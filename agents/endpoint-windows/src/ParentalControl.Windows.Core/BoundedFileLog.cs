using System.Text;

namespace ParentalControl.Windows.Core;

public sealed class BoundedFileLog
{
    private readonly object gate = new();
    private readonly string path;

    public BoundedFileLog(string path) => this.path = path;

    public void Write(string eventName, string? detail = null)
    {
        string safeEvent = Redact(eventName, 64);
        string safeDetail = Redact(detail ?? string.Empty, 160);
        string line = $"{DateTimeOffset.UtcNow:O}\t{safeEvent}\t{safeDetail}{Environment.NewLine}";
        lock (gate)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            RotateIfNeeded(Encoding.UTF8.GetByteCount(line));
            File.AppendAllText(path, line, Encoding.UTF8);
        }
    }

    private void RotateIfNeeded(int incomingBytes)
    {
        if (!File.Exists(path) || new FileInfo(path).Length + incomingBytes <= ProductInfo.MaximumLogBytes) return;
        string oldPath = path + ".1";
        if (File.Exists(oldPath)) File.Delete(oldPath);
        File.Move(path, oldPath);
    }

    private static string Redact(string value, int maximumCharacters)
    {
        string safe = value.Replace('\r', ' ').Replace('\n', ' ').Replace('\t', ' ');
        if (Uri.TryCreate(safe, UriKind.Absolute, out _)) return "[redacted-url]";
        return safe.Length <= maximumCharacters ? safe : safe[..maximumCharacters];
    }
}
