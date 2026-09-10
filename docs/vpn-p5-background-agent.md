# VPN P5 TrollStore Background Agent

## Outcome

P5 removes the normal foreground requirement from TrollStore task 59 by
introducing a dedicated `vpnagent` on loopback port `6016`. The
agent is embedded in `StreamControl.app`, signed with the app's `allow-vpn`
entitlement and Keychain access group, and spawned by `privhelper` with the
mobile persona (UID/GID 501). It is deliberately excluded from
`TSRootBinaries`; agent v6 also drops root privileges itself and refuses to
serve unless real/effective UID and GID are all 501.

```text
task 59 -> streamd -> vpnagent:6016 -> NEVPNManager
                         |
                         + failure -> StreamControl foreground broker:6015
query final fallback ----------------> utun/ipsec/ppp interface probe
```

The foreground broker remains available as a compatibility fallback. Rootfull
continues to use `tlinkauto-vpnd:6014` and is not changed by P5.

If the agent socket disappears, streamd invokes the narrow
`privhelper --ensure-vpnagent` recovery command, respawns the agent as mobile,
and retries the original command once before using the foreground fallback.

## Boundary and safety

The loopback protocol accepts only `ping`, `query`, `connect`, `disconnect`,
and `diagnostics`. Profile configuration and credentials remain local to the
StreamControl VPN settings screen and Keychain; neither task 59 nor vpnagent
accepts them. The agent is licensed through the existing `automation` feature.
It receives `allow-vpn`, but never receives a Packet Tunnel Provider
entitlement.

First-run credentials intentionally remain local to the Managed VPN screen and
Keychain. **Save Profile** uses `NEVPNManager`, restoring the native IKEv2
construction path already proven on the target TrollStore device and iOS
version. Before saving, TLink removes only a marker-owned profile left by the
former private constructor. Task 59 still queries, connects, and disconnects
the resulting profile through vpnagent while StreamControl remains
backgrounded. Missing bootstrap returns `vpn_not_configured` by design.

An explicit disconnect retains the P4 rule: disable on-demand before stopping
the tunnel. Existing request and response shapes for `590`, `591;;0`,
`591;;1`, and `592` remain unchanged.

## XXTouch compatibility comparison

XXTouch's `vpnconf` module loads the private
`/System/Library/PreferenceBundles/VPNPreferences.bundle`, obtains
`VPNConnectionStore.sharedInstance`, creates profiles with
`createVPNWithOptions:`, selects them with `setActiveVPNID:` (or the graded
variant), and drives the current connection directly. That explains why its
profile bootstrap can avoid the normal `NEVPNManager` confirmation UI.

The verified XXTouch artifact also carries `preferences.plist`
`SCPreferences-write-access`, `SCDynamicStore-write-access`, and
`com.apple.managedconfiguration.profiled-access`. TLink now carries this
focused commit set in the app and vpnagent, without copying XXTouch's unrelated
MDM, telephony, app-installation, or root-management entitlements.

TLink keeps the private API only for compatibility probing, legacy control,
and migration cleanup. Only the exact ID/name stored in the mode-0600 marker
may be removed; foreign profiles are never deleted by a broad name match. New
profiles are no longer constructed from an undocumented private options
dictionary.

## Capability contract

Task 97 reports:

```text
vpnState=background_control
vpnQuery=agent_6016_app_6015_interface_fallback
vpnControl=agent_6016_with_foreground_fallback
vpnBackend=nevpnmanager_profile_private_compat_control
vpnBroker=vpnagent_6016_then_StreamControl_6015
vpnPhase=5
vpnBackgroundAgent=candidate_mobile_process_v6_ne_profile_restore
```

Task 592 is authoritative only when
`diagnostics_source=background_vpnagent`, `broker_ready=true`, and
`process_uid=501`. A streamd fallback snapshot reports both agent and
foreground-broker errors and must not be treated as proof that background
control works.

The state is promoted to `background_control` from device evidence: agent v6
reported `background_vpnagent`, `broker_ready=true`, UID/EUID/GID/EGID 501,
and task `591;;1` plus the connected task `590` check succeeded while
StreamControl remained backgrounded.

## Device validation

Install the P5 TrollStore build, launch StreamControl once so the supervisor
starts the services, then return to the Home Screen or foreground another app.
Run the non-destructive check:

```powershell
$iphoneIP = "192.168.1.244"
./scripts/Test-TLinkVPNPhase5.ps1 -HostIP $iphoneIP
```

Open Managed VPN once, enter the IKEv2 values, and tap **Save Profile**. Accept
the native iOS VPN approval sheet if the device presents it. Return to the Home
Screen, then verify that vpnagent v6 sees the managed profile:

```powershell
./scripts/Test-TLinkVPNPhase5.ps1 -HostIP $iphoneIP -RequireManagedProfile
```

Expected fields include `manager_backend=nevpnmanager_ikev2`,
`configured=True`, and a non-empty `profile_identifier`.

With a valid locally saved IKEv2 profile, test background connect:

```powershell
./scripts/Test-TLinkVPNPhase5.ps1 -HostIP $iphoneIP -RequireManagedProfile -RunConnect
```

Test disconnect separately. This also disables P4 Auto-Reconnect by policy:

```powershell
./scripts/Test-TLinkVPNPhase5.ps1 -HostIP $iphoneIP -RunDisconnect
```

P5 was promoted after the background agent identity/readiness and live connect
path passed. Release acceptance should continue to verify real egress IP/DNS
through the VPN and run the explicit disconnect test when its on-demand reset
side effect is acceptable.
