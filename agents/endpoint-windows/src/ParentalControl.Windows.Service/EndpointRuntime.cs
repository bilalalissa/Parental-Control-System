using System.Net.Security;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.ServiceProcess;
using System.Text.Json.Nodes;
using ParentalControl.Windows.Core;

namespace ParentalControl.Windows.Service;

internal sealed class EndpointRuntime : IDisposable
{
    private readonly object gate = new();
    private readonly CancellationTokenSource stopping = new();
    private readonly EndpointStateStore store;
    private readonly WindowsInventory inventory = new();
    private readonly BoundedFileLog log;
    private readonly SemaphoreSlim reconnect = new(0, 1);
    private Task? pipeTask;
    private Task? connectionTask;
    private ClientWebSocket? activeSocket;
    private string connectionState = "Offline";

    internal EndpointRuntime()
    {
        log = new BoundedFileLog(ServicePaths.Log);
        store = new EndpointStateStore(ServicePaths.Configuration, new DpapiSecretProtector());
    }

    internal void Start()
    {
        _ = store.LoadOrCreate();
        pipeTask = new NamedPipeEndpointServer(this, log).RunAsync(stopping.Token);
        connectionTask = RunConnectionLoopAsync(stopping.Token);
        log.Write("service.started", ProductInfo.Version);
    }

    internal void SessionChanged(SessionChangeReason reason)
    {
        inventory.SetSessionState(reason);
        SignalReconnect();
    }

    internal EndpointDashboardStatus Status()
    {
        EndpointState state = store.LoadOrCreate();
        EndpointSnapshot snapshot = inventory.Collect();
        string current;
        lock (gate) current = connectionState;
        return new EndpointDashboardStatus(
            ProductInfo.Version, true,
            state.Controller is not null && state.Controller.PendingPairingCode is null,
            state.Controller?.PendingPairingCode is not null, current,
            snapshot.DeviceName, state.DeviceId, snapshot.OperatingSystem,
            snapshot.Architecture, snapshot.SessionState, snapshot.UptimeSeconds,
            snapshot.Networks, ProductInfo.Capabilities, ProductInfo.PrivacyDisclosure);
    }

    internal PipeResponse Pair(string token)
    {
        PairingInvitation invitation = PairingInvitation.FromToken(token);
        store.Update(state => state with
        {
            Controller = new PairedController(
                invitation.Host, checked((ushort)invitation.Port),
                invitation.CertificateFingerprint,
                Convert.ToBase64String(invitation.ControllerPublicKey),
                invitation.Code, invitation.ExpiresAt),
            ControllerSequence = 0,
        });
        log.Write("pairing.installed", "Adult-authorized invitation accepted");
        SetConnection("Connecting");
        lock (gate) activeSocket?.Abort();
        SignalReconnect();
        return new PipeResponse(true, null, Status());
    }

    private void SignalReconnect()
    {
        if (reconnect.CurrentCount == 0) reconnect.Release();
    }

    private async Task RunConnectionLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            EndpointState state = store.LoadOrCreate();
            if (state.Controller is null)
            {
                SetConnection("Not paired");
                await WaitForReconnectOrDelay(TimeSpan.FromSeconds(30), cancellationToken);
                continue;
            }

            if (state.Controller.PendingPairingExpiresAt is { } expiry && expiry <= DateTimeOffset.UtcNow)
            {
                store.Update(value => value with { Controller = null, ControllerSequence = 0 });
                SetConnection("Pairing invitation expired");
                continue;
            }

            try
            {
                await ConnectOnceAsync(state, cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
            catch (Exception error)
            {
                EndpointState current = store.LoadOrCreate();
                SetConnection(current.Controller?.PendingPairingCode is null
                    ? "Offline"
                    : "Pairing failed · verify the parent app is open and the invitation is current");
                log.Write("connection.failed", error.GetType().Name);
            }

            await WaitForReconnectOrDelay(TimeSpan.FromSeconds(15), cancellationToken);
        }
    }

