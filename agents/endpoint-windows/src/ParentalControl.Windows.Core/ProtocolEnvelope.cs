using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;
using Org.BouncyCastle.Security;

namespace ParentalControl.Windows.Core;

public sealed record ProtocolAuthentication(string Algorithm, string KeyId, string Signature);

public sealed record ProtocolEnvelope(
    Guid Id,
    string ProtocolVersion,
    string DeviceId,
    DateTimeOffset SentAt,
    DateTimeOffset? ExpiresAt,
    ulong Sequence,
    string Type,
    JsonObject Payload,
    ProtocolAuthentication Auth)
{
    public static ProtocolEnvelope CreateUnsigned(
        string deviceId,
        ulong sequence,
        string type,
        JsonObject payload,
        string keyId,
        DateTimeOffset? now = null,
        TimeSpan? lifetime = null,
        Guid? id = null)
    {
        var sentAt = (now ?? DateTimeOffset.UtcNow).ToUniversalTime();
        return new ProtocolEnvelope(
            id ?? Guid.NewGuid(),
            ProductInfo.ProtocolVersion,
            deviceId,
            sentAt,
            lifetime is null ? null : sentAt.Add(lifetime.Value),
            sequence,
            type,
            payload,
            new ProtocolAuthentication("Ed25519", keyId, string.Empty));
    }
}

public static class ProtocolCodec
{
    private static readonly HashSet<string> AllowedTypes =
    [
        "capability.announce",
        "snapshot.request",
        "snapshot.response",
        "activity.update",
        "activity.configuration",
        "application.restriction-event",
        "browser.update",
        "browser.configuration",
        "policy.apply",
        "policy.query",
        "chat.message",
        "chat.mutation",
        "time.request",
        "time.request-resolution",
        "action.lock",
        "action.unlock-temporary",
        "action.logoff",
        "action.restart",
        "action.shutdown",
        "bonus.grant",
        "bonus.revoke",
        "adult-verifier.rotate",
        "diagnostics.request",
        "receipt",
    ];

    public static byte[] SigningData(ProtocolEnvelope envelope)
    {
        var node = new JsonObject
        {
            ["algorithm"] = envelope.Auth.Algorithm,
            ["deviceId"] = envelope.DeviceId,
            ["id"] = envelope.Id.ToString().ToUpperInvariant(),
            ["keyId"] = envelope.Auth.KeyId,
            ["payload"] = envelope.Payload.DeepClone(),
            ["protocolVersion"] = envelope.ProtocolVersion,
            ["sentAt"] = FormatDate(envelope.SentAt),
            ["sequence"] = envelope.Sequence,
            ["type"] = envelope.Type,
        };
        if (envelope.ExpiresAt is not null)
        {
            node["expiresAt"] = FormatDate(envelope.ExpiresAt.Value);
        }

        return CanonicalJson.Serialize(node);
    }

    public static byte[] Encode(ProtocolEnvelope envelope)
    {
        var node = new JsonObject
        {
            ["auth"] = new JsonObject
            {
                ["algorithm"] = envelope.Auth.Algorithm,
                ["keyId"] = envelope.Auth.KeyId,
                ["signature"] = envelope.Auth.Signature,
            },
            ["deviceId"] = envelope.DeviceId,
            ["id"] = envelope.Id.ToString().ToUpperInvariant(),
            ["payload"] = envelope.Payload.DeepClone(),
            ["protocolVersion"] = envelope.ProtocolVersion,
            ["sentAt"] = FormatDate(envelope.SentAt),
            ["sequence"] = envelope.Sequence,
            ["type"] = envelope.Type,
        };
        if (envelope.ExpiresAt is not null)
        {
            node["expiresAt"] = FormatDate(envelope.ExpiresAt.Value);
        }

        var data = CanonicalJson.Serialize(node);
        if (data.Length > ProductInfo.MaximumMessageBytes)
        {
            throw new InvalidDataException("The protocol message exceeds 64 KiB.");
        }

        return data;
    }

