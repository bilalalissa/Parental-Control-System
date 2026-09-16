using System.Security.Cryptography;
using System.Text.Json;

namespace ParentalControl.Windows.Core;

public interface ISecretProtector
{
    byte[] Protect(ReadOnlySpan<byte> cleartext);
    byte[] Unprotect(ReadOnlySpan<byte> ciphertext);
}

public sealed record PairedController(
    string Host,
    ushort Port,
    string CertificateFingerprint,
    string ControllerPublicKeyBase64,
    string? PendingPairingCode = null,
    DateTimeOffset? PendingPairingExpiresAt = null);

public sealed record EndpointState(
    string DeviceId,
    string PrivateKeyBase64,
    ulong Sequence,
    ulong SnapshotVersion,
    ulong ControllerSequence,
    PairedController? Controller,
    EndpointRuntimeData? Runtime = null)
{
    public static EndpointState Create()
    {
        byte[] privateKey = new byte[32];
        RandomNumberGenerator.Fill(privateKey);
        try
        {
            return new EndpointState(
                Guid.NewGuid().ToString("D").ToLowerInvariant(),
                Convert.ToBase64String(privateKey), 0, 0, 0, null, new EndpointRuntimeData());
        }
        finally { CryptographicOperations.ZeroMemory(privateKey); }
    }
}

public sealed class EndpointStateStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false,
    };

    private readonly object gate = new();
    private readonly string path;
    private readonly ISecretProtector protector;

    public EndpointStateStore(string path, ISecretProtector protector)
    {
        this.path = path;
        this.protector = protector;
    }

    public EndpointState LoadOrCreate()
    {
        lock (gate)
        {
            if (!File.Exists(path))
            {
                EndpointState initial = EndpointState.Create();
                WriteLocked(initial);
                return initial;
            }

            FileInfo info = new(path);
            if (info.Length is <= 0 or > ProductInfo.MaximumConfigurationBytes)
            {
                throw new InvalidDataException("Protected endpoint configuration has an invalid size.");
            }

            byte[] protectedBytes = File.ReadAllBytes(path);
            byte[] cleartext = protector.Unprotect(protectedBytes);
            try
            {
                EndpointState state = JsonSerializer.Deserialize<EndpointState>(cleartext, JsonOptions)
                    ?? throw new InvalidDataException("Protected endpoint configuration is empty.");
                Validate(state);
                return state;
            }
            finally
            {
                CryptographicOperations.ZeroMemory(cleartext);
            }
        }
    }

    public EndpointState Update(Func<EndpointState, EndpointState> update)
    {
        lock (gate)
        {
            EndpointState current = LoadOrCreateLocked();
            EndpointState next = update(current);
            Validate(next);
            WriteLocked(next);
            return next;
        }
    }

    public EndpointState NextSequence() => Update(value =>
        value.Sequence == ulong.MaxValue
            ? throw new InvalidOperationException("Endpoint sequence is exhausted.")
            : value with { Sequence = value.Sequence + 1 });

    public EndpointState NextSnapshotVersion() => Update(value =>
        value.SnapshotVersion == ulong.MaxValue
            ? throw new InvalidOperationException("Snapshot sequence is exhausted.")
            : value with { SnapshotVersion = value.SnapshotVersion + 1 });

    private EndpointState LoadOrCreateLocked()
    {
        if (!File.Exists(path))
        {
            EndpointState initial = EndpointState.Create();
            WriteLocked(initial);
            return initial;
        }

        byte[] protectedBytes = File.ReadAllBytes(path);
        if (protectedBytes.Length is <= 0 or > ProductInfo.MaximumConfigurationBytes)
        {
            throw new InvalidDataException("Protected endpoint configuration has an invalid size.");
        }
        byte[] cleartext = protector.Unprotect(protectedBytes);
        try
        {
            EndpointState state = JsonSerializer.Deserialize<EndpointState>(cleartext, JsonOptions)
                ?? throw new InvalidDataException("Protected endpoint configuration is empty.");
            Validate(state);
            return state;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(cleartext);
        }
    }

    private void WriteLocked(EndpointState state)
    {
        byte[] cleartext = JsonSerializer.SerializeToUtf8Bytes(state, JsonOptions);
        if (cleartext.Length > ProductInfo.MaximumConfigurationBytes / 2)
        {
            throw new InvalidDataException("Endpoint configuration exceeds its bound.");
        }

        byte[] protectedBytes;
        try { protectedBytes = protector.Protect(cleartext); }
        finally { CryptographicOperations.ZeroMemory(cleartext); }
        if (protectedBytes.Length > ProductInfo.MaximumConfigurationBytes)
        {
            throw new InvalidDataException("Protected endpoint configuration exceeds its bound.");
        }

        string directory = Path.GetDirectoryName(path)
            ?? throw new InvalidOperationException("Configuration path has no directory.");
        Directory.CreateDirectory(directory);
        string temporary = path + ".new";
        File.WriteAllBytes(temporary, protectedBytes);
        File.Move(temporary, path, overwrite: true);
    }

    private static void Validate(EndpointState state)
    {
        if (!Guid.TryParseExact(state.DeviceId, "D", out _) || state.PrivateKeyBase64.Length > 128)
        {
            throw new InvalidDataException("Endpoint identity is invalid.");
        }
        byte[] privateKey;
        try { privateKey = Convert.FromBase64String(state.PrivateKeyBase64); }
        catch (FormatException error) { throw new InvalidDataException("Endpoint key is invalid.", error); }
        try
        {
            if (privateKey.Length != 32) throw new InvalidDataException("Endpoint key is invalid.");
        }
        finally { CryptographicOperations.ZeroMemory(privateKey); }
        if (state.Controller is not null)
        {
            _ = PairingInvitation.ValidateController(
                state.Controller.Host, state.Controller.Port,
                state.Controller.CertificateFingerprint,
                state.Controller.ControllerPublicKeyBase64);
            if (state.Controller.PendingPairingCode is not null
                && (state.Controller.PendingPairingCode.Length != 6
                    || !state.Controller.PendingPairingCode.All(char.IsAsciiDigit)
                    || state.Controller.PendingPairingExpiresAt is null))
            {
                throw new InvalidDataException("Pending pairing metadata is invalid.");
            }
        }
        EndpointRuntimeData runtime = state.Runtime ?? new EndpointRuntimeData();
        if (runtime.ActivityRetentionDays is < 1 or > 30
            || runtime.BrowserRetentionDays is < 1 or > 30
            || runtime.Applications.Count > 64
            || runtime.BrowserTabs.Count > 128
            || runtime.Messages.Count > 200
            || runtime.Outbound.Count > 100)
        {
            throw new InvalidDataException("Endpoint runtime state exceeds its bounds.");
        }
    }
}
