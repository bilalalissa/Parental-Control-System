namespace ParentalControl.Windows.Core;

public static class ProductInfo
{
    public const string Version = "0.7.0-rc.2";
    public const string ProtocolVersion = "1.0";
    public const int MaximumMessageBytes = 64 * 1024;
    public const int MaximumPipeMessageBytes = 16 * 1024;
    public const int MaximumConfigurationBytes = 64 * 1024;
    public const int MaximumNetworkInterfaces = 8;
    public const int MaximumAddressesPerInterface = 8;
    public const int MaximumLogBytes = 5 * 1024 * 1024;
    public const string PipeName = "ParentalControl.Windows.Endpoint.v1";
    public const string HubWebSocketPath = "/hub";
    public const string HubWebSocketSubProtocol = "parental-control.v1";
    public const string PrivacyDisclosure = "Shares bounded device, uptime, session, health, private/link-local addresses, and informational physical-interface MAC addresses with the paired parent controller. It does not collect application activity, browser tabs, page content, chat, passwords, screenshots, camera, microphone, clipboard, or command lines.";

    public static readonly string[] Capabilities =
    [
        "delta-snapshot",
        "device-info",
        "health",
        "network-metadata",
        "presence",
        "receipt",
        "session-state",
        "uptime",
    ];
}
