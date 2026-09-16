namespace ParentalControl.Windows.Core;

public static class SessionStateMapper
{
    public static string FromServiceReason(string reason) => reason switch
    {
        "SessionLogon" or "ConsoleConnect" or "RemoteConnect" or "SessionUnlock" => "signed-in",
        "SessionLock" => "locked",
        "SessionLogoff" => "no-user",
        "ConsoleDisconnect" or "RemoteDisconnect" => "disconnected",
        _ => "unknown",
    };
}
