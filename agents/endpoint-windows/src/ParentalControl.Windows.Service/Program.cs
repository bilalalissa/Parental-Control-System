using System.ServiceProcess;

namespace ParentalControl.Windows.Service;

internal static class Program
{
    private static void Main(string[] args)
    {
        if (!Environment.UserInteractive && !args.Contains("--console", StringComparer.Ordinal))
        {
            ServiceBase.Run(new EndpointWindowsService());
            return;
        }

        if (!args.Contains("--console", StringComparer.Ordinal))
        {
            Console.Error.WriteLine("This executable is installed as a Windows service. Use the visible Parental Control Child app.");
            Environment.ExitCode = 2;
            return;
        }

        using var runtime = new EndpointRuntime();
        runtime.Start();
        Console.WriteLine("Parental Control Windows Endpoint running in diagnostic console mode. Press Ctrl+C to stop.");
        using var stopped = new ManualResetEventSlim();
        Console.CancelKeyPress += (_, eventArgs) => { eventArgs.Cancel = true; stopped.Set(); };
        stopped.Wait();
    }
}
