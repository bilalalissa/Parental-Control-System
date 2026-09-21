namespace ParentalControl.Windows.Core;

public static class ProductInfo
{
    public const string Version = "0.8.0-rc.3";
    public const string ProtocolVersion = "1.0";
    public const int MaximumMessageBytes = 64 * 1024;
    public const int MaximumPipeMessageBytes = 64 * 1024;
    public const int MaximumConfigurationBytes = 1024 * 1024;
    public const int MaximumNetworkInterfaces = 8;
    public const int MaximumAddressesPerInterface = 8;
    public const int MaximumLogBytes = 5 * 1024 * 1024;
    public const string PipeName = "ParentalControl.Windows.Endpoint.v1";
    public const string HubWebSocketPath = "/hub";
    public const string HubWebSocketSubProtocol = "parental-control.v1";
    public const string PrivacyDisclosure = "Shares bounded device, uptime, session, health, private/link-local addresses, informational physical-interface MAC addresses, application names and executable identities, and—when separately enabled—enrolled browser tab titles and query-free origins with the paired parent controller. Text chat and time requests are retained locally in bounded protected storage. It never collects window or page content, URL paths or queries, private tabs, passwords, screenshots, camera, microphone, clipboard, or command lines.";

    public static readonly string[] Capabilities =
    [
        "delta-snapshot",
        "device-info",
        "health",
        "app-activity",
        "browser-tabs",
        "chat",
        "network-metadata",
        "notifications",
        "presence",
        "receipt",
        "request-more-time",
        "session-state",
        "time-request-resolution",
        "uptime",
    ];
}
