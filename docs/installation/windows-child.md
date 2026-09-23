# Windows Child Endpoint installation

`ParentalControlWindows-0.8.0-rc.4-x64.msi` is a visible Stage 08 test candidate for Windows 10 version 2004 or newer and Windows 11 on x64 hardware.

1. Verify the SHA-256 value supplied beside the MSI.
2. Sign in with the intended standard child account, then have an adult administrator run the MSI and approve Windows Installer.
3. Confirm **Parental Control Child** is visible in the Start menu and after sign-in. The dashboard must say that it is a visible family endpoint.
4. On the Apple-silicon Parent Controller, create one one-time pairing invitation and copy the full token.
5. In the Windows child dashboard, choose **Pair this PC**. Approve the Windows administrator prompt. The standard copy closes before the elevated copy opens; paste the invitation again in that single elevated window and pair.
6. Confirm the parent shows the Windows device as Online. Disconnect the LAN briefly and confirm it shows Offline plus last-seen rather than claiming the PC is powered off.
7. Confirm Chrome or Edge is installed machine-wide under Program Files. Extract `ParentalControlBrowserSharing-0.8.0-rc.2.zip` to an adult-controlled stable folder. In each intended Chrome or Edge profile, enable Developer mode, choose **Load unpacked**, and select the extracted `ParentalControlBrowserSharing` folder. Do not enable incognito access. Per-user browser installations are not admitted by this release's native-host identity check.
8. From the parent, enable application and browser sharing and choose 1–30 days of retention. Confirm the child UI shows the same read-only settings, application names/identities, and only enrolled tab titles/query-free origins.
9. Test text chat, a content-free Windows notification, explicit read state, and one 5–240 minute request. Approval is displayed but does not grant Windows usage time until Stage 09 enforcement exists.

A valid parent-issued invitation is accepted automatically over the authenticated LAN channel; the Parent Controller does not show a separate Accept dialog. If Windows reports a pairing failure, leave the Parent Controller open, create a fresh invitation, confirm both devices are on the same LAN, and retry before the invitation expires.

Stage 08 additionally shares bounded application names/executable identities/foreground state and, when separately enabled, enrolled Chrome/Edge tab titles and query-free HTTP(S) origins. It supports text chat/notifications and request-more-time. It does not collect window or page contents, command lines, URL paths/queries, private tabs, cookies, passwords, or traffic. It does not include Windows schedules, app/website restrictions, locking, shutdown, or other enforcement.

If installed files or startup registration need repair, open the classic **Control Panel > Programs and Features**, select **Parental Control Child**, and choose **Repair**. Windows Settings may expose only Uninstall. The equivalent command from an elevated PowerShell window is:

```powershell
msiexec.exe /fa "C:\full\path\ParentalControlWindows-0.8.0-rc.4-x64.msi" /norestart
```

Repair preserves a valid protected device identity and pairing. It cannot repair a removed browser extension; reload the extension separately in each intended Chrome or Edge profile.

To remove it, use **Apps > Installed apps > Parental Control Child > Uninstall**. Administrator approval is required. Uninstall removes the service, startup entry, native host/registrations, binaries, protected identity/configuration, and bounded logs; remove the visible extension from each browser profile separately. A later reinstall requires fresh pairing.

The candidate is unsigned until production Authenticode credentials are available. Windows may therefore show an unverified-publisher warning. Do not disable SmartScreen or other system protection globally; test only on a device you own and administer.
