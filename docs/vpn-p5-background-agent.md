# VPN P5 TrollStore Background Agent

## Outcome

P5 removes the normal foreground requirement from TrollStore task 59 by
introducing a dedicated `vpnagent` on loopback port `6016`. The
agent is embedded in `StreamControl.app`, signed with the app's `allow-vpn`
entitlement and Keychain access group, and spawned by `privhelper` with the
mobile persona (UID/GID 501). It is deliberately excluded from
`TSRootBinaries`; agent v3 also drops root privileges itself and refuses to
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
Keychain. On compatible TrollStore devices, **Save Profile** now uses the
XXTouch-compatible `VPNConnectionStore` backend and does not display the iOS
VPN confirmation sheet. The verified profile ID/name is stored in a mode-0600
ownership marker; task 59 may select, query, connect, and disconnect only that
profile through vpnagent while StreamControl remains backgrounded. If the
private API is absent, TLink retains the existing `NEVPNManager` fallback.
Missing bootstrap returns `vpn_not_configured` by design.

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

TLink retains the validated `NEVPNManager` backend as fallback and adds a
strict ownership layer around the private path: each new profile has a unique
TLink prefix, creation and selection are verified before the marker is
committed, and only the previous marker-matched TLink profile may be removed.
Foreign profiles are never enumerated into an ownership decision by name
alone. `Test-TLinkVPNPhase5.ps1` reports the private selector probe and whether
the ownership marker proves a mutation was completed.

## Capability contract

Task 97 reports:

```text
vpnState=background_control
vpnQuery=agent_6016_app_6015_interface_fallback
vpnControl=agent_6016_with_foreground_fallback
vpnBackend=hybrid_nevpnmanager_vpnconnectionstore_private
vpnBroker=vpnagent_6016_then_StreamControl_6015
vpnPhase=5
vpnBackgroundAgent=candidate_mobile_process_v3_private_compat
```

Task 592 is authoritative only when
`diagnostics_source=background_vpnagent`, `broker_ready=true`, and
`process_uid=501`. A streamd fallback snapshot reports both agent and
foreground-broker errors and must not be treated as proof that background
control works.

The state is promoted to `background_control` from device evidence: agent v3
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

For the private backend qualification, open Managed VPN once, enter the IKEv2
values, and tap **Save Profile**. No iOS VPN approval sheet should appear and
the result code should be `vpn_private_profile_saved`. Return to the Home
Screen, then verify that vpnagent v3 sees the ownership marker and profile:

```powershell
./scripts/Test-TLinkVPNPhase5.ps1 -HostIP $iphoneIP -RequirePrivateProfile
```

Expected fields include `manager_backend=vpnconnectionstore_private`,
`private_mutating_api_exercised=True`, and a non-empty `profile_identifier`.

With a valid locally saved IKEv2 profile, test background connect:

```powershell
./scripts/Test-TLinkVPNPhase5.ps1 -HostIP $iphoneIP -RequirePrivateProfile -RunConnect
```

Test disconnect separately. This also disables P4 Auto-Reconnect by policy:

```powershell
./scripts/Test-TLinkVPNPhase5.ps1 -HostIP $iphoneIP -RunDisconnect
```

P5 was promoted after the background agent identity/readiness and live connect
path passed. Release acceptance should continue to verify real egress IP/DNS
through the VPN and run the explicit disconnect test when its on-demand reset
side effect is acceptable.
