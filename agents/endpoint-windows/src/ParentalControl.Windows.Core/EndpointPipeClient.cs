using System.Buffers.Binary;
using System.IO.Pipes;

namespace ParentalControl.Windows.Core;

public sealed class EndpointPipeClient
{
    public async Task<PipeResponse> SendAsync(
        PipeRequest request, CancellationToken cancellationToken = default)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(5));
        await using var pipe = new NamedPipeClientStream(
            ".", ProductInfo.PipeName, PipeDirection.InOut, PipeOptions.Asynchronous);
        await pipe.ConnectAsync(timeout.Token);
        byte[] body = PipeCodec.Encode(request);
        byte[] prefix = new byte[4];
        BinaryPrimitives.WriteInt32BigEndian(prefix, body.Length);
        await pipe.WriteAsync(prefix, timeout.Token);
        await pipe.WriteAsync(body, timeout.Token);
        await pipe.FlushAsync(timeout.Token);
        await ReadExactlyAsync(pipe, prefix, timeout.Token);
        int count = BinaryPrimitives.ReadInt32BigEndian(prefix);
        if (count is <= 0 or > ProductInfo.MaximumPipeMessageBytes)
            throw new InvalidDataException("The service response has an invalid size.");
        body = new byte[count];
        await ReadExactlyAsync(pipe, body, timeout.Token);
        return PipeCodec.Decode<PipeResponse>(body);
    }

    private static async Task ReadExactlyAsync(
        Stream stream, Memory<byte> destination, CancellationToken token)
    {
        int offset = 0;
        while (offset < destination.Length)
        {
            int count = await stream.ReadAsync(destination[offset..], token);
            if (count == 0) throw new EndOfStreamException();
            offset += count;
        }
    }
}
