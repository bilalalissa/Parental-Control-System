using System.IO.Pipes;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using ParentalControl.Windows.Core;

namespace ParentalControl.Windows.Service;

internal sealed class NamedPipeEndpointServer
{
    private readonly EndpointRuntime runtime;
    private readonly BoundedFileLog log;

    internal NamedPipeEndpointServer(EndpointRuntime runtime, BoundedFileLog log)
    {
        this.runtime = runtime;
        this.log = log;
    }

    internal async Task RunAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await using NamedPipeServerStream pipe = CreatePipe();
                await pipe.WaitForConnectionAsync(cancellationToken);
                await HandleAsync(pipe, cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
            catch (Exception error)
            {
                log.Write("pipe.error", error.GetType().Name);
                await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken);
            }
        }
    }

    private static NamedPipeServerStream CreatePipe()
    {
        var security = new PipeSecurity();
        security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        security.AddAccessRule(new PipeAccessRule(
            new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
            PipeAccessRights.FullControl, AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(
            new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
            PipeAccessRights.FullControl, AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(
            new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null),
            PipeAccessRights.ReadWrite, AccessControlType.Allow));
        return NamedPipeServerStreamAcl.Create(
            ProductInfo.PipeName, PipeDirection.InOut, 4,
            PipeTransmissionMode.Byte, PipeOptions.Asynchronous,
            ProductInfo.MaximumPipeMessageBytes, ProductInfo.MaximumPipeMessageBytes, security);
    }

    private async Task HandleAsync(NamedPipeServerStream pipe, CancellationToken cancellationToken)
    {
        using var requestTimeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        requestTimeout.CancelAfter(TimeSpan.FromSeconds(5));
        CancellationToken requestToken = requestTimeout.Token;
        byte[] prefix = new byte[4];
        await ReadExactlyAsync(pipe, prefix, requestToken);
        int count = System.Buffers.Binary.BinaryPrimitives.ReadInt32BigEndian(prefix);
        if (count is <= 0 or > ProductInfo.MaximumPipeMessageBytes)
            throw new InvalidDataException("Local request has an invalid size.");
        byte[] buffer = new byte[count];
        await ReadExactlyAsync(pipe, buffer, requestToken);
        PipeResponse response;
        try
        {
            PipeRequest request = PipeCodec.Decode<PipeRequest>(buffer);
            bool activeConsoleClient = IsActiveConsoleClient(pipe);
            bool childApplicationClient = activeConsoleClient && IsExpectedClient(
                pipe, "ParentalControl.Windows.App.exe");
            bool browserHostClient = activeConsoleClient && IsExpectedClient(
                pipe, "ParentalControl.Windows.BrowserHost.exe");
            response = request.Operation switch
            {
                "health" => new PipeResponse(true, null),
                "status" when childApplicationClient => new PipeResponse(true, null, runtime.Status()),
                "pair" when childApplicationClient && IsAdministrator(pipe) && request.Invitation is not null =>
                    runtime.Pair(request.Invitation),
                "pair" => new PipeResponse(false, "Pairing requires an elevated adult administrator session."),
                "activity.update" when childApplicationClient =>
                    runtime.UpdateApplications(request.Applications),
                "browser.native" when browserHostClient => runtime.HandleBrowser(request.Browser),
                "chat.send" when childApplicationClient =>
                    runtime.QueueChat(request.Text, request.Audience, request.ThreadId),
                "chat.read" when childApplicationClient => runtime.MarkChatRead(),
                "time.request" when childApplicationClient =>
                    runtime.RequestMoreTime(request.Minutes, request.Note),
                "status" or "activity.update" or "browser.native" or "chat.send" or "chat.read"
                    or "time.request" =>
                    new PipeResponse(false, "The request must come from an authorized installed client in the active interactive session."),
                _ => new PipeResponse(false, "Unsupported local operation."),
            };
        }
        catch (Exception error)
        {
            response = new PipeResponse(false, error is InvalidDataException
                ? error.Message : "The local request could not be completed.");
        }

        byte[] encoded = PipeCodec.Encode(response);
        System.Buffers.Binary.BinaryPrimitives.WriteInt32BigEndian(prefix, encoded.Length);
        await pipe.WriteAsync(prefix, requestToken);
        await pipe.WriteAsync(encoded, requestToken);
        await pipe.FlushAsync(requestToken);
    }

    private static async Task ReadExactlyAsync(Stream stream, Memory<byte> destination, CancellationToken token)
    {
        int offset = 0;
        while (offset < destination.Length)
        {
            int count = await stream.ReadAsync(destination[offset..], token);
            if (count == 0) throw new EndOfStreamException("The local client disconnected.");
            offset += count;
        }
    }

    private static bool IsAdministrator(NamedPipeServerStream pipe)
    {
        bool administrator = false;
        pipe.RunAsClient(() =>
        {
            using WindowsIdentity identity = WindowsIdentity.GetCurrent(TokenAccessLevels.Query);
            administrator = new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
        });
        return administrator;
    }

    private static bool IsActiveConsoleClient(NamedPipeServerStream pipe)
    {
        if (!GetNamedPipeClientProcessId(pipe.SafePipeHandle.DangerousGetHandle(), out uint processId))
            return false;
        uint activeSession = WTSGetActiveConsoleSessionId();
        if (activeSession == uint.MaxValue) return false;
        try
        {
            using Process process = Process.GetProcessById(checked((int)processId));
            return process.SessionId == activeSession;
        }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException
            or System.ComponentModel.Win32Exception or OverflowException)
        {
            return false;
        }
    }

    private static bool IsExpectedClient(NamedPipeServerStream pipe, string executableName)
    {
        if (!GetNamedPipeClientProcessId(pipe.SafePipeHandle.DangerousGetHandle(), out uint processId))
            return false;
        try
        {
            using Process process = Process.GetProcessById(checked((int)processId));
            string? clientPath = process.MainModule?.FileName;
            if (string.IsNullOrWhiteSpace(clientPath)) return false;
            string expectedPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, executableName));
            return string.Equals(Path.GetFullPath(clientPath), expectedPath,
                StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException
            or System.ComponentModel.Win32Exception or OverflowException
            or NotSupportedException or IOException)
        {
            return false;
        }
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetNamedPipeClientProcessId(IntPtr pipe, out uint clientProcessId);

    [DllImport("kernel32.dll")]
    private static extern uint WTSGetActiveConsoleSessionId();
}
