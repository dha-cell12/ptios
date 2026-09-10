# VPN P5 TrollStore Background Agent

## Outcome

Task 59 uses the dedicated mobile-persona `vpnagent` on loopback port `6016`.
Agent v8 supports two profile backends without sending credentials over task 59:

```text
task 59 -> streamd -> vpnagent:6016 -> selected TLink profile
                                             | IKEv2 -> NEVPNManager
                                             + PPTP/L2TP/IPSec -> VPNConnectionStore
                         |
                         + failure -> StreamControl foreground broker:6015
query final fallback ----------------> utun/ipsec/ppp interface probe
```

The agent is embedded in `StreamControl.app`, signed with the focused VPN and
SystemConfiguration entitlements, and spawned by `privhelper` as UID/GID 501.
It is excluded from `TSRootBinaries`; it also drops root privileges itself and
refuses to serve unless its real and effective UID/GID are all 501. Rootfull
continues to use `tlinkauto-vpnd:6014`.

If the agent socket disappears, streamd invokes
`privhelper --ensure-vpnagent`, retries once, and then uses the foreground
broker fallback.

## Profile backends

IKEv2 keeps the already-qualified public `NEVPNManager` implementation. Its
password is stored in ThisDeviceOnly Keychain and iOS may request approval the
first time the profile is saved. Auto-Reconnect/On Demand remains available.

PPTP, L2TP, and IPSec mirror XXTouch's documented `vpnconf.create` contract:
they load `VPNPreferences.bundle`, call
`VPNConnectionStore.createVPNWithOptions:`, and select the returned service
with `setActiveVPNID:` or its graded variant. The private mutation now runs in
the embedded `privhelper` TSRootBinary instead of the foreground
`UIApplication`, matching XXTouch's daemon process boundary and avoiding the
public iOS VPN approval path. Password and shared secret cross that boundary
only in a randomly named, mode-0600, UID-501 one-shot plist. The helper accepts
only that exact directory/name/owner/mode, unlinks the request immediately
after reading it, and returns a credential-free result plist owned by UID 501.
Credentials are never placed in argv, task 59, the vpnagent socket, logs, or
TLink preferences.

The no-consent branch also carries the two values observed directly in the
XXTouch executable: `com.apple.private.networkextension.configuration=super`
and Keychain group `com.apple.managed.vpn.shared`. `allow-vpn` by itself is
not sufficient: iOS deliberately routes that public capability through the
"Add VPN Configurations" confirmation sheet. Task 592 exposes both retained
signing values as `private_configuration_super` and
`managed_vpn_keychain_access`.

The private options preserve the XXTouch defaults: string protocol names on
modern stores, numeric values `L2TP=0`, `PPTP=1`, and `IPSec=2` on older stores,
PPTP authentication type 0, other types authentication type 1, encryption
level 1, send-all-traffic enabled, and optional group. L2TP on Apple platforms
is L2TP-over-IPSec, so its machine-authentication shared secret is required
and is distinct from the user account password. IKEv2 is deliberately
excluded from the private constructor.

Only the exact private service ID/name/type stored in TLink's mode-0600 marker
is controlled or deleted. Saving IKEv2 removes that marker-owned legacy
profile. Saving a legacy profile leaves the working native IKEv2 profile
installed but makes the private marker authoritative for status and task 59.
Switching profile types requires the current tunnel to be disconnected.

The private legacy backend does not expose On Demand and returns
`vpn_private_on_demand_unsupported`. Saving a legacy profile never loads or
saves `NEVPNManager`; this keeps the direct private path from invoking the
public API approval flow. Explicit IKEv2 disconnect still disables
On Demand before stopping the tunnel.

## Boundary and safety

The loopback protocol accepts only `ping`, `query`, `connect`, `disconnect`,
and `diagnostics`. Profile configuration and credentials remain local to the
Managed VPN screen; neither task 59 nor vpnagent accepts them. The agent is
licensed through the existing `automation` feature and never receives a
Packet Tunnel Provider entitlement. Existing wire shapes for tasks `590`,
`591;;0`, `591;;1`, and `592` remain unchanged.
When neither owned backend is configured, control fails closed with
`vpn_not_configured`.

## Capability contract

Task 97 reports:

```text
vpnState=background_control
vpnQuery=agent_6016_app_6015_interface_fallback
vpnControl=agent_6016_with_foreground_fallback
vpnBackend=ikev2_nevpnmanager_legacy_private_no_consent
vpnBroker=vpnagent_6016_then_StreamControl_6015
vpnPhase=5
vpnBackgroundAgent=candidate_mobile_process_v9_super_configuration
```

Task 592 is authoritative only when
`diagnostics_source=background_vpnagent`, `broker_ready=true`, and
`process_uid=501`. A streamd fallback snapshot is not proof that background
control works.

## IKEv2 device validation

Install the TrollStore build and launch StreamControl once. In Managed VPN,
select IKEv2, enter the values, tap **Save IKEv2 Profile**, and accept the iOS
approval sheet if presented. Then background StreamControl:

```powershell
$iphoneIP = "192.168.1.244"
./scripts/Test-TLinkVPNPhase5.ps1 -HostIP $iphoneIP -RequireManagedProfile
./scripts/Test-TLinkVPNPhase5.ps1 -HostIP $iphoneIP -RequireManagedProfile -RunConnect
```

Expected evidence includes `agent_version=9`,
`manager_backend=nevpnmanager_ikev2`, `profile_type=IKEv2`, and a connected
task 590 query.

## L2TP no-confirm device validation

Disconnect the active IKEv2 tunnel. In Managed VPN, select L2TP and enter its
server, username, password, and IPSec shared secret. Group is optional. Tap
**Save L2TP Profile**. No iOS approval sheet should appear.

Validate creation first:

```powershell
./scripts/Test-TLinkVPNPhase5.ps1 -HostIP $iphoneIP `
  -RequirePrivateProfile -ExpectedPrivateType L2TP
```

Then keep StreamControl backgrounded and validate the actual transition:

```powershell
./scripts/Test-TLinkVPNPhase5.ps1 -HostIP $iphoneIP `
  -RequirePrivateProfile -ExpectedPrivateType L2TP -RunConnect
```

Expected evidence includes `manager_backend=vpnconnectionstore_private`,
`profile_type=L2TP`, `private_mutating_api_exercised=True`, and
`approval_path=privhelper_root_private_store_no_nevpnmanager`,
`connection_status=connected`. Also verify the system VPN icon and actual
egress IP/DNS; a successful control response alone cannot prove traffic is
tunneled.

Disconnect separately when the side effect is acceptable:

```powershell
./scripts/Test-TLinkVPNPhase5.ps1 -HostIP $iphoneIP -RunDisconnect
```
