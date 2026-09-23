using System.Threading;
using System.Windows;

namespace ParentalControl.Windows.App;

public partial class App : System.Windows.Application
{
    private const string InstanceMutexName = @"Local\ParentalControl.Windows.App.v1";
    private Mutex? instanceMutex;
    private bool ownsInstanceMutex;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        bool waitForPrevious = e.Args.Contains(
            "--wait-for-previous-instance", StringComparer.Ordinal);
        instanceMutex = new Mutex(initiallyOwned: false, InstanceMutexName);
        try
        {
            ownsInstanceMutex = instanceMutex.WaitOne(
                waitForPrevious ? TimeSpan.FromSeconds(15) : TimeSpan.Zero);
        }
        catch (AbandonedMutexException)
        {
            ownsInstanceMutex = true;
        }

        if (!ownsInstanceMutex)
        {
            Shutdown();
            return;
        }

        MainWindow = new MainWindow(waitForPrevious);
        MainWindow.Show();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        if (ownsInstanceMutex)
        {
            try { instanceMutex?.ReleaseMutex(); }
            catch (ApplicationException) { }
        }
        instanceMutex?.Dispose();
        base.OnExit(e);
    }
}
