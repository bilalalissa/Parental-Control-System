#!/bin/bash

set -euo pipefail

HOST_BUNDLE_ID="com.bilalalissa.ParentalControlChild"
NETWORK_BUNDLE_ID="com.bilalalissa.ParentalControlNetworkFilter"
EXECUTION_BUNDLE_ID="com.bilalalissa.ParentalControlExecutionFilter"

host_profile=""
network_profile=""
execution_profile=""

usage() {
  /bin/cat <<'USAGE'
Usage: check_stage06d_readiness.sh \
  --host-profile PATH \
  --network-profile PATH \
  --execution-profile PATH

Validates local, non-secret Stage 06D signing prerequisites. Profiles are read
in place, decoded only inside a private temporary directory, and never copied
to the repository or printed. Exit status 0 means ready; 2 means blocked.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host-profile)
      [[ $# -ge 2 ]] || { usage >&2; exit 64; }
      host_profile="$2"
      shift 2
      ;;
    --network-profile)
      [[ $# -ge 2 ]] || { usage >&2; exit 64; }
      network_profile="$2"
      shift 2
      ;;
    --execution-profile)
      [[ $# -ge 2 ]] || { usage >&2; exit 64; }
      execution_profile="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      /bin/echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ "$(/usr/bin/uname -s)" != "Darwin" ]]; then
  /bin/echo "STAGE-06D READINESS: BLOCKED"
  /bin/echo "- macOS signing tools are required."
  exit 2
fi

work_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/parental-control-stage06d.XXXXXX")"
trap '/bin/rm -rf -- "$work_dir"' EXIT

blocked=0
team_ids=()

report_blocked() {
  /bin/echo "- $1"
  blocked=1
}

identity_output="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"
if /usr/bin/grep -q '"Developer ID Application:' <<<"$identity_output"; then
  /bin/echo "- Developer ID Application identity: available"
else
  report_blocked "Developer ID Application identity: missing"
fi

read_profile_value() {
  local plist="$1"
  local key_path="$2"
  /usr/libexec/PlistBuddy -c "Print $key_path" "$plist" 2>/dev/null || true
}

validate_profile() {
  local role="$1"
  local path="$2"
  local bundle_id="$3"
  local entitlement_key="$4"
  local entitlement_value="$5"
  local decoded="$work_dir/$role.plist"

  if [[ -z "$path" ]]; then
    report_blocked "$role provisioning profile: not supplied"
    return
  fi
  if [[ ! -f "$path" ]]; then
    report_blocked "$role provisioning profile: file not found"
    return
  fi
  if ! /usr/bin/security cms -D -i "$path" >"$decoded" 2>/dev/null; then
    report_blocked "$role provisioning profile: could not be decoded"
    return
  fi

  local application_identifier
  application_identifier="$(read_profile_value "$decoded" ':Entitlements:application-identifier')"
  if [[ "$application_identifier" != *".$bundle_id" ]]; then
    report_blocked "$role provisioning profile: explicit App ID does not match $bundle_id"
    return
  fi

  local team_id
  team_id="$(read_profile_value "$decoded" ':Entitlements:com.apple.developer.team-identifier')"
  if [[ -z "$team_id" ]]; then
    team_id="$(read_profile_value "$decoded" ':TeamIdentifier:0')"
  fi
  if [[ -z "$team_id" ]]; then
    report_blocked "$role provisioning profile: Team ID missing"
    return
  fi

  local entitlement
  entitlement="$(read_profile_value "$decoded" ":Entitlements:$entitlement_key")"
  if [[ "$entitlement" != *"$entitlement_value"* ]]; then
    report_blocked "$role provisioning profile: required managed entitlement missing"
    return
  fi

  team_ids+=("$team_id")
  /bin/echo "- $role provisioning profile: valid"
}

validate_profile \
  "host app" \
  "$host_profile" \
  "$HOST_BUNDLE_ID" \
  "com.apple.developer.system-extension.install" \
  "true"

validate_profile \
  "network filter" \
  "$network_profile" \
  "$NETWORK_BUNDLE_ID" \
  "com.apple.developer.networking.networkextension" \
  "content-filter-provider-systemextension"

validate_profile \
  "execution filter" \
  "$execution_profile" \
  "$EXECUTION_BUNDLE_ID" \
  "com.apple.developer.endpoint-security.client" \
  "true"

if [[ ${#team_ids[@]} -eq 3 ]]; then
  if [[ "${team_ids[0]}" == "${team_ids[1]}" && "${team_ids[1]}" == "${team_ids[2]}" ]]; then
    /bin/echo "- Team ID alignment: valid"
  else
    report_blocked "Team ID alignment: profiles do not belong to one team"
  fi
fi

if [[ $blocked -ne 0 ]]; then
  /bin/echo "STAGE-06D READINESS: BLOCKED"
  /bin/echo "No profile, identity, or decoded entitlement data was copied into the repository."
  exit 2
fi

/bin/echo "STAGE-06D READINESS: READY"
/bin/echo "Profiles and identity passed structural checks; signed-build and physical activation checks remain required."
