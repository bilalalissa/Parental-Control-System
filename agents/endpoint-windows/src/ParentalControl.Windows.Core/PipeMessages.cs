using System.Text.Json;

namespace ParentalControl.Windows.Core;

public sealed record PipeRequest(
    string Operation,
    string? Invitation = null,
    IReadOnlyList<WindowsApplicationActivity>? Applications = null,
    BrowserNativeRequest? Browser = null,
    string? Text = null,
    string? Audience = null,
    Guid? ThreadId = null,
    int? Minutes = null,
    string? Note = null);

public sealed record PipeResponse(
    bool Success,
    string? Error,
    EndpointDashboardStatus? Status = null,
    BrowserNativeResponse? Browser = null);

public sealed record EndpointDashboardStatus(
    string ProductVersion,
    bool ServiceHealthy,
    bool Paired,
    bool PairingPending,
    string ConnectionState,
    string DeviceName,
    string DeviceId,
    string OperatingSystem,
    string Architecture,
    string SessionState,
    long UptimeSeconds,
    IReadOnlyList<NetworkSnapshot> Networks,
    IReadOnlyList<string> Capabilities,
    string PrivacyDisclosure,
    bool ActivityCollectionEnabled,
    int ActivityRetentionDays,
    bool BrowserCollectionEnabled,
    int BrowserRetentionDays,
    IReadOnlyList<WindowsApplicationActivity> Applications,
    IReadOnlyList<WindowsBrowserTab> BrowserTabs,
    IReadOnlyList<WindowsChatMessage> Messages,
    WindowsTimeRequest? LatestTimeRequest);

public static class PipeCodec
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    public static byte[] Encode<T>(T value)
    {
        byte[] data = JsonSerializer.SerializeToUtf8Bytes(value, Options);
        if (data.Length > ProductInfo.MaximumPipeMessageBytes)
            throw new InvalidDataException("Local request exceeds the size limit.");
        return data;
    }

    public static T Decode<T>(ReadOnlySpan<byte> data)
    {
        if (data.Length is <= 0 or > ProductInfo.MaximumPipeMessageBytes)
            throw new InvalidDataException("Local request has an invalid size.");
        return JsonSerializer.Deserialize<T>(data, Options)
            ?? throw new InvalidDataException("Local request is empty.");
    }
}
