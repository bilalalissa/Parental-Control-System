# Canonical policy specification

[`policy.schema.json`](policy.schema.json) defines the platform-neutral signed policy document. It describes policy data, not privileged enforcement. Every endpoint must validate a policy, verify its signature and freshness, persist it safely, and evaluate the same golden vectors before it may enforce anything.

## Evaluation inputs

An implementation evaluates a policy against:

- trusted wall-clock UTC and configured IANA time zone;
- monotonic active-use elapsed time for the local policy day;
- latest authenticated immediate command, if still valid;
- a valid short-lived local adult session, if present;
- signed exceptions and bonus-minute state;
- device capabilities and current session state.

Clock rollback must not restore consumed quota or revive expired commands. Sleep, restart, controller outage, daylight-saving transitions, and cross-midnight windows require explicit tests before enforcement stages.

## Precedence

1. Valid short-lived local adult override.
2. Latest authenticated parent immediate command.
3. Signed date-specific exception.
4. Blocked or bedtime interval.
5. Daily active-use quota, including available bonus minutes.
6. Recurring allowed window.
7. Default deny outside allowed windows.

`lock` is the default restrictive action. `logoff`, `restart`, and `shutdown` require an explicit policy, warning, capability check, authenticated command path, audit record, and graceful handling of unsaved work. Force behavior is outside this schema and disabled by design.

## Time semantics

Recurring windows are local civil time in `timezone`; an end earlier than a start crosses midnight. Absolute blocked intervals, exceptions, policy effectiveness, and expiry are RFC 3339 timestamps. During a daylight-saving gap, nonexistent local times advance to the next valid instant; during a fold, the earlier instant begins a window and the later instant ends it. Platform implementations must use a time-zone database and match the golden vectors.
