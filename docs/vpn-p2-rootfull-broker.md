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

The frozen P2 capability baseline was:

```text
vpnState=broker_managed
vpnQuery=broker_localhost_6014
vpnControl=broker_localhost_6014
vpnBackend=nevpnmanager_ikev2
vpnBroker=tlinkauto_vpnd_6014
vpnPhase=2
vpnDiagnostics=task59_action2_base64_json_v1
vpnEntitlementProbe=broker_process_via_592
vpnProfileIdentifier=tlinkauto-managed-v1
```

Live IKEv2 connect/query/disconnect was reported working on rootfull on
2026-08-01. The current implementation is promoted by VPN P4; this document
continues to freeze the P2 broker and security baseline.

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
`vpn_license_denied`. A transition that returns to `Disconnected` reports
`vpn_connection_failed` without waiting for the full timeout.

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
the exact `com.tlinkauto.tlinkauto` Keychain group. The Security query uses
the real `kCFBooleanTrue` value for `kSecReturnPersistentRef`; using an
`NSNumber` here can make `SecItemAdd` reject the query. Server, username, password,
shared secret, certificates, and provider configuration are never accepted
through task `59` or the loopback broker protocol.

Example form values (replace them with values issued by the VPN server):

| Field | Example | Notes |
| --- | --- | --- |
| IKEv2 server address | `vpn.example.com` | Hostname or IP only; do not add `https://` or a path. |
| Remote identifier | `vpn.example.com` | Usually the identity in the server certificate. Leaving it empty uses the server address. |
| Username | `device01@example.com` | IKEv2/EAP account name. |
| Password | `the-issued-vpn-password` | Stored only in the device Keychain. |

Loopback destinations (`127.0.0.0/8`, `::1`, and `localhost`) are rejected
with `vpn_server_loopback_not_allowed`. On iOS they refer to the phone itself,
not the PC running the test. Use the LAN address of the IKEv2 host and make
UDP 500/4500 reachable from the phone.

This P2 form supports IKEv2 extended authentication with username/password.
It does not configure a pre-shared key, client certificate, WireGuard, or
OpenVPN profile.

If Keychain storage fails, the screen now shows the numeric `OSStatus` and a
safe native error description without logging the password. Rebuild and
reinstall the package before retesting because the entitlement and binary
must come from the same artifact.

While Connect or Disconnect is pending, the screen displays a spinner,
elapsed seconds, and the current `NEVPNStatus` refreshed once per second.
The final result remains single-shot, so the task `59` wire contract and the
broker's terminal-state requirement do not change.

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

Performance follow-up C04b limits port 6014 to eight admitted clients,
including queued and running handlers. Additional accepted clients are closed
immediately without a busy response; callers use their existing transport
failure handling. Socket and capacity are released together after completion
or exception. This does not replace the existing I/O/manager timeouts or bound
every underlying asynchronous manager operation. See
[IMPLEMENTATION-C04B.md](performance-audit/IMPLEMENTATION-C04B.md) for test and
device qualification status. TrollStore foreground/agent listeners are separate.

C04c gives request ingress one fixed 30-second window from admission entry,
including queued time. Incoming bytes do not renew it. Expired or fatally failed
reads close without dispatching the accumulated request; normal LF/EOF input is
preserved. This window ends at response dispatch; manager waits and response
writes retain their separate behavior. See
[IMPLEMENTATION-C04C.md](performance-audit/IMPLEMENTATION-C04C.md).

C04d extends that accepted-time window through broker waits and response
writes. The existing 8/24-second wait limits are capped by the remaining outer
budget and include operation starter time. Callback results are synchronized;
duplicates and late completions cannot replace the consumed result. Response
writes use nonblocking sends and the same deadline. This is cooperative:
synchronous APIs can overrun until they return, and manager timeout does not
cancel or roll back VPN effects. See
[IMPLEMENTATION-C04D.md](performance-audit/IMPLEMENTATION-C04D.md).

