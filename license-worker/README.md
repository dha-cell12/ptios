# TLinkauto License Worker

Cloudflare Worker MVP for issuing signed, device-bound license leases.

## Setup

```bash
cd license-worker
npm install
npx wrangler d1 create tlinkauto-license
```

Copy the returned database id into `wrangler.jsonc`, then initialize D1:

```bash
npm run db:init:remote
```

Keep the D1 binding name as `DB`. The Worker also accepts the legacy
`tlinkauto_license` binding for recovery, but new deployments and CI validate
`DB` so an authenticated admin request cannot fail only when it first reaches
the database.

Generate a P-256 signing key:

```bash
npm run keys
```

Set the printed private JWK and an admin token as Worker secrets:

```bash
npx wrangler secret put LICENSE_SIGNING_PRIVATE_JWK
npx wrangler secret put ADMIN_TOKEN
```

After deployment, open the administration dashboard at:

```text
https://YOUR-WORKER/admin
```

Enter the same `ADMIN_TOKEN` secret when prompted. The dashboard keeps the
token in page memory only; it does not write it to cookies, `localStorage`, or
`sessionStorage`. Use the **Lock** action before leaving a shared browser.
Always access the dashboard over HTTPS.

The dashboard can:

- list and filter licenses with active, revoked, and expired totals;
- create a license and show its clear key once;
- edit the fixed license expiration, feature set, status, and device limit;
- inspect device bindings and revoke one binding;
- reset all active device slots or revoke the complete license.

The clear license key cannot be recovered from D1. Only its SHA-256 hash is
stored, so record the key when the create dialog returns it.

Copy the printed public `x` and `y` values into
`stream-app/app/LicenseConfig.plist`, set `LicenseEndpoint`, and deploy:

```bash
npm run deploy
```

Create a test license:

```bash
curl -X POST "https://YOUR-WORKER/v1/admin/licenses" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"license_key":"TLINK-TEST-0001","max_devices":1,"features":["automation","stream","script","admin","shell"]}'
```

Keep `LicenseEnforcementEnabled` false during initial device validation. After
activation, task `75` should report a valid signed lease. Enable enforcement
only after activation, refresh, expiry, and recovery tests pass.

Lease refresh requires a fresh signature from the device private key. Copying
only `lease.json` and `device_public_key.bin` to another device cannot refresh
or pass the local private-key possession check.

If an erase/restore creates a new device key and the license has reached its
device limit, reset the old device registrations with the admin endpoint:

```bash
curl -X POST "https://YOUR-WORKER/v1/admin/reset-devices" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"license_key":"TLINK-TEST-0001"}'
```

The GitHub workflow `license-worker.yml` validates every change. Its manual
deploy job expects the `tlinkauto-license` environment secrets
`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`,
`LICENSE_SIGNING_PRIVATE_JWK`, and `TLINK_LICENSE_ADMIN_TOKEN`.

## Lifecycle v1

Every issued lease includes `license_contract_version: 1`. Lifecycle endpoints
return JSON as `{ "ok": true, ... }` on success and
`{ "ok": false, "error": "<stable_code>" }` on failure.

- `POST /v1/challenge`: create a five-minute, one-time activation challenge.
- `POST /v1/activate`: consume the challenge and issue a device-bound lease.
- `POST /v1/refresh`: require the signed lease plus a fresh device signature.
- `POST /v1/deactivate`: require the same proof and release this device slot.
- `GET /v1/admin/licenses`: list licenses and aggregate status/device totals.
- `GET /v1/admin/license?id=...`: inspect one license and its device bindings.
- `POST /v1/admin/update`: update `status`, `max_devices`, `expires_at`, or
  `features` without editing D1 manually. Admin mutations accept either
  `license_id` or the clear `license_key`.
- `POST /v1/admin/revoke`: revoke the license.
- `POST /v1/admin/reset-devices`: revoke active devices and clear challenges;
  the same proven device key may activate again afterward.
- `POST /v1/admin/revoke-device`: revoke one device binding by `license_id`
  and `device_id`.

Example deactivate body:

```json
{
  "lease": { "version": 1, "key_id": "...", "payload": "...", "signature": "..." },
  "device_signature": "DER_ECDSA_SIGNATURE_BASE64URL"
}
```

Example admin update:

```bash
curl -X POST "https://YOUR-WORKER/v1/admin/update" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"license_key":"TLINK-TEST-0001","max_devices":2,"features":["automation","stream","script"]}'
```

Run the isolated lifecycle suite and task-policy check before deployment:

```bash
npm test
node ../scripts/check-license-task-policy.mjs
```
