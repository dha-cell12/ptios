# VPN P5 TrollStore Background Agent

## Outcome

P5 removes the normal foreground requirement from TrollStore task 59 by
introducing a dedicated `vpnagent` candidate on loopback port `6016`. The
agent is embedded in `StreamControl.app`, signed with the app's `allow-vpn`
entitlement and Keychain access group, and spawned by `privhelper` with the
mobile persona (UID/GID 501). It is deliberately excluded from
`TSRootBinaries`; agent v2 also drops root privileges itself and refuses to
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

An explicit disconnect retains the P4 rule: disable on-demand before stopping
the tunnel. Existing request and response shapes for `590`, `591;;0`,
`591;;1`, and `592` remain unchanged.

## Capability contract

Task 97 reports:

```text
vpnState=background_agent_candidate
vpnQuery=agent_6016_app_6015_interface_fallback
vpnControl=agent_6016_with_foreground_fallback
vpnBackend=nevpnmanager_ikev2_background_agent_candidate
vpnBroker=vpnagent_6016_then_StreamControl_6015
vpnPhase=5
vpnBackgroundAgent=experimental_mobile_process
```

Task 592 is authoritative only when
`diagnostics_source=background_vpnagent`, `broker_ready=true`, and
`process_uid=501`. A streamd fallback snapshot reports both agent and
foreground-broker errors and must not be treated as proof that background
control works.

The state remains `background_agent_candidate` until a real device proves
query/connect/disconnect after StreamControl has been sent to the background.

## Device validation

Install the P5 TrollStore build, launch StreamControl once so the supervisor
starts the services, then return to the Home Screen or foreground another app.
Run the non-destructive check:

```powershell
$iphoneIP = "192.168.1.244"
./scripts/Test-TLinkVPNPhase5.ps1 -HostIP $iphoneIP
```

With a valid locally saved IKEv2 profile, test background connect:

```powershell
./scripts/Test-TLinkVPNPhase5.ps1 -HostIP $iphoneIP -RunConnect
```

Test disconnect separately. This also disables P4 Auto-Reconnect by policy:

```powershell
./scripts/Test-TLinkVPNPhase5.ps1 -HostIP $iphoneIP -RunDisconnect
```

Promotion requires `background_vpnagent`, UID/EUID 501, successful task 590
and both transitions while StreamControl remains backgrounded, plus real
egress IP/DNS verification through the live VPN.
