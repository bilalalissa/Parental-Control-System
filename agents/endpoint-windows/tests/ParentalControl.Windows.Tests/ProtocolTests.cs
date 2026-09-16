using System.Text.Json.Nodes;
using ParentalControl.Windows.Core;

namespace ParentalControl.Windows.Tests;

[TestClass]
public sealed class ProtocolTests
{
    [TestMethod]
    public void SignedEnvelopeRoundTripsAndRejectsTampering()
    {
        byte[] seed = Enumerable.Range(0, 32).Select(value => (byte)value).ToArray();
        var identity = new Ed25519DeviceIdentity("device-test-device", seed);
        ProtocolEnvelope signed = identity.Sign(ProtocolEnvelope.CreateUnsigned(
            "test-device", 1, "snapshot.response",
            new JsonObject { ["changed"] = new JsonObject { ["state"] = "online" } },
            identity.KeyId,
            DateTimeOffset.UtcNow,
            TimeSpan.FromMinutes(2),
            Guid.Parse("11111111-2222-3333-4444-555555555555")));

        ProtocolEnvelope decoded = ProtocolCodec.Decode(ProtocolCodec.Encode(signed));
        Assert.IsTrue(Ed25519DeviceIdentity.Verify(decoded, identity.PublicKey));
        Assert.IsFalse(Ed25519DeviceIdentity.Verify(
            decoded with { Payload = new JsonObject { ["changed"] = new JsonObject { ["state"] = "offline" } } },
            identity.PublicKey));
    }

    [TestMethod]
    public void CanonicalSigningShapeMatchesSwiftKeys()
    {
        byte[] seed = new byte[32];
        var identity = new Ed25519DeviceIdentity("device-unit", seed);
        ProtocolEnvelope envelope = ProtocolEnvelope.CreateUnsigned(
            "unit", 7, "receipt", new JsonObject { ["z"] = 2, ["a"] = 1 },
            identity.KeyId, new DateTimeOffset(2026, 9, 14, 1, 2, 3, TimeSpan.Zero), null,
            Guid.Parse("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"));
        string json = System.Text.Encoding.UTF8.GetString(ProtocolCodec.SigningData(envelope));
        Assert.AreEqual(
            "{\"algorithm\":\"Ed25519\",\"deviceId\":\"unit\",\"id\":\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\",\"keyId\":\"device-unit\",\"payload\":{\"a\":1,\"z\":2},\"protocolVersion\":\"1.0\",\"sentAt\":\"2026-09-14T01:02:03Z\",\"sequence\":7,\"type\":\"receipt\"}",
            json);
    }

    [TestMethod]
    public void WindowsGoldenSignatureMatchesSwiftFixture()
    {
        byte[] seed = Enumerable.Range(0, 32).Select(value => (byte)value).ToArray();
        var identity = new Ed25519DeviceIdentity("device-windows-golden", seed);
        ProtocolEnvelope signed = identity.Sign(ProtocolEnvelope.CreateUnsigned(
            "windows-golden", 1, "snapshot.response",
            new JsonObject
            {
                ["changed"] = new JsonObject
                {
                    ["deviceName"] = "Windows Test",
                    ["state"] = "online",
                    ["uptimeSeconds"] = 42,
                },
                ["reason"] = "connected",
                ["snapshotVersion"] = 1,
            },
            identity.KeyId,
            new DateTimeOffset(2026, 9, 14, 12, 0, 0, TimeSpan.Zero),
            TimeSpan.FromMinutes(2),
            Guid.Parse("77777777-0000-4000-8000-000000000001")));
        Assert.AreEqual(
            "DgNlYb3nMg+KhxdQwx+6agrEj5PSkIcxVth5NDppnnrWVpRy0tEaM9I3LUKTJiuxFNXpChUqYQn7dhbDVnQnDA==",
            signed.Auth.Signature);
    }

    [TestMethod]
    public void ReplayProtectorRejectsDuplicateAndOlderSequence()
    {
        ProtocolEnvelope first = FakeEnvelope(2, Guid.NewGuid());
        var replay = new ReplayProtector(1);
        replay.Accept(first);
        Assert.ThrowsException<InvalidDataException>(() => replay.Accept(first));
        Assert.ThrowsException<InvalidDataException>(() => replay.Accept(FakeEnvelope(1, Guid.NewGuid())));
    }

    [TestMethod]
    public void ExpiredAndOversizedMessagesFailClosed()
    {
        ProtocolEnvelope envelope = FakeEnvelope(1, Guid.NewGuid()) with
        {
            ExpiresAt = DateTimeOffset.UtcNow.AddSeconds(-1),
        };
        Assert.ThrowsException<InvalidDataException>(() => ProtocolCodec.ValidateEnvelope(envelope));
        Assert.ThrowsException<InvalidDataException>(() => ProtocolCodec.Decode(
            new byte[ProductInfo.MaximumMessageBytes + 1]));
        Assert.ThrowsException<InvalidDataException>(() => ProtocolCodec.ValidateEnvelope(
            FakeEnvelope(2, Guid.NewGuid()) with
            {
                ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(-1),
                SentAt = DateTimeOffset.UtcNow,
            }));
    }

    private static ProtocolEnvelope FakeEnvelope(ulong sequence, Guid id) => new(
        id, "1.0", "device-unit", DateTimeOffset.UtcNow, null, sequence, "receipt",
        new JsonObject(), new ProtocolAuthentication("Ed25519", "controller-unit", Convert.ToBase64String(new byte[64])));
}
