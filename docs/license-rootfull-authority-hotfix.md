# Rootfull License Authority Hotfix

## Incident

An enforced rootfull package could show a valid license in the foreground app
while task `75` returned:

```text
state=device_mismatch
error=license_device_private_key_unavailable
device_key_proof=false
```

The lease, server signature, public-key hash, release integrity, features, and
expiry were valid. The foreground app could read its private key, but
`tlinkautod` and the SpringBoard-hosted tweak could not read an item owned by
the app's Keychain access group. Re-activating or allocating another server
device does not repair this process-entitlement mismatch.

An admin token was also pasted into a diagnostic conversation during this
incident. Treat any disclosed token as compromised: rotate the Worker
`ADMIN_TOKEN`, update the protected GitHub
`TLINK_LICENSE_ADMIN_TOKEN` secret, and never place either value in source,
artifacts, task responses, or logs.

## Architecture

The hotfix installs `/usr/libexec/tlinkauto-licensed` as a mobile
LaunchDaemon. It is the only new rootfull executable that receives the app's
`com.tlinkauto.tlinkauto` Keychain access group. It deliberately receives no
VPN or Network Extension entitlement.

Clients use:

```text
/var/mobile/Library/TLinkauto/run/license-authority.sock
```

For every status refresh:

1. the client generates a random 32-byte nonce;
2. the authority verifies the lease and private-key possession locally;
3. the authority returns status, nonce, issue time, and a 10-second expiry;
4. the authority signs those exact JSON bytes using the device P-256 key;
5. the client independently verifies the server signature on `lease.json` and
   anchors `device_public_key.bin` to the signed `device_key_hash`;
6. the client verifies the authority signature, matches the nonce, and
   enforces a maximum 15-second proof lifetime.

The status contains no license key, admin token, private key, VPN password, or
lease signature. A missing socket, malformed response, nonce mismatch,
expired proof, or invalid signature fails closed.

`tlinkautod`, `tlinkautob`, `pccontrol`, `tlinkauto-jsd`, and
`tlinkauto-vpnd` compile in authority-client mode. The foreground app and
the authority retain direct verification because they are the processes
authorized to use the Keychain item.

## Package validation

The Phase 6 artifact validator now requires:

- `tlinkauto-licensed` in the package with the correct observe/enforced
  compile markers;
- the exact Keychain access group on the authority's signed entitlements;
- no VPN entitlement on the authority;
- the signed authority client in every rootfull runtime verifier;
- the authority LaunchDaemon to load before `tlinkautod`.

## Device validation

Install the rebuilt enforced package, unlock the device once, and open
TLinkauto. Do not remove the existing valid lease or create another license.

```powershell
$daemonRaw = Invoke-TLinkTask -HostIP $iphoneIP -Task "75"
$daemonB64 = ($daemonRaw -split ";;", 2)[1].Trim()
$daemon = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($daemonB64)
) | ConvertFrom-Json

$springRaw = Invoke-TLinkTask -HostIP $iphoneIP -Task "60"
$springB64 = ($springRaw -split ";;", 2)[1].Trim()
$spring = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($springB64)
) | ConvertFrom-Json

$daemon | Select-Object state,licensed,effective_access,device_key_proof,
    authority_contract_version,authority_proof,error
$spring.license | Select-Object state,licensed,effective_access,
    device_key_proof,authority_contract_version,authority_proof,error
```

Expected after activation:

```text
state=valid
licensed=true
effective_access=true
device_key_proof=true
authority_contract_version=1
authority_proof=true
error=
```

Then run the existing Phase 6 regression and test VPN/script:

```powershell
./scripts/Test-TLinkRootfullLicensePhase6.ps1 `
  -HostIP $iphoneIP `
  -ExpectedMode enforced `
  -ExpectedState valid `
  -RunSafeFeatureProbes

Invoke-TLinkTask -HostIP $iphoneIP -Task "590"
Invoke-TLinkTask -HostIP $iphoneIP -Task "591;;1"
Invoke-TLinkTask -HostIP $iphoneIP -Task "591;;0"
```

If the authority is unavailable, inspect:

```text
/var/mobile/Library/TLinkauto/license-authority-launchctl.log
/var/mobile/Library/TLinkauto/license-authority.log
/var/mobile/Library/TLinkauto/license-authority.err.log
```
