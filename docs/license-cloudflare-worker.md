# TLinkauto Cloudflare License MVP

Security architecture, threat model, hardening backlog, and OLLVM protection
targets are documented separately in
[`license-security-design.md`](license-security-design.md).

## Architecture

- `StreamControl.app` creates a P-256 device key. Secure Enclave is preferred;
  a `ThisDeviceOnly` Keychain key is the fallback.
- The app proves possession of that key to the Cloudflare Worker during
  activation.
- The Worker stores only a hash of the normalized license key, registers the
  device public key, and returns a short signed lease plus an offline grace
  deadline.
- `streamd`, H264 servers, `clipboardd`, foreground app bridges, and
  `privhelper` verify the Worker signature, product/version, lease dates,
  feature list, public-key hash, and local private-key possession.
- Refresh requests are also signed by the device key. Copying the lease and
  public-key file to another device is insufficient.

This raises the cost of casual copying and server emulation. It cannot make a
client binary impossible to patch, so enforcement is deliberately repeated in
multiple processes and sensitive business decisions remain server-side.

## Cloudflare Setup

```bash
cd license-worker
npm install
npx wrangler d1 create tlinkauto-license
```

Put the returned D1 database id in `license-worker/wrangler.jsonc`, then:

```bash
npm run db:init:remote
npm run keys
npx wrangler secret put LICENSE_SIGNING_PRIVATE_JWK
npx wrangler secret put ADMIN_TOKEN
npm run deploy
```

Only the public P-256 `x` and `y` values belong in the app. Never put the
private signing JWK or admin token in the repository, app bundle, GitHub
variables, task responses, or diagnostic exports.

## GitHub Build Variables

The StreamControl workflow accepts these repository variables:

- `TLINK_LICENSE_ENDPOINT`
- `TLINK_LICENSE_KEY_ID`
- `TLINK_LICENSE_PUBLIC_KEY_X`
- `TLINK_LICENSE_PUBLIC_KEY_Y`
- `TLINK_LICENSE_ENFORCEMENT`

Use `false` for the first device test. When set to `true`, the workflow also
compiles `streamd`, `clipboardd`, `privhelper`, and the app with forced
enforcement, so
editing `LicenseConfig.plist` alone cannot switch the release back to observe
mode.

The manual `license-worker.yml` deploy job uses the protected GitHub
environment `tlinkauto-license` and these secrets:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`
- `LICENSE_SIGNING_PRIVATE_JWK`
- `TLINK_LICENSE_ADMIN_TOKEN`

## Rollout

1. Deploy the Worker and create a one-device test license.
2. Build with `TLINK_LICENSE_ENFORCEMENT=false`.
3. Open `Settings > License`, activate, and refresh.
4. Verify task `75` from the app, `streamd`, and after a streamd restart.
5. Test expiry/offline grace by temporarily shortening Worker lease values.
6. Test H264 and admin denial after removing the local lease.
7. Only then build with `TLINK_LICENSE_ENFORCEMENT=true`.

## Manual Diagnostics

```powershell
$raw = Invoke-TLinkTask -HostIP $iphoneIP -Task "75"
$b64 = ($raw -replace '^0;;', '').Trim()
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) |
  ConvertFrom-Json |
  Format-List

# Force a fresh check in streamd.
Invoke-TLinkTask -HostIP $iphoneIP -Task "76"
```

Expected for an activated device:

- `state=valid` or `offline_grace`
- `licensed=true`
- `device_key_proof=true`
- `effective_access=true`

Task `60` includes the same object under `license`. Task `97` includes the
short `license`, `licenseState`, and `licenseAccess` fields.

## Device Reset And iOS Upgrade

- Normal iOS upgrades should keep a `ThisDeviceOnly` Keychain/Secure Enclave
  key, but the app must still be tested on the target OS.
- Erase/restore or hardware replacement creates a new key. Revoke/reset the
  old device registrations through `/v1/admin/reset-devices`, then activate
  again.
- Do not bind directly to mutable values such as OS version, device name, or
  IP address.

## Deferred Hardening

- Certificate pinning is deferred during the Cloudflare test phase because
  managed edge certificates can rotate. Signed leases already prevent a
  network intermediary from minting valid access.
- Before production, use a stable custom hostname and evaluate public-key
  pinning with a backup pin and a remote rotation plan.
- Add server-side rate limits, audit events, activation anomaly detection, and
  key rotation before commercial rollout.
- Rootfull runtime enforcement remains a separate rollout. The shared
  verifier is reusable, but the old rootfull daemon and app still need their
  own config packaging, activation UI, and task gate validation.
