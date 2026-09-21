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
    private readonly SemaphoreSlim outboundSignal = new(0, 1);
    private Task? pipeTask;
    private Task? connectionTask;
    private ClientWebSocket? activeSocket;
    private string connectionState = "Offline";
    private string? lastActivityDigest;
    private string? lastBrowserDigest;

    internal EndpointRuntime()
    {
        log = new BoundedFileLog(ServicePaths.Log);
        store = new EndpointStateStore(ServicePaths.Configuration, new DpapiSecretProtector());
    }

    internal void Start()
    {
        EndpointStateLoadResult initialState = store.LoadOrCreateRecoveringUnreadable();
        if (initialState.RecoveredUnreadableState)
        {
            log.Write(
                "configuration.recovered",
                "Unreadable protected state preserved; fresh pairing is required");
        }
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
        EndpointRuntimeData runtime = Normalized(state.Runtime);
        EndpointSnapshot snapshot = inventory.Collect();
        string current;
        lock (gate) current = connectionState;
        return new EndpointDashboardStatus(
            ProductInfo.Version, true,
            state.Controller is not null && state.Controller.PendingPairingCode is null,
            state.Controller?.PendingPairingCode is not null, current,
            snapshot.DeviceName, state.DeviceId, snapshot.OperatingSystem,
            snapshot.Architecture, snapshot.SessionState, snapshot.UptimeSeconds,
            snapshot.Networks, ProductInfo.Capabilities, ProductInfo.PrivacyDisclosure,
            runtime.ActivityCollectionEnabled, runtime.ActivityRetentionDays,
            runtime.BrowserCollectionEnabled, runtime.BrowserRetentionDays,
            runtime.Applications.Take(32).ToArray(), runtime.BrowserTabs.Take(32).ToArray(),
            runtime.Messages.TakeLast(25).ToArray(), runtime.LatestTimeRequest);
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

    internal PipeResponse UpdateApplications(IReadOnlyList<WindowsApplicationActivity>? values)
    {
        if (values is null || values.Count > 64)
            return new PipeResponse(false, "Application update exceeds its bound.");
        WindowsApplicationActivity[] applications;
        try
        {
            applications = values.Select(Stage08Validation.Validate)
                .GroupBy(item => item.BundleIdentifier, StringComparer.OrdinalIgnoreCase)
                .Select(group => group.OrderByDescending(item => item.IsForeground)
                    .ThenByDescending(item => item.ObservedAt).First())
                .OrderByDescending(item => item.IsForeground)
                .ThenByDescending(item => item.ObservedAt)
                .Take(64).ToArray();
        }
        catch (InvalidDataException error)
        {
            return new PipeResponse(false, error.Message);
        }

        bool enabled = false;
        UpdateRuntime(runtime =>
        {
            enabled = runtime.ActivityCollectionEnabled;
            return enabled ? runtime with { Applications = applications } : runtime with { Applications = [] };
        });
        if (enabled) SignalOutbound();
        return new PipeResponse(true, null, Status());
    }

    internal PipeResponse HandleBrowser(BrowserNativeRequest? request)
    {
        if (request is null)
            return new PipeResponse(false, "Browser request is missing.");
        string browser = Stage08Validation.Bound(request.Browser.Trim().ToLowerInvariant(), 40);
        string profile = Stage08Validation.Bound(request.Profile.Trim(), 80);
        if (browser.Length == 0 || profile.Length == 0)
            return new PipeResponse(false, "Browser identity is invalid.");

        EndpointRuntimeData current = Normalized(store.LoadOrCreate().Runtime);
        if (request.Type == "configuration.query")
        {
            return new PipeResponse(true, null, null,
                new BrowserNativeResponse(true, current.BrowserCollectionEnabled, browser));
        }
        if (request.Type == "policy.ack")
        {
            return new PipeResponse(true, null, null,
                new BrowserNativeResponse(true, current.BrowserCollectionEnabled, browser));
        }
        if (request.Type != "tabs.update" || request.Tabs is null || request.Tabs.Count > 128)
            return new PipeResponse(false, "Browser update is unsupported or exceeds its bound.");

        try
        {
            WindowsBrowserTab[] tabs = request.Tabs
                .Select(item => Stage08Validation.Validate(browser, profile, item))
                .Take(128).ToArray();
            bool enabled = false;
            UpdateRuntime(runtime =>
            {
                enabled = runtime.BrowserCollectionEnabled;
                var retained = runtime.BrowserTabs.Where(item =>
                    !string.Equals(item.Browser, browser, StringComparison.OrdinalIgnoreCase)
                    || !string.Equals(item.Profile, profile, StringComparison.Ordinal)).ToList();
                if (enabled) retained.AddRange(tabs);
                return runtime with { BrowserTabs = retained.TakeLast(128).ToArray() };
            });
            if (enabled) SignalOutbound();
            return new PipeResponse(true, null, null,
                new BrowserNativeResponse(true, enabled, browser));
        }
        catch (Exception error) when (error is InvalidDataException or ArgumentOutOfRangeException)
        {
            return new PipeResponse(false, error.Message, null,
                new BrowserNativeResponse(false, false, browser, error.Message));
        }
    }

    internal PipeResponse QueueChat(string? text, string? audience, Guid? threadId)
    {
        string trimmed = Stage08Validation.Bound((text ?? "").Trim(), 2_000);
        string targetAudience = audience ?? "direct";
        EndpointState state = store.LoadOrCreate();
        if (state.Controller is null) return new PipeResponse(false, "Pair with a parent before chatting.");
        if (trimmed.Length == 0 || !Stage08Validation.ChatAudiences.Contains(targetAudience))
            return new PipeResponse(false, "Chat message is invalid.");
        Guid id = Guid.NewGuid();
        Guid thread = threadId ?? Guid.NewGuid();
        DateTimeOffset now = DateTimeOffset.UtcNow;
        var payload = new JsonObject
        {
            ["text"] = trimmed,
            ["sender"] = "Child",
            ["audience"] = targetAudience,
            ["threadId"] = thread.ToString(),
        };
        UpdateRuntime(runtime => runtime with
        {
            Messages = runtime.Messages.Append(new WindowsChatMessage(
                id, thread, now, "Child", trimmed, "queued", targetAudience, false))
                .TakeLast(200).ToArray(),
            Outbound = AppendOutbound(runtime.Outbound,
                new PendingOutboundMessage(id, "chat.message", payload.ToJsonString(), now)),
        });
        SignalOutbound();
        log.Write("chat.queued", "Outbound chat metadata queued; content omitted");
        return new PipeResponse(true, null, Status());
    }

    internal PipeResponse MarkChatRead()
    {
        UpdateRuntime(runtime =>
        {
            var outbound = runtime.Outbound.ToList();
            var messages = runtime.Messages.Select(message =>
            {
                if (!message.IsFromParent || message.State == "read") return message;
                var payload = new JsonObject
                {
                    ["originalMessageId"] = message.Id.ToString(),
                    ["state"] = "read",
                };
                outbound = AppendOutbound(outbound,
                    new PendingOutboundMessage(Guid.NewGuid(), "receipt", payload.ToJsonString(),
                        DateTimeOffset.UtcNow)).ToList();
                return message with { State = "read" };
            }).ToArray();
            return runtime with { Messages = messages, Outbound = outbound.TakeLast(100).ToArray() };
        });
        SignalOutbound();
        return new PipeResponse(true, null, Status());
    }

    internal PipeResponse RequestMoreTime(int? minutes, string? note)
    {
        EndpointState state = store.LoadOrCreate();
        if (state.Controller is null) return new PipeResponse(false, "Pair with a parent before requesting time.");
        int boundedMinutes = Math.Clamp(minutes ?? 15, 5, 240);
        string boundedNote = Stage08Validation.Bound(note ?? "", 500);
        Guid id = Guid.NewGuid();
        DateTimeOffset now = DateTimeOffset.UtcNow;
        var request = new WindowsTimeRequest(id, boundedMinutes, boundedNote, now);
        var payload = new JsonObject { ["minutes"] = boundedMinutes, ["note"] = boundedNote };
        UpdateRuntime(runtime => runtime with
        {
            LatestTimeRequest = request,
            Outbound = AppendOutbound(runtime.Outbound,
                new PendingOutboundMessage(id, "time.request", payload.ToJsonString(), now)),
        });
        SignalOutbound();
        log.Write("time.requested", "Bounded time request queued; note content omitted");
        return new PipeResponse(true, null, Status());
    }

    private void SignalReconnect()
    {
        if (reconnect.CurrentCount == 0) reconnect.Release();
    }

    private void SignalOutbound()
    {
        if (outboundSignal.CurrentCount == 0) outboundSignal.Release();
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
        lastActivityDigest = null;
        lastBrowserDigest = null;
        log.Write("connection.online", "Pinned TLS WebSocket established");

        var replay = new ReplayProtector(initial.ControllerSequence);
        var delta = new SnapshotDelta();
        Guid announceId = await SendAnnouncementAsync(socket, cancellationToken);
        await SendSnapshotAsync(socket, delta, "connected", cancellationToken);
        await FlushOutboundAsync(socket, cancellationToken);
        await SendActivityIfChangedAsync(socket, cancellationToken);
        await SendBrowserIfChangedAsync(socket, cancellationToken);

        TimeSpan activeHeartbeat = TimeSpan.FromSeconds(15);
        TimeSpan idleHeartbeat = TimeSpan.FromSeconds(60);
        TimeSpan heartbeat = activeHeartbeat;
        int heartbeatCount = 0;
        Task<byte[]?> receiveTask = ReceiveMessageAsync(socket, cancellationToken);
        Task outboundTask = outboundSignal.WaitAsync(cancellationToken);
        Task heartbeatTask = Task.Delay(heartbeat, cancellationToken);
        try
        {
            while (socket.State == WebSocketState.Open && !cancellationToken.IsCancellationRequested)
            {
                Task completed = await Task.WhenAny(receiveTask, outboundTask, heartbeatTask);
                if (completed == receiveTask)
                {
                    byte[]? message = await receiveTask;
                    if (message is null) break;
                    ProtocolEnvelope envelope = ProtocolCodec.Decode(message);
                    byte[] controllerKey = Convert.FromBase64String(controller.ControllerPublicKeyBase64);
                    if (!Ed25519DeviceIdentity.Verify(envelope, controllerKey))
                        throw new InvalidDataException("Controller signature validation failed.");
                    replay.Accept(envelope);
                    store.Update(value => value with { ControllerSequence = replay.HighestSequence });
                    controller = await HandleControllerEnvelopeAsync(
                        socket, envelope, announceId, controller, cancellationToken,
                        active => activeHeartbeat = active, idle => idleHeartbeat = idle);
                    heartbeatCount = 0;
                    heartbeat = activeHeartbeat;
                    heartbeatTask = Task.Delay(heartbeat, cancellationToken);
                    receiveTask = ReceiveMessageAsync(socket, cancellationToken);
                    await FlushOutboundAsync(socket, cancellationToken);
                }
                if (completed == outboundTask)
                {
                    await FlushOutboundAsync(socket, cancellationToken);
                    await SendActivityIfChangedAsync(socket, cancellationToken);
                    await SendBrowserIfChangedAsync(socket, cancellationToken);
                    outboundTask = outboundSignal.WaitAsync(cancellationToken);
                }
                if (completed == heartbeatTask)
                {
                    await SendSnapshotAsync(socket, delta, "adaptive-heartbeat", cancellationToken);
                    await FlushOutboundAsync(socket, cancellationToken);
                    await SendActivityIfChangedAsync(socket, cancellationToken);
                    await SendBrowserIfChangedAsync(socket, cancellationToken);
                    heartbeatCount++;
                    heartbeat = heartbeatCount < 3 ? activeHeartbeat : idleHeartbeat;
                    heartbeatTask = Task.Delay(heartbeat, cancellationToken);
                }
            }
        }
        finally
        {
            lock (gate) { if (ReferenceEquals(activeSocket, socket)) activeSocket = null; }
            SetConnection("Offline");
        }
    }

    private async Task<PairedController> HandleControllerEnvelopeAsync(
        ClientWebSocket socket,
        ProtocolEnvelope envelope,
        Guid announceId,
        PairedController controller,
        CancellationToken token,
        Action<TimeSpan> setActive,
        Action<TimeSpan> setIdle)
    {
        EndpointState current = store.LoadOrCreate();
        if (envelope.Type == "receipt")
        {
            if (envelope.Payload["heartbeatActiveSeconds"]?.GetValue<long>() is { } active)
                setActive(TimeSpan.FromSeconds(Math.Clamp(active, 15, 300)));
            if (envelope.Payload["heartbeatIdleSeconds"]?.GetValue<long>() is { } idle)
                setIdle(TimeSpan.FromSeconds(Math.Clamp(idle, 15, 900)));
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
            if (Guid.TryParse(original, out Guid messageId)
                && receiptState is not null && Stage08Validation.ChatStates.Contains(receiptState))
            {
                UpdateRuntime(runtime => runtime with
                {
                    Messages = runtime.Messages.Select(item => item.Id == messageId
                        ? item with { State = AdvanceChatState(item.State, receiptState) } : item).ToArray(),
                });
            }
            return controller;
        }
        if (envelope.Type == "snapshot.request")
        {
            await SendSnapshotAsync(socket, new SnapshotDelta(), "controller-request", token);
            return controller;
        }

        string target = envelope.Payload["targetDeviceId"]?.GetValue<string>() ?? string.Empty;
        if (target != current.DeviceId) throw new InvalidDataException("Controller message target is invalid.");
        switch (envelope.Type)
        {
            case "activity.configuration":
                if (envelope.Payload["restrictionPolicy"] is not null)
                {
                    QueueReceipt(envelope.Id, "unsupported");
                    break;
                }
                bool activityEnabled = envelope.Payload["enabled"]?.GetValue<bool>()
                    ?? throw new InvalidDataException("Activity configuration is incomplete.");
                int activityRetention = Math.Clamp(
                    envelope.Payload["retentionDays"]?.GetValue<int>() ?? 7, 1, 30);
                UpdateRuntime(runtime => runtime with
                {
                    ActivityCollectionEnabled = activityEnabled,
                    ActivityRetentionDays = activityRetention,
                    Applications = activityEnabled ? runtime.Applications : [],
                });
                QueueReceipt(envelope.Id, "delivered");
                log.Write("activity.configuration", activityEnabled ? "Collection enabled" : "Collection disabled");
                break;
            case "browser.configuration":
                if (envelope.Payload["websitePolicy"] is not null)
                {
                    QueueReceipt(envelope.Id, "unsupported");
                    break;
                }
                bool browserEnabled = envelope.Payload["enabled"]?.GetValue<bool>()
                    ?? throw new InvalidDataException("Browser configuration is incomplete.");
                int browserRetention = Math.Clamp(
                    envelope.Payload["retentionDays"]?.GetValue<int>() ?? 7, 1, 30);
                UpdateRuntime(runtime => runtime with
                {
                    BrowserCollectionEnabled = browserEnabled,
                    BrowserRetentionDays = browserRetention,
                    BrowserTabs = browserEnabled ? runtime.BrowserTabs : [],
                });
                QueueReceipt(envelope.Id, "delivered");
                log.Write("browser.configuration", browserEnabled ? "Collection enabled" : "Collection disabled");
                break;
            case "chat.message":
                ReceiveChat(envelope);
                QueueReceipt(envelope.Id, "delivered");
                break;
            case "chat.mutation":
                ReceiveChatMutation(envelope);
                QueueReceipt(envelope.Id, "delivered");
                break;
            case "time.request-resolution":
                ResolveTimeRequest(envelope);
                QueueReceipt(envelope.Id, "delivered");
                break;
            default:
                QueueReceipt(envelope.Id, "unsupported");
                break;
        }
        SignalOutbound();
        return controller;
    }

    private void ReceiveChat(ProtocolEnvelope envelope)
    {
        string text = Stage08Validation.Bound(
            envelope.Payload["text"]?.GetValue<string>()?.Trim() ?? string.Empty, 2_000);
        string audience = envelope.Payload["audience"]?.GetValue<string>() ?? string.Empty;
        Guid thread = Guid.TryParse(envelope.Payload["threadId"]?.GetValue<string>(), out Guid value)
            ? value : Guid.NewGuid();
        if (text.Length == 0 || !Stage08Validation.ChatAudiences.Contains(audience))
            throw new InvalidDataException("Chat message is invalid.");
        UpdateRuntime(runtime => runtime.Messages.Any(item => item.Id == envelope.Id) ? runtime : runtime with
        {
            Messages = runtime.Messages.Append(new WindowsChatMessage(
                envelope.Id, thread, envelope.SentAt, "Parent", text, "delivered", audience, true))
                .TakeLast(200).ToArray(),
        });
        log.Write("chat.received", "Inbound chat metadata received; content omitted");
    }

    private void ReceiveChatMutation(ProtocolEnvelope envelope)
    {
        if (!Guid.TryParse(envelope.Payload["originalMessageId"]?.GetValue<string>(), out Guid original)
            || !DateTimeOffset.TryParse(envelope.Payload["mutatedAt"]?.GetValue<string>(), out DateTimeOffset mutated))
            throw new InvalidDataException("Chat mutation is invalid.");
        string action = envelope.Payload["action"]?.GetValue<string>() ?? string.Empty;
        UpdateRuntime(runtime => runtime with
        {
            Messages = runtime.Messages.Select(item =>
            {
                if (item.Id != original || !item.IsFromParent || item.DeletedAt is not null) return item;
                return action switch
                {
                    "edit" when !string.IsNullOrWhiteSpace(envelope.Payload["text"]?.GetValue<string>()) =>
                        item with
                        {
                            Text = Stage08Validation.Bound(
                                envelope.Payload["text"]!.GetValue<string>().Trim(), 2_000),
                            EditedAt = mutated,
                        },
                    "delete" => item with { Text = string.Empty, DeletedAt = mutated },
                    _ => throw new InvalidDataException("Chat mutation action is invalid."),
                };
            }).ToArray(),
        });
    }

    private void ResolveTimeRequest(ProtocolEnvelope envelope)
    {
        if (!Guid.TryParse(envelope.Payload["requestId"]?.GetValue<string>(), out Guid requestId))
            throw new InvalidDataException("Time request resolution is invalid.");
        string decision = envelope.Payload["decision"]?.GetValue<string>() ?? string.Empty;
        if (decision is not "approved" and not "rejected")
            throw new InvalidDataException("Time request decision is invalid.");
        int minutes = Math.Clamp(envelope.Payload["minutes"]?.GetValue<int>() ?? 15, 5, 240);
        UpdateRuntime(runtime => runtime with
        {
            LatestTimeRequest = runtime.LatestTimeRequest?.Id == requestId
                ? runtime.LatestTimeRequest with { State = decision, ResolvedAt = DateTimeOffset.UtcNow }
                : new WindowsTimeRequest(
                    requestId, minutes, string.Empty, DateTimeOffset.UtcNow, decision, DateTimeOffset.UtcNow),
        });
    }

    private void QueueReceipt(Guid originalId, string state)
    {
        var payload = new JsonObject
        {
            ["originalMessageId"] = originalId.ToString(),
            ["state"] = state,
        };
        UpdateRuntime(runtime => runtime with
        {
            Outbound = AppendOutbound(runtime.Outbound,
                new PendingOutboundMessage(Guid.NewGuid(), "receipt", payload.ToJsonString(),
                    DateTimeOffset.UtcNow)),
        });
    }

    private async Task FlushOutboundAsync(ClientWebSocket socket, CancellationToken token)
    {
        PendingOutboundMessage[] items = Normalized(store.LoadOrCreate().Runtime).Outbound.ToArray();
        foreach (PendingOutboundMessage item in items)
        {
            EndpointState state = store.NextSequence();
            Ed25519DeviceIdentity identity = Identity(state);
            ProtocolEnvelope envelope = identity.Sign(ProtocolEnvelope.CreateUnsigned(
                state.DeviceId, state.Sequence, item.Type, Stage08Validation.ParsePayload(item),
                identity.KeyId, lifetime: TimeSpan.FromMinutes(2), id: item.Id));
            await SendAsync(socket, envelope, token);
            UpdateRuntime(runtime => runtime with
            {
                Outbound = runtime.Outbound.Where(value => value.Id != item.Id).ToArray(),
                Messages = item.Type == "chat.message"
                    ? runtime.Messages.Select(message => message.Id == item.Id
                        ? message with { State = AdvanceChatState(message.State, "sent") } : message).ToArray()
                    : runtime.Messages,
            });
        }
    }

    private async Task SendActivityIfChangedAsync(ClientWebSocket socket, CancellationToken token)
    {
        EndpointRuntimeData runtime = Normalized(store.LoadOrCreate().Runtime);
        WindowsApplicationActivity[] applications = runtime.ActivityCollectionEnabled
            ? runtime.Applications.Take(64).ToArray() : [];
        string digest = string.Join('|', applications.Select(value =>
            $"{value.BundleIdentifier}:{value.IsForeground}:{value.ObservedAt.ToUnixTimeSeconds()}"));
        if (digest == lastActivityDigest) return;
        var values = new JsonArray(applications.Select(application => new JsonObject
        {
            ["bundleIdentifier"] = application.BundleIdentifier,
            ["applicationName"] = application.ApplicationName,
            ["signingIdentifier"] = application.SigningIdentifier,
            ["teamIdentifier"] = application.TeamIdentifier,
            ["isForeground"] = application.IsForeground,
            ["observedAt"] = ProtocolCodec.FormatDate(application.ObservedAt),
        }).Cast<JsonNode?>().ToArray());
        EndpointState state = store.NextSequence();
        Ed25519DeviceIdentity identity = Identity(state);
        await SendAsync(socket, identity.Sign(ProtocolEnvelope.CreateUnsigned(
            state.DeviceId, state.Sequence, "activity.update",
            new JsonObject { ["applications"] = values }, identity.KeyId,
            lifetime: TimeSpan.FromMinutes(2))), token);
        lastActivityDigest = digest;
    }

    private async Task SendBrowserIfChangedAsync(ClientWebSocket socket, CancellationToken token)
    {
        EndpointRuntimeData runtime = Normalized(store.LoadOrCreate().Runtime);
        WindowsBrowserTab[] tabs = runtime.BrowserCollectionEnabled
            ? runtime.BrowserTabs.Take(128).ToArray() : [];
        string digest = string.Join('|', tabs.Select(value =>
            $"{value.Browser}:{value.Profile}:{value.Origin}:{value.Title}:{value.IsActive}"));
        if (digest == lastBrowserDigest) return;
        var values = new JsonArray(tabs.Select(tab => new JsonObject
        {
            ["browser"] = tab.Browser,
            ["profile"] = tab.Profile,
            ["title"] = tab.Title,
            ["origin"] = tab.Origin,
            ["isActive"] = tab.IsActive,
            ["observedAt"] = ProtocolCodec.FormatDate(tab.ObservedAt),
        }).Cast<JsonNode?>().ToArray());
        EndpointState state = store.NextSequence();
        Ed25519DeviceIdentity identity = Identity(state);
        await SendAsync(socket, identity.Sign(ProtocolEnvelope.CreateUnsigned(
            state.DeviceId, state.Sequence, "browser.update",
            new JsonObject { ["tabs"] = values }, identity.KeyId,
            lifetime: TimeSpan.FromMinutes(2))), token);
        lastBrowserDigest = digest;
    }

    private async Task<Guid> SendAnnouncementAsync(ClientWebSocket socket, CancellationToken token)
    {
        EndpointState state = store.NextSequence();
        Ed25519DeviceIdentity identity = Identity(state);
        var payload = new JsonObject
        {
            ["name"] = inventory.Collect().DeviceName,
            ["platform"] = "Windows",
            ["publicKey"] = Convert.ToBase64String(identity.PublicKey),
            ["capabilities"] = new JsonArray(
                ProductInfo.Capabilities.Select(value => JsonValue.Create(value)).ToArray()),
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
        Ed25519DeviceIdentity identity = Identity(version);
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

    private EndpointRuntimeData UpdateRuntime(Func<EndpointRuntimeData, EndpointRuntimeData> update)
    {
        EndpointRuntimeData? result = null;
        store.Update(state =>
        {
            result = Normalized(update(Normalized(state.Runtime)));
            return state with { Runtime = result };
        });
        return result!;
    }

    private static EndpointRuntimeData Normalized(EndpointRuntimeData? value)
    {
        EndpointRuntimeData runtime = value ?? new EndpointRuntimeData();
        DateTimeOffset now = DateTimeOffset.UtcNow;
        DateTimeOffset activityCutoff = now.AddDays(-Math.Clamp(runtime.ActivityRetentionDays, 1, 30));
        DateTimeOffset browserCutoff = now.AddDays(-Math.Clamp(runtime.BrowserRetentionDays, 1, 30));
        DateTimeOffset chatCutoff = now.AddDays(-30);
        return runtime with
        {
            ActivityRetentionDays = Math.Clamp(runtime.ActivityRetentionDays, 1, 30),
            BrowserRetentionDays = Math.Clamp(runtime.BrowserRetentionDays, 1, 30),
            Applications = runtime.Applications.Where(item => item.ObservedAt >= activityCutoff)
                .TakeLast(64).ToArray(),
            BrowserTabs = runtime.BrowserTabs.Where(item => item.ObservedAt >= browserCutoff)
                .TakeLast(128).ToArray(),
            Messages = runtime.Messages.Where(item => item.SentAt >= chatCutoff).TakeLast(200).ToArray(),
            Outbound = runtime.Outbound.Where(item => item.CreatedAt >= chatCutoff).TakeLast(100).ToArray(),
        };
    }

    private static IReadOnlyList<PendingOutboundMessage> AppendOutbound(
        IEnumerable<PendingOutboundMessage> current,
        PendingOutboundMessage item) => current.Append(item).TakeLast(100).ToArray();

    private static string AdvanceChatState(string current, string candidate)
    {
        if (current == "read") return current;
        if (candidate == "failed") return current is "queued" or "sent" ? candidate : current;
        int Rank(string state) => state switch
        {
            "queued" => 0, "sent" => 1, "delivered" => 2, "read" => 3, _ => -1,
        };
        return Rank(candidate) >= Rank(current) ? candidate : current;
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
        outboundSignal.Dispose();
        log.Write("service.stopped");
    }
}
