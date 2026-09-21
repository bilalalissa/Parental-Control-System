using System.Text.Json.Nodes;

namespace ParentalControl.Windows.Core;

public sealed record WindowsApplicationActivity(
    string BundleIdentifier,
    string ApplicationName,
    string? SigningIdentifier,
    string? TeamIdentifier,
    bool IsForeground,
    DateTimeOffset ObservedAt);

public sealed record WindowsBrowserTab(
    string Browser,
    string Profile,
    string Title,
    string Origin,
    bool IsActive,
    DateTimeOffset ObservedAt);

public sealed record WindowsChatMessage(
    Guid Id,
    Guid ThreadId,
    DateTimeOffset SentAt,
    string Sender,
    string Text,
    string State,
    string Audience,
    bool IsFromParent,
    DateTimeOffset? EditedAt = null,
    DateTimeOffset? DeletedAt = null);

public sealed record WindowsTimeRequest(
    Guid Id,
    int RequestedMinutes,
    string Note,
    DateTimeOffset CreatedAt,
    string State = "pending",
    DateTimeOffset? ResolvedAt = null);

public sealed record PendingOutboundMessage(
    Guid Id,
    string Type,
    string PayloadJson,
    DateTimeOffset CreatedAt);

public sealed record EndpointRuntimeData
{
    public bool ActivityCollectionEnabled { get; init; } = true;
    public int ActivityRetentionDays { get; init; } = 7;
    public bool BrowserCollectionEnabled { get; init; }
    public int BrowserRetentionDays { get; init; } = 7;
    public IReadOnlyList<WindowsApplicationActivity> Applications { get; init; } = [];
    public IReadOnlyList<WindowsBrowserTab> BrowserTabs { get; init; } = [];
    public IReadOnlyList<WindowsChatMessage> Messages { get; init; } = [];
    public IReadOnlyList<PendingOutboundMessage> Outbound { get; init; } = [];
    public WindowsTimeRequest? LatestTimeRequest { get; init; }
}

public sealed record BrowserNativeRequest(
    string Type,
    string Browser,
    string Profile,
    IReadOnlyList<BrowserNativeTab>? Tabs = null,
    long? PolicyVersion = null,
    string? PolicyState = null);

public sealed record BrowserNativeTab(
    string Title,
    string Origin,
    bool Active,
    long ObservedAt);

public sealed record BrowserNativeResponse(
    bool Accepted,
    bool Enabled,
    string Browser,
    string? Error = null,
    bool WebsitePolicySupported = false);

public static class Stage08Validation
{
    public static readonly HashSet<string> ChatAudiences =
        new(["direct", "family-group", "announcement"], StringComparer.Ordinal);
    public static readonly HashSet<string> ChatStates =
        new(["queued", "sent", "delivered", "read", "failed"], StringComparer.Ordinal);

    public static string Bound(string value, int characters) =>
        value.Length <= characters ? value : value[..characters];

    public static WindowsApplicationActivity Validate(WindowsApplicationActivity value)
    {
        string identifier = Bound(value.BundleIdentifier.Trim(), 200);
        string name = Bound(value.ApplicationName.Trim(), 120);
        if (identifier.Length is < 3 || name.Length == 0)
            throw new InvalidDataException("Application metadata is incomplete.");
        return value with
        {
            BundleIdentifier = identifier,
            ApplicationName = name,
            SigningIdentifier = value.SigningIdentifier is null
                ? null : Bound(value.SigningIdentifier.Trim(), 200),
            TeamIdentifier = value.TeamIdentifier is null
                ? null : Bound(value.TeamIdentifier.Trim(), 64),
            ObservedAt = value.ObservedAt.ToUniversalTime(),
        };
    }

    public static WindowsBrowserTab Validate(
        string browser, string profile, BrowserNativeTab value)
    {
        browser = Bound(browser.Trim().ToLowerInvariant(), 40);
        profile = Bound(profile.Trim(), 80);
        string title = Bound(value.Title.Trim(), 300);
        if (browser.Length == 0 || profile.Length == 0 || title.Length == 0
            || !Uri.TryCreate(value.Origin, UriKind.Absolute, out Uri? uri)
            || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps)
            || string.IsNullOrWhiteSpace(uri.Host))
        {
            throw new InvalidDataException("Browser metadata is invalid.");
        }
        string origin = uri.GetLeftPart(UriPartial.Authority);
        DateTimeOffset observed = value.ObservedAt > 0
            ? DateTimeOffset.FromUnixTimeMilliseconds(value.ObservedAt)
            : DateTimeOffset.UtcNow;
        if (observed > DateTimeOffset.UtcNow.AddMinutes(2)) observed = DateTimeOffset.UtcNow;
        return new WindowsBrowserTab(browser, profile, title, origin, value.Active, observed);
    }

    public static JsonObject ParsePayload(PendingOutboundMessage item) =>
        JsonNode.Parse(item.PayloadJson) as JsonObject
        ?? throw new InvalidDataException("Queued payload is invalid.");
}
