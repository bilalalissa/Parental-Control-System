#!/bin/bash
set -euo pipefail

if [[ "$(id -u)" != "0" ]]; then
  echo "Run this visible uninstaller with sudo." >&2
  exit 1
fi

/bin/launchctl bootout system/com.bilalalissa.ParentalControlAgent.daemon >/dev/null 2>&1 || true
/usr/bin/pkill -x ParentalControlAgentUser >/dev/null 2>&1 || true
/usr/bin/pkill -x ParentalControlChild >/dev/null 2>&1 || true
/usr/bin/security delete-generic-password -s com.bilalalissa.ParentalControlAgent.device >/dev/null 2>&1 || true
/bin/rm -f -- /Library/LaunchDaemons/com.bilalalissa.ParentalControlAgent.daemon.plist
/bin/rm -f -- /Library/LaunchAgents/com.bilalalissa.ParentalControlAgent.user.plist
/bin/rm -f -- /Library/PrivilegedHelperTools/com.bilalalissa.ParentalControlAgent.daemon
/bin/rm -f -- /usr/local/bin/parental-control-agentctl
/bin/rm -rf -- "/Applications/Parental Control Child.app"
/bin/rm -rf -- "/Library/Application Support/ParentalControlAgent"
/usr/sbin/pkgutil --forget com.bilalalissa.ParentalControlChild.component >/dev/null 2>&1 || true
echo "Parental Control Child and its project-owned local data were removed. Restart login sessions to refresh all launchd state."
