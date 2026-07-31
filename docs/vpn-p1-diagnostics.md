# VPN P1 Shared Diagnostics and Entitlement Probe

## Outcome

VPN P1 implements the action `2` reservation from the P0 contract. Both
rootfull and TrollStore now accept:

```text
592\r\n
```

and return:

```text
0;;<base64-json>\r\n
```

The JSON is produced by the same shared module,
`shared/TLinkVPNDiagnostics.mm`, in both runtimes. P1 remains read-only: it
does not add production VPN entitlements, save a profile, call
`startVPNTunnel`, stop a tunnel, or change the legacy action `0/1` behavior.

## What the probe proves

The shared module checks the process that actually handles the request:

- `SecTaskCopyValueForEntitlement` reads
  `com.apple.developer.networking.vpn.api` and
  `com.apple.developer.networking.networkextension`.
- The NetworkExtension framework is loaded read-only and the
  `NEVPNManager` class is checked for availability.
- No NetworkExtension manager method is exercised in P1.

The scope is deliberately reported as:

```text
entitlement_probe_scope=current_process_only
```

This prevents three invalid conclusions:

1. Root or platform status does not imply `allow-vpn`.
2. An entitlement present in another executable does not authorize the
   current process.
3. Class availability does not prove that profile save/start will succeed.

`control_preflight=candidate_unverified` means only that the current process
reports `allow-vpn` and can resolve `NEVPNManager`. Device testing of
load/save/start is still required before capability can become `ready`.

## Diagnostics schema v1

The executable schema fixture is
`test/fixtures/vpn-diagnostics-contract-v1.json`.

Important fields:

| Field | Meaning |
| --- | --- |
| `contract_version` | Legacy task 59 contract, currently `1` |
| `diagnostics_version` | JSON diagnostics schema, currently `1` |
| `runtime` | `rootfull` or `trollstore` |
| `state/query/control/backend/broker` | Honest current runtime baseline |
| `profile_identifier` | Non-secret ownership marker `tlinkauto-managed-v1` |
| `effective_connected` | TrollStore interface heuristic; `null` when unknown |
| `entitlements` | Current-process entitlement snapshot |
| `network_extension` | Framework/class availability; `api_exercised=0` in P1 |
| `control_preflight` | `candidate_unverified` or a blocked state |
| `generated_at_ms` | Snapshot generation time |

Unknown fields must be ignored by clients. Required v1 fields must not be
removed or renamed without incrementing `diagnostics_version`.

## Runtime behavior retained from P0

Rootfull:

- action `0`: existing unsupported stub
- action `1`: existing unsupported stub
- action `2`: shared diagnostics

TrollStore:

- action `0`: effective VPN-interface heuristic
- action `1`: explicit unsupported response
- action `2`: shared diagnostics with the current interface result

Action `2` rejects extra arguments with
`vpn_diagnostics_takes_no_arguments`.

The frozen rootfull task `97` capability markers for this historical phase
were:

```text
vpnPhase=1
vpnDiagnostics=task59_action2_base64_json_v1
vpnEntitlementProbe=sec_task_current_process
vpnProfileIdentifier=tlinkauto-managed-v1
```

P2 is allowed to advance the live rootfull values, while this block preserves
the exact P1 baseline used by the regression gate.

## Security boundary

Diagnostics contain no server address, username, password, shared secret,
certificate material, private key, provider configuration, or Keychain
value. Entitlement values and the fixed TLink profile ownership marker are
not credentials.

Production app and streamd entitlement files remain unchanged in P1. The POC
packet-tunnel entitlements remain isolated under `poc-trollstore/` and are not
compiled or packaged into StreamControl.

## Device check

After installing and restarting the relevant runtime:

```powershell
$raw = Invoke-TLinkTask -HostIP $iphoneIP -Task "592"
$b64 = ($raw -replace '^0;;', '').Trim()
$vpn = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($b64)
) | ConvertFrom-Json

$vpn | Format-List
$vpn.entitlements | Format-List
$vpn.network_extension | Format-List
```

Expected for the P1 package without VPN entitlements:

- `diagnostics_version=1`
- `broker_ready=0`
- `api_exercised=0`
- `allow_vpn=0`
- `control_preflight=blocked_missing_entitlement_or_framework`

The exact framework/class availability may vary by iOS version. A surprising
`allow_vpn=1` must be treated as evidence to investigate, not permission to
start a tunnel automatically.

## P2/P3 hand-off

The next phase may choose an entitled app/agent broker based on device
evidence. Before enabling action `1`, it must:

1. prove the entitlement on the broker process itself;
2. load only the TLink-owned profile identifier;
3. keep all configuration and secrets in foreground UI/Keychain;
4. observe connection state notifications until terminal state or timeout;
5. leave action `0` and diagnostics v1 backward-compatible.

Run the P1 static gate with:

```text
node scripts/check-vpn-p1-diagnostics.mjs
```
