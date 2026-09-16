using System.Runtime.InteropServices;
using Microsoft.Win32;
using ParentalControl.Windows.Core;
using System.ServiceProcess;

namespace ParentalControl.Windows.Service;

internal sealed class WindowsInventory
{
    private string sessionState = WTSGetActiveConsoleSessionId() == uint.MaxValue ? "no-user" : "signed-in";

    [DllImport("kernel32.dll")]
    private static extern uint WTSGetActiveConsoleSessionId();

    internal void SetSessionState(SessionChangeReason reason) =>
        sessionState = SessionStateMapper.FromServiceReason(reason.ToString());

    internal EndpointSnapshot Collect()
    {
        long uptime = Math.Max(0, Environment.TickCount64 / 1000);
        DateTimeOffset boot = DateTimeOffset.UtcNow.AddSeconds(-uptime);
        string model;
        try
        {
            model = Registry.GetValue(
                @"HKEY_LOCAL_MACHINE\HARDWARE\DESCRIPTION\System\BIOS", "SystemProductName", null)
                as string ?? "Windows PC";
        }
        catch { model = "Windows PC"; }
        return new EndpointSnapshot(
            "online",
            Bound(Environment.MachineName, 80),
            Bound(model, 80),
            Bound(RuntimeInformation.OSDescription, 120),
            RuntimeInformation.OSArchitecture.ToString().ToLowerInvariant(),
            uptime,
            boot,
            sessionState,
            NetworkMetadata.Collect(),
            true);
    }

    private static string Bound(string value, int limit) => value.Length <= limit ? value : value[..limit];
}
