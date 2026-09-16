using System.Net;
using System.Net.NetworkInformation;
using System.Text.Json.Nodes;

namespace ParentalControl.Windows.Core;

public sealed record NetworkSnapshot(string Interface, IReadOnlyList<string> Addresses, string? MacAddress);

public sealed record EndpointSnapshot(
    string State,
    string DeviceName,
    string Model,
    string OperatingSystem,
    string Architecture,
    long UptimeSeconds,
    DateTimeOffset BootTime,
    string SessionState,
    IReadOnlyList<NetworkSnapshot> Networks,
    bool DaemonHealthy)
{
    public JsonObject ToJson() => new()
    {
        ["state"] = State,
        ["deviceName"] = DeviceName,
        ["model"] = Model,
        ["operatingSystem"] = OperatingSystem,
        ["architecture"] = Architecture,
        ["uptimeSeconds"] = UptimeSeconds,
        ["bootTime"] = BootTime.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"),
        ["sessionState"] = SessionState,
        ["networks"] = new JsonArray(Networks.Select(network => (JsonNode)new JsonObject
        {
            ["interface"] = network.Interface,
            ["addresses"] = new JsonArray(network.Addresses.Select(value => JsonValue.Create(value)).ToArray()),
            ["macAddress"] = network.MacAddress,
        }).ToArray()),
        ["daemonHealthy"] = DaemonHealthy,
    };
}

public static class NetworkMetadata
{
    public static IReadOnlyList<NetworkSnapshot> Collect()
    {
        var result = new List<NetworkSnapshot>();
        foreach (NetworkInterface network in NetworkInterface.GetAllNetworkInterfaces()
                     .Where(item => item.NetworkInterfaceType is NetworkInterfaceType.Ethernet
                         or NetworkInterfaceType.Wireless80211)
                     .OrderBy(item => item.Name, StringComparer.Ordinal)
                     .Take(ProductInfo.MaximumNetworkInterfaces))
        {
            try
            {
                IReadOnlyList<string> addresses = network.GetIPProperties().UnicastAddresses
                    .Select(item => item.Address)
                    .Where(IsPrivateOrLinkLocal)
                    .Select(item => item.ToString())
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .OrderBy(item => item, StringComparer.Ordinal)
                    .Take(ProductInfo.MaximumAddressesPerInterface)
                    .ToArray();
                string mac = network.GetPhysicalAddress().ToString();
                result.Add(new NetworkSnapshot(
                    Bound(network.Name, 64), addresses,
                    mac.Length == 12 ? string.Join(":", Enumerable.Range(0, 6).Select(i => mac.Substring(i * 2, 2))) : null));
            }
            catch (NetworkInformationException) { }
        }
        return result;
    }

    public static bool IsPrivateOrLinkLocal(IPAddress address)
    {
        byte[] bytes = address.GetAddressBytes();
        if (address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
        {
            return bytes[0] == 10
                || (bytes[0] == 172 && bytes[1] is >= 16 and <= 31)
                || (bytes[0] == 192 && bytes[1] == 168)
                || (bytes[0] == 169 && bytes[1] == 254);
        }

        return address.IsIPv6LinkLocal
            || (bytes.Length == 16 && (bytes[0] & 0xfe) == 0xfc);
    }

    private static string Bound(string value, int limit) => value.Length <= limit ? value : value[..limit];
}

public sealed class SnapshotDelta
{
    private JsonObject previous = new();

    public JsonObject Changed(JsonObject current)
    {
        var changed = new JsonObject();
        foreach ((string key, JsonNode? value) in current)
        {
            if (!JsonNode.DeepEquals(previous[key], value)) changed[key] = value?.DeepClone();
        }
        foreach (string key in previous.Select(item => item.Key).Except(current.Select(item => item.Key)))
        {
            changed[key] = null;
        }
        previous = (JsonObject)current.DeepClone();
        return changed;
    }
}
