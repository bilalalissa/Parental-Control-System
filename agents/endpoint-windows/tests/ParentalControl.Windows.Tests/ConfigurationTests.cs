using System.Text.Json;
using ParentalControl.Windows.Core;

namespace ParentalControl.Windows.Tests;

[TestClass]
public sealed class ConfigurationTests
{
    [TestMethod]
    public void InvitationAcceptsCanonicalMillisecondsEncoding()
    {
        DateTimeOffset now = new(2026, 9, 14, 12, 0, 0, TimeSpan.Zero);
        string token = Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(new
        {
            code = "314159",
            expiresAt = now.AddMinutes(5).ToUnixTimeMilliseconds(),
            host = "192.168.1.20",
            port = 49171,
            certificateFingerprint = new string('a', 64),
            controllerPublicKey = Convert.ToBase64String(new byte[32]),
        }));
        PairingInvitation invitation = PairingInvitation.FromToken(token, now);
        Assert.AreEqual("314159", invitation.Code);
        Assert.AreEqual(49171, invitation.Port);
        Assert.AreEqual(new string('A', 64), invitation.CertificateFingerprint);
        HubWebSocketEndpoint endpoint = invitation.HubWebSocketEndpoint;
        Assert.AreEqual("wss", endpoint.Uri.Scheme);
        Assert.AreEqual("192.168.1.20", endpoint.Uri.Host);
        Assert.AreEqual(49171, endpoint.Uri.Port);
        Assert.AreEqual("/hub", endpoint.Uri.AbsolutePath);
        Assert.AreEqual("parental-control.v1", endpoint.SubProtocol);
    }

    [TestMethod]
    public void InvitationRejectsExpiryAndMalformedKey()
    {
        DateTimeOffset now = DateTimeOffset.UtcNow;
        string token = Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(new
        {
            code = "123456",
            expiresAt = now.AddMinutes(11).ToUnixTimeMilliseconds(),
            host = "controller.local",
            port = 49171,
            certificateFingerprint = new string('b', 64),
            controllerPublicKey = Convert.ToBase64String(new byte[31]),
        }));
        Assert.ThrowsException<InvalidDataException>(() => PairingInvitation.FromToken(token, now));
    }

    [TestMethod]
    public void ProtectedStatePersistsIdentityAndMonotonicSequence()
    {
        string root = Path.Combine(Path.GetTempPath(), "parental-control-windows-test-" + Guid.NewGuid());
        try
        {
            var store = new EndpointStateStore(Path.Combine(root, "endpoint.dat"), new TestProtector());
            EndpointState first = store.LoadOrCreate();
            EndpointState second = store.NextSequence();
            EndpointState reopened = new EndpointStateStore(
                Path.Combine(root, "endpoint.dat"), new TestProtector()).LoadOrCreate();
            Assert.AreEqual(first.DeviceId, reopened.DeviceId);
            Assert.AreEqual(1UL, second.Sequence);
            Assert.AreEqual(1UL, reopened.Sequence);
            Assert.AreEqual(32, Convert.FromBase64String(reopened.PrivateKeyBase64).Length);
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    [TestMethod]
    public void ProtectedStatePersistsBoundedStageEightRuntimeData()
    {
        string root = Path.Combine(Path.GetTempPath(), "parental-control-windows-test-" + Guid.NewGuid());
        try
        {
            var store = new EndpointStateStore(Path.Combine(root, "endpoint.dat"), new TestProtector());
            DateTimeOffset now = DateTimeOffset.UtcNow;
            store.Update(state => state with
            {
                Runtime = new EndpointRuntimeData
                {
                    ActivityCollectionEnabled = false,
                    BrowserCollectionEnabled = true,
                    BrowserRetentionDays = 14,
                    BrowserTabs =
                    [
                        new WindowsBrowserTab(
                            "edge", "Default", "Example", "https://example.test", true, now),
                    ],
                    Messages =
                    [
                        new WindowsChatMessage(
                            Guid.NewGuid(), Guid.NewGuid(), now, "Parent", "Hello", "delivered",
                            "direct", true),
                    ],
                },
            });

            EndpointRuntimeData runtime = store.LoadOrCreate().Runtime!;
            Assert.IsFalse(runtime.ActivityCollectionEnabled);
            Assert.IsTrue(runtime.BrowserCollectionEnabled);
            Assert.AreEqual(14, runtime.BrowserRetentionDays);
            Assert.AreEqual("https://example.test", runtime.BrowserTabs.Single().Origin);
            Assert.AreEqual("Hello", runtime.Messages.Single().Text);
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    [TestMethod]
    public void ProtectedStateRejectsRuntimeCollectionsBeyondTheirLimits()
    {
        string root = Path.Combine(Path.GetTempPath(), "parental-control-windows-test-" + Guid.NewGuid());
        try
        {
            var store = new EndpointStateStore(Path.Combine(root, "endpoint.dat"), new TestProtector());
            DateTimeOffset now = DateTimeOffset.UtcNow;
            Assert.ThrowsException<InvalidDataException>(() => store.Update(state => state with
            {
                Runtime = new EndpointRuntimeData
                {
                    Applications = Enumerable.Range(0, 65).Select(index =>
                        new WindowsApplicationActivity(
                            $"win32.app-{index}.exe", $"App {index}", null, null, false, now))
                        .ToArray(),
                },
            }));
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    private sealed class TestProtector : ISecretProtector
    {
        public byte[] Protect(ReadOnlySpan<byte> cleartext) => cleartext.ToArray().Reverse().ToArray();
        public byte[] Unprotect(ReadOnlySpan<byte> ciphertext) => ciphertext.ToArray().Reverse().ToArray();
    }
}
