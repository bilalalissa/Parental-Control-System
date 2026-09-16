using System.IO.Pipes;
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
            response = request.Operation switch
            {
                "status" => new PipeResponse(true, null, runtime.Status()),
                "pair" when IsAdministrator(pipe) && request.Invitation is not null =>
                    runtime.Pair(request.Invitation),
                "pair" => new PipeResponse(false, "Pairing requires an elevated adult administrator session."),
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
}
