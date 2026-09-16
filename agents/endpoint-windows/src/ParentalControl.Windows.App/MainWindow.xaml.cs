using System.Diagnostics;
using System.Security.Principal;
using System.Windows;
using ParentalControl.Windows.Core;

namespace ParentalControl.Windows.App;

public partial class MainWindow : Window
{
    private readonly EndpointPipeClient client = new();

    public MainWindow()
    {
        InitializeComponent();
        Loaded += async (_, _) => await RefreshAsync();
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e) => await RefreshAsync();

    private async void Pair_Click(object sender, RoutedEventArgs e)
    {
        using WindowsIdentity identity = WindowsIdentity.GetCurrent();
        if (!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
        {
            PairingResult.Text = "Approve the Windows prompt, then paste the invitation again in the elevated window.";
            try
            {
                Process.Start(new ProcessStartInfo(Environment.ProcessPath!)
                {
                    UseShellExecute = true,
                    Verb = "runas",
                });
            }
            catch { PairingResult.Text = "Administrator authorization was cancelled."; }
            return;
        }
        PairingResult.Text = "Pairing…";
        try
        {
            PipeResponse response = await client.SendAsync(new PipeRequest("pair", InvitationText.Text.Trim()));
            PairingResult.Text = response.Success ? "Invitation accepted. Connecting to the parent…" : response.Error;
            if (response.Success) InvitationText.Clear();
            if (response.Status is not null) Render(response.Status);
        }
        catch { PairingResult.Text = "The endpoint service is unavailable."; }
    }

    private async Task RefreshAsync()
    {
        try
        {
            PipeResponse response = await client.SendAsync(new PipeRequest("status"));
            if (response.Success && response.Status is not null) Render(response.Status);
            else ServiceValue.Text = response.Error ?? "Service unavailable";
        }
        catch
        {
            ServiceValue.Text = "Service unavailable";
            ControllerValue.Text = "Offline";
        }
    }

    private void Render(EndpointDashboardStatus status)
    {
        ServiceValue.Text = $"Healthy · version {status.ProductVersion}";
        ControllerValue.Text = status.Paired || status.PairingPending
            ? status.ConnectionState
            : status.ConnectionState == "Pairing invitation expired"
                ? status.ConnectionState
                : "Not paired";
        DeviceValue.Text = $"{status.DeviceName} · {status.DeviceId}";
        SystemValue.Text = status.OperatingSystem;
        ArchitectureValue.Text = status.Architecture;
        SessionValue.Text = status.SessionState;
        UptimeValue.Text = TimeSpan.FromSeconds(status.UptimeSeconds).ToString("d'.'hh':'mm':'ss");
        PrivacyValue.Text = status.PrivacyDisclosure;
        NetworkValue.Text = status.Networks.Count == 0
            ? "No bounded private/link-local interface metadata available."
            : string.Join(Environment.NewLine, status.Networks.Select(item =>
                $"{item.Interface}: {string.Join(", ", item.Addresses)}"));
    }
}
