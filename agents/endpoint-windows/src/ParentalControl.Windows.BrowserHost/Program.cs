using System.Buffers.Binary;
using System.Text.Json;
using ParentalControl.Windows.Core;
using ParentalControl.Windows.BrowserHost;

const int maximumNativeMessageBytes = 64 * 1024;
var options = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

try
{
    if (!BrowserCallerPolicy.IsApprovedParent())
        throw new UnauthorizedAccessException("The native host must be started by an installed Chrome or Edge browser.");
    Stream input = Console.OpenStandardInput();
    Stream output = Console.OpenStandardOutput();
    byte[] prefix = new byte[4];
    await ReadExactlyAsync(input, prefix);
    int length = BinaryPrimitives.ReadInt32LittleEndian(prefix);
    if (length is <= 0 or > maximumNativeMessageBytes)
        throw new InvalidDataException("Native browser message has an invalid size.");
    byte[] body = new byte[length];
    await ReadExactlyAsync(input, body);
    BrowserNativeRequest request = JsonSerializer.Deserialize<BrowserNativeRequest>(body, options)
        ?? throw new InvalidDataException("Native browser message is empty.");
    PipeResponse response = await new EndpointPipeClient().SendAsync(
        new PipeRequest("browser.native", Browser: request));
    BrowserNativeResponse browser = response.Browser
        ?? new BrowserNativeResponse(false, false, request.Browser, response.Error);
    body = JsonSerializer.SerializeToUtf8Bytes(browser, options);
    BinaryPrimitives.WriteInt32LittleEndian(prefix, body.Length);
    await output.WriteAsync(prefix);
    await output.WriteAsync(body);
    await output.FlushAsync();
}
catch (Exception error)
{
    try
    {
        byte[] body = JsonSerializer.SerializeToUtf8Bytes(
            new BrowserNativeResponse(false, false, "unknown", error.GetType().Name), options);
        byte[] prefix = new byte[4];
        BinaryPrimitives.WriteInt32LittleEndian(prefix, body.Length);
        Stream output = Console.OpenStandardOutput();
        await output.WriteAsync(prefix);
        await output.WriteAsync(body);
        await output.FlushAsync();
    }
    catch { }
    Environment.ExitCode = 1;
}

static async Task ReadExactlyAsync(Stream stream, Memory<byte> destination)
{
    int offset = 0;
    while (offset < destination.Length)
    {
        int count = await stream.ReadAsync(destination[offset..]);
        if (count == 0) throw new EndOfStreamException();
        offset += count;
    }
}
