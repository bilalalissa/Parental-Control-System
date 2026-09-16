using System.Text.Json;
using System.Net;

namespace ParentalControl.Windows.Core;

public sealed record HubWebSocketEndpoint(Uri Uri, string SubProtocol);

public sealed record PairingInvitation(
    string Code,
    DateTimeOffset ExpiresAt,
    string Host,
    int Port,
    string CertificateFingerprint,
    byte[] ControllerPublicKey)
{
    public HubWebSocketEndpoint HubWebSocketEndpoint =>
        CreateHubWebSocketEndpoint(Host, checked((ushort)Port));

    public static HubWebSocketEndpoint CreateHubWebSocketEndpoint(string host, ushort port)
    {
        if (!IsValidHost(host) || port == 0)
        {
            throw new InvalidDataException("The paired controller endpoint is invalid.");
        }

        var uri = new UriBuilder(Uri.UriSchemeWss, host, port, ProductInfo.HubWebSocketPath).Uri;
        return new HubWebSocketEndpoint(uri, ProductInfo.HubWebSocketSubProtocol);
    }

    public static bool ValidateController(
        string host, ushort port, string fingerprint, string publicKeyBase64)
    {
        if (!IsValidHost(host)
            || port == 0 || NormalizeFingerprint(fingerprint).Length != 64)
        {
            throw new InvalidDataException("The paired controller metadata is invalid.");
        }
        try
        {
            if (Convert.FromBase64String(publicKeyBase64).Length != 32)
                throw new InvalidDataException("The paired controller key is invalid.");
        }
        catch (FormatException error)
        {
            throw new InvalidDataException("The paired controller key is invalid.", error);
        }
        return true;
    }

    public static PairingInvitation FromToken(string token, DateTimeOffset? now = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(token);
        byte[] encoded;
        try
        {
            encoded = Convert.FromBase64String(token.Trim());
        }
        catch (FormatException error)
        {
            throw new InvalidDataException("The pairing invitation is not valid base64.", error);
        }

        if (encoded.Length is 0 or > 8 * 1024)
        {
            throw new InvalidDataException("The pairing invitation has an invalid size.");
        }

        using var document = JsonDocument.Parse(encoded);
        var root = document.RootElement;
        var code = root.GetProperty("code").GetString() ?? string.Empty;
        var host = root.GetProperty("host").GetString() ?? string.Empty;
        var port = root.GetProperty("port").GetInt32();
        var fingerprint = NormalizeFingerprint(
            root.GetProperty("certificateFingerprint").GetString() ?? string.Empty);
        var publicKeyText = root.GetProperty("controllerPublicKey").GetString() ?? string.Empty;
        var milliseconds = root.GetProperty("expiresAt").GetDouble();
        var expiresAt = DateTimeOffset.FromUnixTimeMilliseconds(checked((long)milliseconds));

        byte[] publicKey;
        try
        {
            publicKey = Convert.FromBase64String(publicKeyText);
        }
        catch (FormatException error)
        {
            throw new InvalidDataException("The controller public key is malformed.", error);
        }

        if (code.Length != 6 || !code.All(char.IsAsciiDigit))
        {
            throw new InvalidDataException("The pairing code must contain exactly six digits.");
        }

        if (!IsValidHost(host))
        {
            throw new InvalidDataException("The controller host is invalid.");
        }

        if (port is < 1 or > 65535 || fingerprint.Length != 64 || publicKey.Length != 32)
        {
            throw new InvalidDataException("The pairing invitation has invalid security metadata.");
        }

        var reference = now ?? DateTimeOffset.UtcNow;
        if (expiresAt <= reference || expiresAt > reference.AddMinutes(10))
        {
            throw new InvalidDataException("The pairing invitation is expired or exceeds ten minutes.");
        }

        return new PairingInvitation(code, expiresAt, host, port, fingerprint, publicKey);
    }

    public static string NormalizeFingerprint(string value)
    {
        if (value.Any(character => !char.IsAsciiHexDigit(character)
            && character is not ':' and not '-' && !char.IsWhiteSpace(character))) return string.Empty;
        var normalized = new string(value.Where(char.IsAsciiHexDigit).ToArray()).ToUpperInvariant();
        return normalized.Length == 64 ? normalized : string.Empty;
    }

    private static bool IsValidHost(string host) =>
        host.Length is > 0 and <= 253
        && !host.Any(character => char.IsControl(character) || char.IsWhiteSpace(character))
        && (IPAddress.TryParse(host, out _) || Uri.CheckHostName(host) == UriHostNameType.Dns);
}