C04e separately limits pending manager submissions to eight per broker process,
shared by query, connect, disconnect and diagnostics status. Client timeout does
not release this admission: both starter exit and a terminal callback are needed.
When full, admitted query/control requests return `-1;;vpn_broker_busy`; diagnostics
still returns static fields with manager status unavailable and last_error set
to `vpn_broker_busy`. Ordinary license checks retain precedence. Late callbacks
restore capacity; stale callbacks cannot retire a replacement slot. A missing
callback or uncertain throwing starter keeps its slot until completion or process
restart, so eight permanently lost callbacks can keep the broker busy. There is
no automatic expiry, operation cancellation or rollback. This counts broker
submissions, not backend subtasks or work from other callers. See
[IMPLEMENTATION-C04E.md](performance-audit/IMPLEMENTATION-C04E.md).

C04f gives the SpringBoard client its own fixed 30-second window across socket
setup, nonblocking connect, exact request writes and response reads. Polls recheck
continuous time at intervals of at most 250 ms; incoming bytes do not renew the
deadline. Timeout/fatal read errors discard an incomplete prefix, while normal
LF/EOF framing and the response decoder stay compatible. The existing response
cap is enforced at exactly 1 MiB. Socket ownership is scoped across exceptions.
The client and broker windows are independent, and the outer IPC path remains
synchronous; client timeout does not cancel manager effects. See
[IMPLEMENTATION-C04F.md](performance-audit/IMPLEMENTATION-C04F.md).

C04g captures the client's current native caller budget and observes its stop
state throughout IO, including cancellation, inherited native deadlines and
output exhaustion. A stopped caller opens no socket; in-flight waits stop at
the next checkpoint/poll return and release the scoped descriptor. Native clock
epochs are not converted, and changing TLS in nested code cannot replace the
captured caller. The independent 30-second socket ceiling and existing authority,
cleanup and response policies remain. This stops client waiting without cancelling
an already submitted broker operation or rolling back effects. See
[IMPLEMENTATION-C04G.md](performance-audit/IMPLEMENTATION-C04G.md).

C04h routes reply-bearing daemon task 59 through a dedicated serial sender and
SpringBoard CF port/run-loop, `com.tlinkauto.tlinkautod.springboard.vpn.v1`.
Its private TVP1 envelope admits only task 59 with a native deadline at most
30 seconds ahead and 8..4095 non-NUL payload bytes. Missing private support,
oversize input and transport failure return explicit errors without legacy
retry. Upgrade daemon and tweak together. Existing task/license/broker policies
and healthy replies remain; direct legacy callers stay compatible. The daemon
ordinary task queue still serializes VPN with other ordinary network tasks,
so this is IPC-owner isolation, with task-lane isolation still pending. See
[IMPLEMENTATION-C04H.md](performance-audit/IMPLEMENTATION-C04H.md).

C04i adds a serial daemon work lane for task 59, capped at two running/queued/
completion-pending requests within the existing fourteen ordinary slots. The two
reserved image slots and sixteen-task total remain. Excess VPN clients use the
existing overload-close behavior. Its native 30-second deadline and cancellation
token start before enqueue; queued time is not renewed by IPC. Disconnect marks
the budget stopped, but capacity retires only after socket-owner completion ACK.
Ordinary/image clients can progress independently; each client's FIFO is kept.
Different clients may now interleave differently. An executing CF wait remains
non-preemptible, and no remote manager cancellation is added. See
[IMPLEMENTATION-C04I.md](performance-audit/IMPLEMENTATION-C04I.md).

C04j gives pending native NEVPNManager transitions an owned one-shot timer and
observer with a synchronized first-result gate. Terminal completion cancels the
timer and removes the observer before callback delivery, replacing the former
dispatch_after closure retained until its deadline. Setup unwind retires known
resources; timer allocation failure returns vpn_transition_timer_failed before
start/stop effects. Timeout anchor/clamp, profile/license checks and healthy
replies remain. This does not cancel a tunnel transition or coalesce operations.
The shared native path also applies to TrollStore; its private backend is
unchanged. See [IMPLEMENTATION-C04J.md](performance-audit/IMPLEMENTATION-C04J.md).

Static gates prove packaging, ownership checks, license gates, secret
handling, bounded transitions, and wire compatibility. Only a rootfull device
with a real IKEv2 server can prove that:

- the ad-hoc `allow-vpn` entitlement is honored on the target iOS build;
- the mobile LaunchDaemon can access the app-owned manager preferences and
  Keychain persistent reference;
- the selected IKEv2 parameters match the server;
- real traffic and DNS traverse the tunnel.

Keep TrollStore at VPN P1 until this rootfull path is stable on device.
