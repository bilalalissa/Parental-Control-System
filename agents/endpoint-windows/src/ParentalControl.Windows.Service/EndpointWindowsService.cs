using System.ServiceProcess;

namespace ParentalControl.Windows.Service;

internal sealed class EndpointWindowsService : ServiceBase
{
    private EndpointRuntime? runtime;

    internal EndpointWindowsService()
    {
        ServiceName = "ParentalControlWindowsEndpoint";
        CanStop = true;
        CanShutdown = true;
        CanHandleSessionChangeEvent = true;
        AutoLog = false;
    }

    protected override void OnStart(string[] args)
    {
        runtime = new EndpointRuntime();
        runtime.Start();
    }

    protected override void OnSessionChange(SessionChangeDescription changeDescription)
    {
        runtime?.SessionChanged(changeDescription.Reason);
    }

    protected override void OnStop()
    {
        runtime?.Dispose();
        runtime = null;
    }

    protected override void OnShutdown() => OnStop();
}
