using System.Diagnostics;
using System.Security.Principal;
using System.Windows;
using System.Windows.Threading;
using ParentalControl.Windows.Core;

namespace ParentalControl.Windows.App;

public partial class MainWindow : Window
{
    private readonly EndpointPipeClient client = new();
    private readonly WindowsActivityMonitor activityMonitor;
    private readonly DispatcherTimer refreshTimer;
    private readonly System.Windows.Forms.NotifyIcon notificationIcon;
    private readonly HashSet<Guid> announcedMessages = [];
    private readonly Guid directThread = Guid.NewGuid();
    private bool firstRefresh = true;
    private bool refreshing;

    public MainWindow()
    {
        InitializeComponent();
        activityMonitor = new WindowsActivityMonitor(client);
        notificationIcon = new System.Windows.Forms.NotifyIcon
        {
            Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!),
            Text = "Parental Control Child",
            Visible = true,
        };
        notificationIcon.Click += (_, _) => Dispatcher.Invoke(() =>
        {
            Show();
            WindowState = WindowState.Normal;
            Activate();
        });
        refreshTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
        refreshTimer.Tick += async (_, _) => await RefreshAsync();
        Loaded += async (_, _) =>
        {
            await RefreshAsync();
            refreshTimer.Start();
        };
        Closed += (_, _) =>
        {
            refreshTimer.Stop();
            activityMonitor.Dispose();
            notificationIcon.Visible = false;
            notificationIcon.Dispose();
        };
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

    private async void SendChat_Click(object sender, RoutedEventArgs e)
    {
        string text = ChatDraft.Text.Trim();
        if (text.Length == 0) return;
        ChatResult.Text = "Sending…";
        try
        {
            PipeResponse response = await client.SendAsync(new PipeRequest(
                "chat.send", Text: text, Audience: "direct", ThreadId: directThread));
            ChatResult.Text = response.Success ? "Queued for authenticated delivery." : response.Error;
            if (response.Success) ChatDraft.Clear();
            if (response.Status is not null) Render(response.Status);
        }
        catch { ChatResult.Text = "The endpoint service is unavailable."; }
    }

    private async void MarkRead_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            PipeResponse response = await client.SendAsync(new PipeRequest("chat.read"));
            ChatResult.Text = response.Success ? "Parent messages marked read." : response.Error;
            if (response.Status is not null) Render(response.Status);
        }
        catch { ChatResult.Text = "The endpoint service is unavailable."; }
    }

    private async void RequestTime_Click(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(MinutesText.Text, out int minutes) || minutes is < 5 or > 240)
        {
            TimeRequestResult.Text = "Enter 5–240 minutes.";
            return;
        }
        TimeRequestResult.Text = "Sending…";
        try
        {
            PipeResponse response = await client.SendAsync(new PipeRequest(
                "time.request", Minutes: minutes, Note: TimeNote.Text.Trim()));
            TimeRequestResult.Text = response.Success ? "Request queued for your parent." : response.Error;
            if (response.Success) TimeNote.Clear();
            if (response.Status is not null) Render(response.Status);
        }
        catch { TimeRequestResult.Text = "The endpoint service is unavailable."; }
    }

    private async Task RefreshAsync()
    {
        if (refreshing) return;
        refreshing = true;
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
            activityMonitor.Enabled = false;
        }
        finally { refreshing = false; }
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

        activityMonitor.Enabled = status.ActivityCollectionEnabled;
        ActivitySummary.Text = status.ActivityCollectionEnabled
            ? $"Enabled by parent · {status.ActivityRetentionDays}-day retention · {status.Applications.Count} recently observed applications"
            : "Disabled by parent; collection and retained application observations are cleared.";
        ApplicationList.ItemsSource = status.Applications.Select(item =>
            $"{(item.IsForeground ? "Foreground" : "Running")} · {item.ApplicationName} · {item.BundleIdentifier}"
        ).ToArray();
        BrowserSummary.Text = status.BrowserCollectionEnabled
            ? $"Enabled by parent · {status.BrowserRetentionDays}-day retention · {status.BrowserTabs.Count} enrolled-profile tabs"
            : "Disabled by parent; the extension reports no tab metadata.";
        BrowserList.ItemsSource = status.BrowserTabs.Select(item =>
            $"{(item.IsActive ? "Active" : "Open")} · {item.Browser} · {item.Title} · {item.Origin}"
        ).ToArray();
        ChatList.ItemsSource = status.Messages.OrderBy(item => item.SentAt).Select(item =>
            $"{item.SentAt.ToLocalTime():g} · {item.Sender} · {(item.DeletedAt is null ? item.Text : "Message deleted")} · {item.State}"
        ).ToArray();
        if (status.LatestTimeRequest is { } request)
        {
            TimeRequestResult.Text = request.State == "pending"
                ? $"Pending request for {request.RequestedMinutes} minutes."
                : $"Latest request: {request.State}.";
        }

        foreach (WindowsChatMessage message in status.Messages.Where(item => item.IsFromParent))
        {
            if (!announcedMessages.Add(message.Id) || firstRefresh) continue;
            notificationIcon.BalloonTipTitle = "Message from parent";
            notificationIcon.BalloonTipText = "Open Parental Control Child to read the new message.";
            notificationIcon.ShowBalloonTip(5_000);
        }
        firstRefresh = false;
    }
}
