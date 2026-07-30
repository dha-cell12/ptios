# VPN P0 Baseline and Wire Contract v1

## Scope

VPN P0 freezes the legacy task `59` grammar, records the honest capability
baseline for both runtimes, and defines the security boundary for the
TLink-owned VPN path. It does not add a Network Extension entitlement, create
or save a VPN profile, start or stop a tunnel, or port the packet-tunnel POC
into either production runtime.

The production target is a TLink-owned profile on both rootfull and
TrollStore. Control of arbitrary third-party or MDM-owned VPN profiles is a
separate experimental track and must not silently change task `59`.

## Legacy task 59 contract

Port `6000` keeps the two-digit task prefix and CRLF line framing:

| Operation | Request | Contract-v1 success |
| --- | --- | --- |
| Query effective VPN connectivity | `590\r\n` | `0;;0\r\n` or `0;;1\r\n` |
| Disconnect selected TLink profile | `591;;0\r\n` | `0;;0\r\n` |
| Connect selected TLink profile | `591;;1\r\n` | `0;;1\r\n` |
| Diagnostics (reserved for VPN P1) | `592\r\n` | `0;;<base64-json>\r\n` |

For action `1`, success means the requested terminal state was observed, not
merely that an asynchronous start/stop call returned. A future broker must use
a bounded wait and return `-1;;<stable_error>\r\n` on denial, timeout, invalid
configuration, or an unavailable backend.

Action `0` remains the legacy boolean view of effective VPN connectivity so
`webtango/tlinkauto/client.py::is_vpn_on()` remains compatible. During P0,
TrollStore derives this value from an active VPN-like interface. This is a
heuristic and does not prove that the active tunnel is the selected
TLink-owned profile. Rootfull has no query implementation yet and returns its
existing stub error.

Action `2` is reserved. P0 does not implement it. Its future JSON payload must
include `contract_version`, runtime, backend, entitlement state, profile
ownership, configured/enabled flags, observed connection state, last error,
and transition timestamps. Unknown fields must be ignored by clients.

The executable fixture is
`test/fixtures/vpn-wire-contract-v1.json`.

## P0 runtime baseline

| Runtime | Query | Set/connect | Backend | Broker |
| --- | --- | --- | --- | --- |
| rootfull | Unsupported | Unsupported | `stub` | Not implemented |
| TrollStore | `utun`/VPN-interface heuristic | Unsupported | `interface_probe` | Not implemented |

This baseline is deliberately explicit:

- Root privileges alone are not treated as proof of Network Extension
  entitlement.
- `enabled=true` on a profile is not considered connected.
- An interface probe is not described as profile ownership or control.
- Opening Settings is manual assistance, never a successful connect result.
- The existing `poc-trollstore/NEManager.mm` is lifecycle and packaging
  evidence only. Its sample packet tunnel does not forward production traffic
  and must not be promoted as a VPN backend.

Task `97` exposes the flattened P0 markers below. TrollStore task `60` exposes
the same facts in `capabilities`; rootfull task `60` exposes them in `vpn`.

Common markers:

```text
vpnContractVersion=1
vpnLegacyTask=59
vpnProfileScope=tlink_owned_only
vpnConfigurationTransport=local_ui_keychain_only
vpnCredentialsOverTask59=forbidden
```

Rootfull markers:

```text
vpnState=unavailable
vpnQuery=unsupported
vpnControl=unsupported
vpnBackend=stub
vpnBroker=not_implemented
```

TrollStore markers:

```text
vpnState=query_only
vpnQuery=interface_probe
vpnControl=unsupported
vpnBackend=interface_probe
vpnBroker=not_implemented
```

## Security and ownership boundary

Task `59` may select or control only a profile created and identified by
TLinkauto. VPN server addresses, usernames, passwords, shared secrets,
certificates, private keys, and provider configuration must never be accepted
or returned through task `59`, task `60`, task `97`, logs, or exported
diagnostics.

Configuration belongs to foreground UI. Secret material belongs in Keychain
with the narrowest practical accessibility and access group. The broker
receives only a non-secret profile identifier and the requested state. Task
`59` remains covered by the existing `automation` license gate.

## P1 hand-off

VPN P1 may start only after this gate passes. It should add a shared status
model and entitlement probe without changing the legacy request bytes. The
first production backend should use a TLink-managed IKEv2/IPsec profile via
`NEVPNManager`; the packet-tunnel POC is not the default backend.

P1 must keep these invariants:

1. No credentials or raw profile configuration on port `6000`.
2. Only the TLink-owned profile may be mutated.
3. Query remains backward-compatible with a single `0`/`1` field.
4. Connect/disconnect success is emitted only after observing the terminal
   state.
5. Capability state changes from P0 values only when device evidence proves
   the entitlement and broker path for that runtime.

Run the P0 sanity gate with:

```text
node scripts/check-vpn-p0-baseline.mjs
```
