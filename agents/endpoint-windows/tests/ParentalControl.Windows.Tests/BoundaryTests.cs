using System.Net;
using ParentalControl.Windows.Core;

namespace ParentalControl.Windows.Tests;

[TestClass]
public sealed class BoundaryTests
{
    [DataTestMethod]
    [DataRow("10.0.0.1", true)]
    [DataRow("172.31.255.1", true)]
    [DataRow("192.168.50.4", true)]
    [DataRow("169.254.10.4", true)]
    [DataRow("8.8.8.8", false)]
    [DataRow("2001:4860:4860::8888", false)]
    [DataRow("fe80::1", true)]
    [DataRow("fd00::1", true)]
    public void OnlyPrivateOrLinkLocalAddressesAreShared(string text, bool expected)
    {
        Assert.AreEqual(expected, NetworkMetadata.IsPrivateOrLinkLocal(IPAddress.Parse(text)));
    }

    [TestMethod]
    public void PipeMessagesAreBounded()
    {
        byte[] valid = PipeCodec.Encode(new PipeRequest("status"));
        Assert.AreEqual("status", PipeCodec.Decode<PipeRequest>(valid).Operation);
        Assert.ThrowsException<InvalidDataException>(() => PipeCodec.Decode<PipeRequest>(
            new byte[ProductInfo.MaximumPipeMessageBytes + 1]));
    }

    [TestMethod]
    public void StageSevenCapabilitiesDoNotClaimMonitoringOrEnforcement()
    {
        string[] forbidden = ["app-activity", "browser-tabs", "chat", "signed-policy", "lock", "shutdown"];
        CollectionAssert.DoesNotContain(ProductInfo.Capabilities, forbidden[0]);
        Assert.IsFalse(ProductInfo.Capabilities.Intersect(forbidden, StringComparer.Ordinal).Any());
    }

    [DataTestMethod]
    [DataRow("SessionLogon", "signed-in")]
    [DataRow("SessionUnlock", "signed-in")]
    [DataRow("SessionLock", "locked")]
    [DataRow("SessionLogoff", "no-user")]
    [DataRow("RemoteDisconnect", "disconnected")]
    [DataRow("Other", "unknown")]
    public void ServiceSessionTransitionsRemainCoarse(string reason, string expected)
    {
        Assert.AreEqual(expected, SessionStateMapper.FromServiceReason(reason));
    }
}
