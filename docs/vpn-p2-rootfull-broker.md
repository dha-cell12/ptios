# VPN P2 Rootfull IKEv2 Broker

## Outcome

VPN P2 enables the first production-shaped task `59` control path on
rootfull. It uses the built-in iOS IKEv2 provider through
`NEVPNManager.sharedManager`; it does not ship or enable the packet-tunnel
POC.

The architecture is:

```text
PC client :6000
  -> tlinkautod / SpringBoard task gate
  -> pccontrol loopback client
  -> 127.0.0.1:6014
  -> tlinkauto-vpnd (mobile LaunchDaemon, allow-vpn)
  -> NEVPNManager / TLink-owned IKEv2 profile
```

The broker executable is `/usr/libexec/tlinkauto-vpnd`. Launchd runs it as
`mobile`, and it binds only to `127.0.0.1:6014`.

## Task behavior

The legacy bytes remain unchanged:

| Request | Behavior |
| --- | --- |
| `590\r\n` | Query the owned manager; returns `0;;0/1\r\n` |
| `591;;0\r\n` | Stop and wait for `Disconnected` |
| `591;;1\r\n` | Start and wait for `Connected` |
| `592\r\n` | Return broker-process entitlement and manager diagnostics |

Action `1` success is returned only after observing the terminal
`NEVPNStatus` notification. The transition wait is bounded to 20 seconds.
Calling `startVPNTunnelAndReturnError:` successfully is not sufficient for a
task success.

Stable errors include `vpn_broker_unavailable`, `vpn_not_configured`,
`vpn_profile_disabled`, `vpn_start_failed`, `vpn_transition_timeout`, and
`vpn_license_denied`.

## Profile ownership

P2 uses `NEVPNManager.sharedManager` and accepts only the fixed description:

```text
TLinkauto Managed VPN (tlinkauto-managed-v1)
```

If a loaded manager already contains a different description, configuration
fails with `vpn_foreign_profile_present`. The broker does not enumerate,
select, edit, or stop third-party/MDM VPN profiles.

The first backend is IKEv2 username/password with:

- AES-256 encryption;
- SHA-256 integrity;
- Diffie-Hellman group 14;
- extended authentication;
- on-demand explicitly disabled.

## Configuration and secrets

Open:

```text
TLinkauto -> Settings -> VPN -> Managed IKEv2 VPN
```

Enter server address, optional remote identifier, username, and password,
then press **Save Profile**. iOS may display its VPN configuration consent
prompt; approve it in the foreground.

The password is stored as a persistent Keychain reference using
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. The app and broker share
the existing narrow TLinkauto Keychain group. Server, username, password,
shared secret, certificates, and provider configuration are never accepted
through task `59` or the loopback broker protocol.

The loopback protocol accepts exactly four fixed commands: `query`,
`connect`, `disconnect`, and `diagnostics`.

## Entitlements and signing

`layout/entitlements.plist` adds only:

```xml
<key>com.apple.developer.networking.vpn.api</key>
<array>
    <string>allow-vpn</string>
</array>
```

This entitlement signs the TLinkauto app and `tlinkauto-vpnd`. The shortcut
extension uses `layout/shortcut-entitlements.plist`, which deliberately does
not contain VPN or NetworkExtension entitlements.

Every broker query/connect/disconnect command independently checks the
`automation` license feature. Diagnostics remain available for recovery.

## Install and launch

The package installs:

```text
/usr/libexec/tlinkauto-vpnd
/Library/LaunchDaemons/com.tlinkauto.vpn-broker.plist
```

Post-install reloads the broker and records launchctl output at:

```text
/var/mobile/Library/TLinkauto/vpn-broker-launchctl.log
```

Runtime stdout/stderr are under
`/var/mobile/Library/TLinkauto/vpn-broker*.log`.

## Device validation

1. Install the rootfull package and respring.
2. Open TLinkauto and save the IKEv2 profile from Settings.
3. Verify diagnostics:

```powershell
$raw = Invoke-TLinkTask -HostIP $iphoneIP -Task "592"
$b64 = ($raw -replace '^0;;', '').Trim()
$vpn = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($b64)
) | ConvertFrom-Json
$vpn | Format-List
$vpn.entitlements | Format-List
$vpn.manager_status | Format-List
```

Expected:

- `phase=2`
- `broker_ready=1`
- `entitlement_probe_scope=broker_process`
- `allow_vpn=1`
- `profile_identifier=tlinkauto-managed-v1`
- `api_exercised=0` refers only to the generic P1 class probe; manager status
  and task transition results are the P2 execution evidence.

4. Query, connect, query, disconnect, query:

```powershell
Invoke-TLinkTask -HostIP $iphoneIP -Task "590"
Invoke-TLinkTask -HostIP $iphoneIP -Task "591;;1"
Invoke-TLinkTask -HostIP $iphoneIP -Task "590"
Invoke-TLinkTask -HostIP $iphoneIP -Task "591;;0"
Invoke-TLinkTask -HostIP $iphoneIP -Task "590"
```

Expected response sequence is `0`, `1`, `1`, `0`, `0`. Confirm real egress
traffic separately; `Connected` proves the iOS manager state, not that the
remote VPN routes or DNS are correct.

5. Revoke/expire the automation license and verify direct broker control is
denied as well as task `59`.

## Known validation boundary

Static gates prove packaging, ownership checks, license gates, secret
handling, bounded transitions, and wire compatibility. Only a rootfull device
with a real IKEv2 server can prove that:

- the ad-hoc `allow-vpn` entitlement is honored on the target iOS build;
- the mobile LaunchDaemon can access the app-owned manager preferences and
  Keychain persistent reference;
- the selected IKEv2 parameters match the server;
- real traffic and DNS traverse the tunnel.

Keep TrollStore at VPN P1 until this rootfull path is stable on device.