    public static ProtocolEnvelope Decode(ReadOnlySpan<byte> data)
    {
        if (data.Length is 0 or > ProductInfo.MaximumMessageBytes)
        {
            throw new InvalidDataException("The protocol message has an invalid size.");
        }

        using var document = JsonDocument.Parse(data.ToArray());
        var root = document.RootElement;
        string[] required = ["auth", "deviceId", "id", "payload", "protocolVersion", "sentAt", "sequence", "type"];
        string[] names = root.ValueKind == JsonValueKind.Object
            ? root.EnumerateObject().Select(property => property.Name).ToArray() : [];
        if (root.ValueKind != JsonValueKind.Object || names.Length is < 8 or > 9
            || names.Distinct(StringComparer.Ordinal).Count() != names.Length
            || required.Any(name => !names.Contains(name, StringComparer.Ordinal))
            || names.Any(name => !required.Contains(name, StringComparer.Ordinal) && name != "expiresAt"))
        {
            throw new InvalidDataException("The protocol envelope shape is invalid.");
        }

        var protocolVersion = root.GetProperty("protocolVersion").GetString() ?? string.Empty;
        var deviceId = root.GetProperty("deviceId").GetString() ?? string.Empty;
        var type = root.GetProperty("type").GetString() ?? string.Empty;
        var authElement = root.GetProperty("auth");
        string[] authNames = authElement.ValueKind == JsonValueKind.Object
            ? authElement.EnumerateObject().Select(property => property.Name).ToArray() : [];
        if (authNames.Length != 3 || authNames.Distinct(StringComparer.Ordinal).Count() != 3
            || !new[] { "algorithm", "keyId", "signature" }.All(name => authNames.Contains(name, StringComparer.Ordinal)))
        {
            throw new InvalidDataException("The protocol authentication shape is invalid.");
        }
        var auth = new ProtocolAuthentication(
            authElement.GetProperty("algorithm").GetString() ?? string.Empty,
            authElement.GetProperty("keyId").GetString() ?? string.Empty,
            authElement.GetProperty("signature").GetString() ?? string.Empty);
        var payload = JsonNode.Parse(root.GetProperty("payload").GetRawText()) as JsonObject
            ?? throw new InvalidDataException("The protocol payload must be an object.");
        var expiresAt = root.TryGetProperty("expiresAt", out var expires)
            ? ParseDate(expires.GetString())
            : null;
        var envelope = new ProtocolEnvelope(
            root.GetProperty("id").GetGuid(),
            protocolVersion,
            deviceId,
            ParseDate(root.GetProperty("sentAt").GetString())
                ?? throw new InvalidDataException("The sentAt timestamp is invalid."),
            expiresAt,
            root.GetProperty("sequence").GetUInt64(),
            type,
            payload,
            auth);
        ValidateEnvelope(envelope);
        return envelope;
    }

    public static void ValidateEnvelope(ProtocolEnvelope envelope, DateTimeOffset? now = null)
    {
        if (envelope.ProtocolVersion != ProductInfo.ProtocolVersion || !AllowedTypes.Contains(envelope.Type))
        {
            throw new InvalidDataException("The protocol version or message type is unsupported.");
        }

        if (!IsIdentifier(envelope.DeviceId, 128) || !IsIdentifier(envelope.Auth.KeyId, 128)
            || envelope.Auth.Algorithm != "Ed25519")
        {
            throw new InvalidDataException("The protocol identity metadata is invalid.");
        }

        if (envelope.Payload.Count > 64)
        {
            throw new InvalidDataException("The protocol payload exceeds 64 fields.");
        }

        var reference = now ?? DateTimeOffset.UtcNow;
        if (envelope.SentAt > reference.AddMinutes(2)
            || (envelope.ExpiresAt is not null
                && (envelope.ExpiresAt <= reference || envelope.ExpiresAt <= envelope.SentAt))
            || (envelope.ExpiresAt is null && reference - envelope.SentAt > TimeSpan.FromMinutes(2)))
        {
            throw new InvalidDataException("The protocol message is expired or from the future.");
        }

        byte[] signature;
        try
        {
            signature = Convert.FromBase64String(envelope.Auth.Signature);
        }
        catch (FormatException error)
        {
            throw new InvalidDataException("The protocol signature is malformed.", error);
        }

        if (signature.Length != 64)
        {
            throw new InvalidDataException("The protocol signature must be 64 bytes.");
        }
    }

