using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using ParentalControl.Windows.Core;

namespace ParentalControl.Windows.App;

internal sealed class WindowsActivityMonitor : IDisposable
{
    private const uint EventSystemForeground = 0x0003;
    private const uint EventObjectCreate = 0x8000;
    private const uint EventObjectHide = 0x8003;
    private const uint WineventOutofcontext = 0x0000;
    private const uint WineventSkipownprocess = 0x0002;
    private const uint GwOwner = 4;
    private readonly EndpointPipeClient client;
    private readonly WinEventDelegate callback;
    private readonly SemaphoreSlim publishGate = new(1, 1);
    private readonly System.Threading.Timer reconciliation;
    private IntPtr foregroundHook;
    private IntPtr windowHook;
    private CancellationTokenSource? debounce;
    private bool enabled;

    internal WindowsActivityMonitor(EndpointPipeClient client)
    {
        this.client = client;
        callback = OnWindowEvent;
        foregroundHook = SetWinEventHook(
            EventSystemForeground, EventSystemForeground, IntPtr.Zero, callback, 0, 0,
            WineventOutofcontext | WineventSkipownprocess);
        windowHook = SetWinEventHook(
            EventObjectCreate, EventObjectHide, IntPtr.Zero, callback, 0, 0,
            WineventOutofcontext | WineventSkipownprocess);
        reconciliation = new System.Threading.Timer(
            _ => SchedulePublish(TimeSpan.Zero), null, TimeSpan.FromMinutes(15), TimeSpan.FromMinutes(15));
    }

    internal bool Enabled
    {
        get => enabled;
        set
        {
            if (enabled == value) return;
            enabled = value;
            if (enabled) SchedulePublish(TimeSpan.Zero);
        }
    }

    private void OnWindowEvent(
        IntPtr hook, uint eventType, IntPtr window, int objectId, int childId,
        uint eventThread, uint eventTime)
    {
        if (!enabled || (objectId != 0 && eventType != EventSystemForeground)) return;
        SchedulePublish(TimeSpan.FromMilliseconds(600));
    }

    private void SchedulePublish(TimeSpan delay)
    {
        if (!enabled) return;
        CancellationTokenSource next = new();
        CancellationTokenSource? former = Interlocked.Exchange(ref debounce, next);
        former?.Cancel();
        former?.Dispose();
        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(delay, next.Token);
                await PublishAsync(next.Token);
            }
            catch (OperationCanceledException) { }
            catch { }
        });
    }

    private async Task PublishAsync(CancellationToken token)
    {
        if (!enabled || !await publishGate.WaitAsync(0, token)) return;
        try
        {
            IReadOnlyList<WindowsApplicationActivity> applications = Collect();
            await client.SendAsync(new PipeRequest("activity.update", Applications: applications), token);
        }
        finally { publishGate.Release(); }
    }

    internal static IReadOnlyList<WindowsApplicationActivity> Collect()
    {
        IntPtr foreground = GetForegroundWindow();
        GetWindowThreadProcessId(foreground, out uint foregroundProcess);
        int sessionId = Process.GetCurrentProcess().SessionId;
        var processIds = new HashSet<uint>();
        EnumWindows((window, _) =>
        {
            if (IsWindowVisible(window) && GetWindow(window, GwOwner) == IntPtr.Zero)
            {
                GetWindowThreadProcessId(window, out uint processId);
                if (processId != 0) processIds.Add(processId);
            }
            return true;
        }, IntPtr.Zero);

        var values = new List<WindowsApplicationActivity>();
        foreach (uint processId in processIds.Take(128))
        {
            try
            {
                using Process process = Process.GetProcessById(checked((int)processId));
                if (process.SessionId != sessionId || process.HasExited) continue;
                string? path = process.MainModule?.FileName;
                if (string.IsNullOrWhiteSpace(path)) continue;
                FileVersionInfo version = FileVersionInfo.GetVersionInfo(path);
                string executable = Path.GetFileName(
                    string.IsNullOrWhiteSpace(version.OriginalFilename)
                        ? path : version.OriginalFilename);
                string identifier = "win32." + NormalizeIdentifier(executable);
                string name = string.IsNullOrWhiteSpace(version.ProductName)
                    ? Path.GetFileNameWithoutExtension(executable) : version.ProductName;
                (string? signing, string? publisher) = SignedIdentity(path);
                values.Add(Stage08Validation.Validate(new WindowsApplicationActivity(
                    identifier, name, signing, publisher, processId == foregroundProcess,
                    DateTimeOffset.UtcNow)));
            }
            catch (Exception error) when (error is ArgumentException or InvalidOperationException
                or System.ComponentModel.Win32Exception or UnauthorizedAccessException
                or CryptographicException or IOException or OverflowException)
            { }
        }
        return values.OrderByDescending(value => value.IsForeground)
            .ThenBy(value => value.ApplicationName, StringComparer.OrdinalIgnoreCase)
            .Take(64).ToArray();
    }

    private static string NormalizeIdentifier(string value)
    {
        string normalized = new(value.ToLowerInvariant().Select(character =>
            char.IsAsciiLetterOrDigit(character) || character is '.' or '-' or '_'
                ? character : '-').ToArray());
        return Stage08Validation.Bound(normalized.Trim('-'), 180);
    }

    private static (string?, string?) SignedIdentity(string path)
    {
        try
        {
            using var certificate = new X509Certificate2(X509Certificate.CreateFromSignedFile(path));
            string signing = "sha256:" + Convert.ToHexString(
                SHA256.HashData(certificate.RawData)).ToLowerInvariant();
            string publisher = "sha256:" + Convert.ToHexString(
                SHA256.HashData(Encoding.UTF8.GetBytes(certificate.Subject))).ToLowerInvariant()[..32];
            return (signing, publisher);
        }
        catch (CryptographicException) { return (null, null); }
    }

    public void Dispose()
    {
        enabled = false;
        CancellationTokenSource? current = Interlocked.Exchange(ref debounce, null);
        current?.Cancel();
        current?.Dispose();
        reconciliation.Dispose();
        if (foregroundHook != IntPtr.Zero) UnhookWinEvent(foregroundHook);
        if (windowHook != IntPtr.Zero) UnhookWinEvent(windowHook);
        publishGate.Dispose();
    }

    private delegate void WinEventDelegate(
        IntPtr hook, uint eventType, IntPtr window, int objectId, int childId,
        uint eventThread, uint eventTime);
    private delegate bool EnumWindowsDelegate(IntPtr window, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern IntPtr SetWinEventHook(
        uint eventMin, uint eventMax, IntPtr module, WinEventDelegate callback,
        uint processId, uint threadId, uint flags);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(EnumWindowsDelegate callback, IntPtr parameter);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr window, uint command);
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
}
