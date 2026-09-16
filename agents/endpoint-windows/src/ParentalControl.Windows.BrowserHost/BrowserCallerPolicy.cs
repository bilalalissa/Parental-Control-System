using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace ParentalControl.Windows.BrowserHost;

internal static class BrowserCallerPolicy
{
    private const uint SnapshotProcesses = 0x00000002;

    internal static bool IsApprovedParent()
    {
        uint parentProcessId = FindParentProcessId(checked((uint)Environment.ProcessId));
        if (parentProcessId == 0) return false;
        try
        {
            using Process parent = Process.GetProcessById(checked((int)parentProcessId));
            string? parentPath = parent.MainModule?.FileName;
            return parentPath is not null && IsApprovedBrowserPath(parentPath);
        }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException
            or System.ComponentModel.Win32Exception or OverflowException
            or NotSupportedException or IOException)
        {
            return false;
        }
    }

    internal static bool IsApprovedBrowserPath(string path)
    {
        string fullPath;
        try
        {
            fullPath = Path.GetFullPath(path);
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException
            or PathTooLongException)
        {
            return false;
        }

        string[] roots =
        [
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
        ];
        string[] browserPaths =
        [
            Path.Combine("Google", "Chrome", "Application", "chrome.exe"),
            Path.Combine("Microsoft", "Edge", "Application", "msedge.exe"),
        ];
        return roots.Where(root => !string.IsNullOrWhiteSpace(root)).Any(root =>
            browserPaths.Any(browser => string.Equals(
                fullPath, Path.GetFullPath(Path.Combine(root, browser)),
                StringComparison.OrdinalIgnoreCase)));
    }

    private static uint FindParentProcessId(uint processId)
    {
        using SafeFileHandle snapshot = CreateToolhelp32Snapshot(SnapshotProcesses, 0);
        if (snapshot.IsInvalid) return 0;
        var entry = new ProcessEntry32 { Size = checked((uint)Marshal.SizeOf<ProcessEntry32>()) };
        if (!Process32First(snapshot, ref entry)) return 0;
        do
        {
            if (entry.ProcessId == processId) return entry.ParentProcessId;
        } while (Process32Next(snapshot, ref entry));
        return 0;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ProcessEntry32
    {
        internal uint Size;
        internal uint Usage;
        internal uint ProcessId;
        internal UIntPtr DefaultHeapId;
        internal uint ModuleId;
        internal uint Threads;
        internal uint ParentProcessId;
        internal int PriorityClassBase;
        internal uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        internal string ExecutableFile;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern SafeFileHandle CreateToolhelp32Snapshot(uint flags, uint processId);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Process32First(SafeFileHandle snapshot, ref ProcessEntry32 entry);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Process32Next(SafeFileHandle snapshot, ref ProcessEntry32 entry);
}
