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
    public void StageEightCapabilitiesClaimOnlyImplementedMetadataAndCommunication()
    {
        string[] expected = ["app-activity", "browser-tabs", "chat", "notifications",
            "request-more-time", "time-request-resolution"];
        string[] forbidden = ["app-use-restrictions", "browser-website-policy", "signed-policy",
            "lock", "shutdown"];
        foreach (string capability in expected)
            CollectionAssert.Contains(ProductInfo.Capabilities, capability);
        Assert.IsFalse(ProductInfo.Capabilities.Intersect(forbidden, StringComparer.Ordinal).Any());
    }

    [TestMethod]
    public void BrowserMetadataKeepsOnlyBoundedTitleAndOrigin()
    {
        var source = new BrowserNativeTab(
            new string('x', 400), "https://example.test/private/path?q=secret#fragment",
            true, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
        WindowsBrowserTab value = Stage08Validation.Validate("Chrome", "Default", source);

        Assert.AreEqual(300, value.Title.Length);
        Assert.AreEqual("https://example.test", value.Origin);
        Assert.AreEqual("chrome", value.Browser);
        Assert.IsTrue(value.IsActive);
    }

    [TestMethod]
    public void BrowserMetadataRejectsNonWebSchemes()
    {
        var source = new BrowserNativeTab("Local file", "file:///private/secret", false, 0);
        Assert.ThrowsException<InvalidDataException>(() =>
            Stage08Validation.Validate("edge", "Default", source));
    }

    [TestMethod]
    public void WindowsBrowserHostDoesNotClaimWebsitePolicySupport()
    {
        var response = new BrowserNativeResponse(true, true, "edge");
        Assert.IsFalse(response.WebsitePolicySupported);
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