    private async Task ConnectOnceAsync(EndpointState initial, CancellationToken cancellationToken)
    {
        PairedController controller = initial.Controller!;
        HubWebSocketEndpoint endpoint = PairingInvitation.CreateHubWebSocketEndpoint(
            controller.Host, controller.Port);
        using var socket = new ClientWebSocket();
        socket.Options.KeepAliveInterval = TimeSpan.FromSeconds(30);
        socket.Options.AddSubProtocol(endpoint.SubProtocol);
        socket.Options.RemoteCertificateValidationCallback = (_, certificate, _, errors) =>
            ValidatePinnedCertificate(certificate, errors, controller.CertificateFingerprint);
        SetConnection("Connecting");
        await socket.ConnectAsync(endpoint.Uri, cancellationToken);
        lock (gate) activeSocket = socket;
        SetConnection("Online");
        log.Write("connection.online", "Pinned TLS WebSocket established");

        var replay = new ReplayProtector(initial.ControllerSequence);
        var delta = new SnapshotDelta();
        Guid announceId = await SendAnnouncementAsync(socket, cancellationToken);
        await SendSnapshotAsync(socket, delta, "connected", cancellationToken);

        TimeSpan activeHeartbeat = TimeSpan.FromSeconds(15);
        TimeSpan idleHeartbeat = TimeSpan.FromSeconds(60);
        TimeSpan heartbeat = activeHeartbeat;
        int heartbeatCount = 0;
        try
        {
            while (socket.State == WebSocketState.Open && !cancellationToken.IsCancellationRequested)
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                timeout.CancelAfter(heartbeat);
                byte[]? message;
                try
                {
                    message = await ReceiveMessageAsync(socket, timeout.Token);
                }
                catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
                {
                    await SendSnapshotAsync(socket, delta, "adaptive-heartbeat", cancellationToken);
                    heartbeatCount++;
                    heartbeat = heartbeatCount < 3 ? activeHeartbeat : idleHeartbeat;
                    continue;
                }
                if (message is null) break;

                ProtocolEnvelope envelope = ProtocolCodec.Decode(message);
                byte[] controllerKey = Convert.FromBase64String(controller.ControllerPublicKeyBase64);
                if (!Ed25519DeviceIdentity.Verify(envelope, controllerKey))
                    throw new InvalidDataException("Controller signature validation failed.");
                replay.Accept(envelope);
                store.Update(value => value with { ControllerSequence = replay.HighestSequence });

                if (envelope.Type == "receipt")
                {
                    if (envelope.Payload["heartbeatActiveSeconds"]?.GetValue<long>() is { } active)
                        activeHeartbeat = TimeSpan.FromSeconds(Math.Clamp(active, 15, 300));
                    if (envelope.Payload["heartbeatIdleSeconds"]?.GetValue<long>() is { } idle)
                        idleHeartbeat = TimeSpan.FromSeconds(Math.Clamp(idle, (long)activeHeartbeat.TotalSeconds, 900));
                    heartbeat = heartbeatCount < 3 ? activeHeartbeat : idleHeartbeat;
                    string? original = envelope.Payload["originalMessageId"]?.GetValue<string>();
                    string? receiptState = envelope.Payload["state"]?.GetValue<string>();
                    if (Guid.TryParse(original, out Guid receiptId) && receiptId == announceId
                        && receiptState == "accepted" && controller.PendingPairingCode is not null)
                    {
                        store.Update(value => value with
                        {
                            Controller = value.Controller! with
                            {
                                PendingPairingCode = null,
                                PendingPairingExpiresAt = null,
                            },
                        });
                        controller = controller with { PendingPairingCode = null, PendingPairingExpiresAt = null };
                        log.Write("pairing.completed", "Controller receipt verified");
                    }
                }
                else if (envelope.Type == "snapshot.request")
                {
                    await SendSnapshotAsync(socket, delta, "controller-request", cancellationToken);
                    heartbeatCount = 0;
                    heartbeat = activeHeartbeat;
                }
            }
        }
        finally
        {
            lock (gate) { if (ReferenceEquals(activeSocket, socket)) activeSocket = null; }
            SetConnection("Offline");
        }
    }

    private async Task<Guid> SendAnnouncementAsync(ClientWebSocket socket, CancellationToken token)
    {
        EndpointState state = store.NextSequence();
        var identity = Identity(state);
        var payload = new JsonObject
        {
            ["name"] = inventory.Collect().DeviceName,
            ["platform"] = "Windows",
            ["publicKey"] = Convert.ToBase64String(identity.PublicKey),
            ["capabilities"] = new JsonArray(ProductInfo.Capabilities.Select(value => JsonValue.Create(value)).ToArray()),
        };
        if (state.Controller?.PendingPairingCode is { } code) payload["pairingCode"] = code;
        ProtocolEnvelope envelope = identity.Sign(ProtocolEnvelope.CreateUnsigned(
            state.DeviceId, state.Sequence, "capability.announce", payload, identity.KeyId,
            lifetime: TimeSpan.FromMinutes(2)));
        await SendAsync(socket, envelope, token);
        return envelope.Id;
    }

    private async Task SendSnapshotAsync(
        ClientWebSocket socket, SnapshotDelta delta, string reason, CancellationToken token)
    {
        EndpointState sequence = store.NextSequence();
        EndpointState version = store.NextSnapshotVersion();
        var identity = Identity(version);
        JsonObject changed = delta.Changed(inventory.Collect().ToJson());
        var payload = new JsonObject
        {
            ["snapshotVersion"] = version.SnapshotVersion,
            ["changed"] = changed,
            ["reason"] = reason,
        };
        ProtocolEnvelope envelope = identity.Sign(ProtocolEnvelope.CreateUnsigned(
            version.DeviceId, sequence.Sequence, "snapshot.response", payload, identity.KeyId,
            lifetime: TimeSpan.FromMinutes(2)));
        await SendAsync(socket, envelope, token);
    }

    private static Ed25519DeviceIdentity Identity(EndpointState state)
    {
        byte[] seed = Convert.FromBase64String(state.PrivateKeyBase64);
        try { return new Ed25519DeviceIdentity($"device-{state.DeviceId}", seed); }
        finally { CryptographicOperations.ZeroMemory(seed); }
    }

    private static async Task SendAsync(
        ClientWebSocket socket, ProtocolEnvelope envelope, CancellationToken token)
    {
        byte[] data = ProtocolCodec.Encode(envelope);
        await socket.SendAsync(data, WebSocketMessageType.Text, true, token);
    }

    private static async Task<byte[]?> ReceiveMessageAsync(ClientWebSocket socket, CancellationToken token)
    {
        using var stream = new MemoryStream();
        byte[] buffer = new byte[8192];
        while (true)
        {
            ValueWebSocketReceiveResult result = await socket.ReceiveAsync(buffer.AsMemory(), token);
            if (result.MessageType == WebSocketMessageType.Close) return null;
            if (result.MessageType is not WebSocketMessageType.Text and not WebSocketMessageType.Binary)
                throw new InvalidDataException("Only protocol data messages are accepted.");
            if (stream.Length + result.Count > ProductInfo.MaximumMessageBytes)
                throw new InvalidDataException("Controller message exceeds 64 KiB.");
            stream.Write(buffer, 0, result.Count);
            if (result.EndOfMessage) return stream.ToArray();
        }
    }

    private static bool ValidatePinnedCertificate(
        X509Certificate? certificate, SslPolicyErrors errors, string expectedFingerprint)
    {
        if (certificate is null || errors.HasFlag(SslPolicyErrors.RemoteCertificateNotAvailable)) return false;
        string actual = Convert.ToHexString(SHA256.HashData(certificate.GetRawCertData()));
        return CryptographicOperations.FixedTimeEquals(
            Convert.FromHexString(actual),
            Convert.FromHexString(PairingInvitation.NormalizeFingerprint(expectedFingerprint)));
    }

    private async Task WaitForReconnectOrDelay(TimeSpan delay, CancellationToken token)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
        timeout.CancelAfter(delay);
        try { await reconnect.WaitAsync(timeout.Token); }
        catch (OperationCanceledException) when (!token.IsCancellationRequested) { }
    }

    private void SetConnection(string value)
    {
        lock (gate) connectionState = value;
    }

    public void Dispose()
    {
        stopping.Cancel();
        Task[] tasks = new[] { pipeTask, connectionTask }.OfType<Task>().ToArray();
        try { Task.WaitAll(tasks, TimeSpan.FromSeconds(5)); }
        catch (AggregateException) { }
        stopping.Dispose();
        reconnect.Dispose();
        log.Write("service.stopped");
    }
}
