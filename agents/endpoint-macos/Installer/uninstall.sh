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
/bin/rm -f -- /Library/Google/Chrome/NativeMessagingHosts/com.bilalalissa.parental_control.json
/bin/rm -f -- /Library/Microsoft/Edge/NativeMessagingHosts/com.bilalalissa.parental_control.json
CONSOLE_USER="$(/usr/bin/stat -f '%Su' /dev/console)"
CONSOLE_HOME="$(/usr/bin/dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}')"
if [[ "$CONSOLE_HOME" == /Users/* ]]; then
  ARC_HOST_DIRECTORY="$CONSOLE_HOME/Library/Application Support/Arc/User Data/NativeMessagingHosts"
  /bin/rm -f -- "$ARC_HOST_DIRECTORY/com.bilalalissa.parental_control.json"
  /bin/rmdir "$ARC_HOST_DIRECTORY" >/dev/null 2>&1 || true
fi
/bin/rmdir /Library/Google/Chrome/NativeMessagingHosts >/dev/null 2>&1 || true
/bin/rmdir /Library/Microsoft/Edge/NativeMessagingHosts >/dev/null 2>&1 || true
/bin/rm -rf -- "/Applications/Parental Control Child.app"
/bin/rm -rf -- "/Library/Application Support/ParentalControlAgent"
/usr/sbin/pkgutil --forget com.bilalalissa.ParentalControlChild.component >/dev/null 2>&1 || true
echo "Parental Control Child and its project-owned local data were removed. Restart login sessions to refresh all launchd state."