    public static string FormatDate(DateTimeOffset value) =>
        value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", System.Globalization.CultureInfo.InvariantCulture);

    private static DateTimeOffset? ParseDate(string? value) =>
        DateTimeOffset.TryParseExact(
            value,
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.AssumeUniversal
                | System.Globalization.DateTimeStyles.AdjustToUniversal,
            out var parsed)
            ? parsed
            : null;

    private static bool IsIdentifier(string value, int maximumBytes)
    {
        if (value.Length < 3 || Encoding.UTF8.GetByteCount(value) > maximumBytes || !char.IsAsciiLetterOrDigit(value[0]))
        {
            return false;
        }

        return value.All(character => char.IsAsciiLetterOrDigit(character) || character is '.' or '_' or '-');
    }
}

public sealed class Ed25519DeviceIdentity
{
    private readonly Ed25519PrivateKeyParameters privateKey;

    public Ed25519DeviceIdentity(string keyId, ReadOnlySpan<byte> seed)
    {
        if (seed.Length != 32 || string.IsNullOrWhiteSpace(keyId))
        {
            throw new ArgumentException("An Ed25519 identity requires a key ID and a 32-byte seed.");
        }

        KeyId = keyId;
        privateKey = new Ed25519PrivateKeyParameters(seed);
    }

    public string KeyId { get; }

    public byte[] PublicKey => privateKey.GeneratePublicKey().GetEncoded();

    public static byte[] GenerateSeed()
    {
        var key = new Ed25519PrivateKeyParameters(new SecureRandom());
        return key.GetEncoded();
    }

    public ProtocolEnvelope Sign(ProtocolEnvelope unsigned)
    {
        if (unsigned.Auth.KeyId != KeyId)
        {
            throw new InvalidOperationException("The message key ID does not match this identity.");
        }

        var data = ProtocolCodec.SigningData(unsigned);
        var signer = new Ed25519Signer();
        signer.Init(true, privateKey);
        signer.BlockUpdate(data, 0, data.Length);
        var signature = signer.GenerateSignature();
        return unsigned with
        {
            Auth = unsigned.Auth with { Signature = Convert.ToBase64String(signature) },
        };
    }

    public static bool Verify(ProtocolEnvelope envelope, ReadOnlySpan<byte> publicKey)
    {
        if (publicKey.Length != 32)
        {
            return false;
        }

        byte[] signature;
        try
        {
            signature = Convert.FromBase64String(envelope.Auth.Signature);
        }
        catch (FormatException)
        {
            return false;
        }

        var signer = new Ed25519Signer();
        signer.Init(false, new Ed25519PublicKeyParameters(publicKey));
        var data = ProtocolCodec.SigningData(envelope);
        signer.BlockUpdate(data, 0, data.Length);
        return signer.VerifySignature(signature);
    }
}

public static class CanonicalJson
{
    public static byte[] Serialize(JsonNode node)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(
                   stream,
                   new JsonWriterOptions
                   {
                       Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
                       Indented = false,
                       SkipValidation = false,
                   }))
        {
            WriteNode(writer, node);
        }

        return stream.ToArray();
    }

    private static void WriteNode(Utf8JsonWriter writer, JsonNode? node)
    {
        switch (node)
        {
            case null:
                writer.WriteNullValue();
                break;
            case JsonObject value:
                writer.WriteStartObject();
                foreach (var property in value.OrderBy(item => item.Key, StringComparer.Ordinal))
                {
                    writer.WritePropertyName(property.Key);
                    WriteNode(writer, property.Value);
                }
                writer.WriteEndObject();
                break;
            case JsonArray value:
                writer.WriteStartArray();
                foreach (var item in value)
                {
                    WriteNode(writer, item);
                }
                writer.WriteEndArray();
                break;
            case JsonValue value:
                value.WriteTo(writer);
                break;
            default:
                throw new InvalidDataException("Unsupported JSON node.");
        }
    }
}
