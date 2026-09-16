namespace ParentalControl.Windows.Service;

internal static class ServicePaths
{
    internal static readonly string Root = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
        "Parental Control", "Windows Endpoint");
    internal static readonly string Configuration = Path.Combine(Root, "endpoint.dat");
    internal static readonly string Log = Path.Combine(Root, "endpoint.log");
}
