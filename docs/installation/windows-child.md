# Windows Child Endpoint installation

`ParentalControlWindows-0.7.0-rc.1-x64.msi` is a visible Stage 07 test candidate for Windows 10 version 2004 or newer and Windows 11 on x64 hardware.

1. Verify the SHA-256 value supplied beside the MSI.
2. Sign in with the intended standard child account, then have an adult administrator run the MSI and approve Windows Installer.
3. Confirm **Parental Control Child** is visible in the Start menu and after sign-in. The dashboard must say that it is a visible family endpoint.
4. On the Apple-silicon Parent Controller, create one one-time pairing invitation and copy the full token.
5. In the Windows child dashboard, choose **Pair this PC**. Approve the Windows administrator prompt, paste the invitation again in the elevated visible window, and pair.
6. Confirm the parent shows the Windows device as Online. Disconnect the LAN briefly and confirm it shows Offline plus last-seen rather than claiming the PC is powered off.

Stage 07 shares only bounded device, uptime, coarse session, physical-network, and service-health metadata. It does not include app/browser monitoring, website restrictions, chat, schedules, locking, shutdown, or other enforcement.

To remove it, use **Apps > Installed apps > Parental Control Child > Uninstall**. Administrator approval is required. Uninstall removes the service, startup entry, binaries, protected identity/configuration, and bounded logs; a later reinstall requires fresh pairing.

The candidate is unsigned until production Authenticode credentials are available. Windows may therefore show an unverified-publisher warning. Do not disable SmartScreen or other system protection globally; test only on a device you own and administer.
