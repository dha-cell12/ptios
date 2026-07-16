const encoder = new TextEncoder();
const decoder = new TextDecoder();

function jsonResponse(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "access-control-allow-origin": "*",
      "access-control-allow-headers": "authorization, content-type",
      "access-control-allow-methods": "GET, POST, OPTIONS",
    },
  });
}

function base64UrlEncode(input) {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64UrlDecode(value) {
  const normalized = String(value || "").replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function randomToken(bytes = 32) {
  const value = new Uint8Array(bytes);
  crypto.getRandomValues(value);
  return base64UrlEncode(value);
}

async function sha256Base64Url(value) {
  const bytes = typeof value === "string" ? encoder.encode(value) : value;
  return base64UrlEncode(await crypto.subtle.digest("SHA-256", bytes));
}

function normalizeLicenseKey(value) {
  return String(value || "").trim().toUpperCase().replace(/\s+/g, "");
}

function trimInteger(bytes) {
  let start = 0;
  while (start < bytes.length - 1 && bytes[start] === 0) start++;
  let out = bytes.slice(start);
  if (out[0] & 0x80) {
    const prefixed = new Uint8Array(out.length + 1);
    prefixed.set(out, 1);
    out = prefixed;
  }
  return out;
}

function rawSignatureToDer(rawValue) {
  const raw = new Uint8Array(rawValue);
  if (raw.length !== 64) throw new Error("invalid_raw_ecdsa_signature");
  const r = trimInteger(raw.slice(0, 32));
  const s = trimInteger(raw.slice(32, 64));
  const bodyLength = 2 + r.length + 2 + s.length;
  const der = new Uint8Array(2 + bodyLength);
  let offset = 0;
  der[offset++] = 0x30;
  der[offset++] = bodyLength;
  der[offset++] = 0x02;
  der[offset++] = r.length;
  der.set(r, offset);
  offset += r.length;
  der[offset++] = 0x02;
  der[offset++] = s.length;
  der.set(s, offset);
  return der;
}

function derSignatureToRaw(derValue) {
  const der = new Uint8Array(derValue);
  if (der.length < 8 || der[0] !== 0x30 || der[1] !== der.length - 2) {
    throw new Error("invalid_der_ecdsa_signature");
  }
  let offset = 2;
  if (der[offset++] !== 0x02) throw new Error("invalid_der_r");
  const rLength = der[offset++];
  let r = der.slice(offset, offset + rLength);
  offset += rLength;
  if (der[offset++] !== 0x02) throw new Error("invalid_der_s");
  const sLength = der[offset++];
  let s = der.slice(offset, offset + sLength);
  if (r.length === 33 && r[0] === 0) r = r.slice(1);
  if (s.length === 33 && s[0] === 0) s = s.slice(1);
  if (r.length > 32 || s.length > 32) throw new Error("invalid_der_component_size");
  const raw = new Uint8Array(64);
  raw.set(r, 32 - r.length);
  raw.set(s, 64 - s.length);
  return raw;
}

function validatePublicJwk(value) {
  if (!value || value.kty !== "EC" || value.crv !== "P-256") throw new Error("invalid_device_public_key");
  const x = base64UrlDecode(value.x);
  const y = base64UrlDecode(value.y);
  if (x.length !== 32 || y.length !== 32) throw new Error("invalid_device_public_key_size");
  return { kty: "EC", crv: "P-256", x: value.x, y: value.y, ext: true };
}

async function deviceKeyHash(publicJwk) {
  const jwk = validatePublicJwk(publicJwk);
  const point = new Uint8Array(65);
  point[0] = 0x04;
  point.set(base64UrlDecode(jwk.x), 1);
  point.set(base64UrlDecode(jwk.y), 33);
  return sha256Base64Url(point);
}

async function signingKeys(env) {
  const privateJwk = JSON.parse(env.LICENSE_SIGNING_PRIVATE_JWK);
  const publicJwk = { ...privateJwk };
  delete publicJwk.d;
  publicJwk.key_ops = ["verify"];
  const privateKey = await crypto.subtle.importKey(
    "jwk",
    privateJwk,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const publicKey = await crypto.subtle.importKey(
    "jwk",
    publicJwk,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  return { privateKey, publicKey, publicJwk };
}

async function signPayload(env, payload) {
  const payloadBytes = encoder.encode(JSON.stringify(payload));
  const { privateKey } = await signingKeys(env);
  const rawSignature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    payloadBytes,
  );
  return {
    version: 1,
    key_id: env.LICENSE_KEY_ID || "tlinkauto-test-2026-01",
    payload: base64UrlEncode(payloadBytes),
    signature: base64UrlEncode(rawSignatureToDer(rawSignature)),
  };
}

async function verifyLease(env, lease) {
  if (!lease || lease.version !== 1 || !lease.payload || !lease.signature) throw new Error("invalid_lease");
  const payloadBytes = base64UrlDecode(lease.payload);
  const signatureRaw = derSignatureToRaw(base64UrlDecode(lease.signature));
  const { publicKey } = await signingKeys(env);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    signatureRaw,
    payloadBytes,
  );
  if (!valid) throw new Error("invalid_lease_signature");
  return JSON.parse(decoder.decode(payloadBytes));
}

async function readJson(request) {
  try {
    return await request.json();
  } catch {
    throw new Error("invalid_json");
  }
}

async function loadLicense(env, normalizedKey) {
  const keyHash = await sha256Base64Url(encoder.encode(normalizedKey));
  return env.DB.prepare("SELECT * FROM licenses WHERE key_hash = ?").bind(keyHash).first();
}

function licenseUsable(license, now) {
  return license && license.status === "active" && (!license.expires_at || license.expires_at > now);
}

async function issueLease(env, license, device) {
  const now = Math.floor(Date.now() / 1000);
  const leaseSeconds = Math.max(300, Number(env.LEASE_SECONDS || 86400));
  const graceSeconds = Math.max(leaseSeconds, Number(env.OFFLINE_GRACE_SECONDS || 259200));
  return signPayload(env, {
    version: 1,
    product: "tlinkauto",
    token_id: crypto.randomUUID(),
    license_id: license.id,
    device_id: device.id,
    device_key_hash: device.device_key_hash,
    issued_at: now,
    not_before: now - 30,
    expires_at: now + leaseSeconds,
    offline_until: now + graceSeconds,
    features: JSON.parse(license.features_json || "[]"),
  });
}

async function handleChallenge(request, env) {
  const body = await readJson(request);
  const key = normalizeLicenseKey(body.license_key);
  const publicJwk = validatePublicJwk(body.device_public_key);
  if (!key) return jsonResponse({ ok: false, error: "invalid_license" }, 403);
  const license = await loadLicense(env, key);
  const now = Math.floor(Date.now() / 1000);
  if (!licenseUsable(license, now)) return jsonResponse({ ok: false, error: "invalid_license" }, 403);

  const id = crypto.randomUUID();
  const challenge = randomToken(32);
  const keyHash = await deviceKeyHash(publicJwk);
  await env.DB.prepare(
    "INSERT INTO activation_challenges (id, license_id, device_key_hash, challenge, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)",
  ).bind(id, license.id, keyHash, challenge, now + 300, now).run();
  return jsonResponse({ ok: true, challenge_id: id, challenge, expires_at: now + 300 });
}

async function handleActivate(request, env) {
  const body = await readJson(request);
  const key = normalizeLicenseKey(body.license_key);
  const publicJwk = validatePublicJwk(body.device_public_key);
  const deviceHash = await deviceKeyHash(publicJwk);
  const license = await loadLicense(env, key);
  const now = Math.floor(Date.now() / 1000);
  if (!licenseUsable(license, now)) return jsonResponse({ ok: false, error: "invalid_license" }, 403);

  const challengeRow = await env.DB.prepare(
    "SELECT * FROM activation_challenges WHERE id = ? AND license_id = ?",
  ).bind(body.challenge_id || "", license.id).first();
  if (!challengeRow || challengeRow.expires_at < now || challengeRow.device_key_hash !== deviceHash) {
    return jsonResponse({ ok: false, error: "invalid_or_expired_challenge" }, 403);
  }

  const deviceKey = await crypto.subtle.importKey(
    "jwk",
    publicJwk,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  let signatureRaw;
  try {
    signatureRaw = derSignatureToRaw(base64UrlDecode(body.signature || ""));
  } catch {
    return jsonResponse({ ok: false, error: "invalid_device_signature" }, 403);
  }
  const proofValid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    deviceKey,
    signatureRaw,
    encoder.encode(challengeRow.challenge),
  );
  if (!proofValid) return jsonResponse({ ok: false, error: "invalid_device_signature" }, 403);

  await env.DB.prepare("DELETE FROM activation_challenges WHERE id = ?").bind(challengeRow.id).run();
  let device = await env.DB.prepare(
    "SELECT * FROM devices WHERE license_id = ? AND device_key_hash = ?",
  ).bind(license.id, deviceHash).first();
  if (!device) {
    const countRow = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM devices WHERE license_id = ? AND status = 'active'",
    ).bind(license.id).first();
    if (Number(countRow?.count || 0) >= Number(license.max_devices || 1)) {
      return jsonResponse({ ok: false, error: "device_limit_reached" }, 409);
    }
    const deviceId = crypto.randomUUID();
    await env.DB.prepare(
      "INSERT INTO devices (id, license_id, device_key_hash, public_jwk, status, created_at, last_seen_at) VALUES (?, ?, ?, ?, 'active', ?, ?)",
    ).bind(deviceId, license.id, deviceHash, JSON.stringify(publicJwk), now, now).run();
    device = await env.DB.prepare("SELECT * FROM devices WHERE id = ?").bind(deviceId).first();
  } else {
    if (device.status !== "active") return jsonResponse({ ok: false, error: "device_revoked" }, 403);
    await env.DB.prepare("UPDATE devices SET last_seen_at = ? WHERE id = ?").bind(now, device.id).run();
  }

  const lease = await issueLease(env, license, device);
  return jsonResponse({ ok: true, lease });
}

async function handleRefresh(request, env) {
  const body = await readJson(request);
  let payload;
  try {
    payload = await verifyLease(env, body.lease);
  } catch (error) {
    return jsonResponse({ ok: false, error: error.message || "invalid_lease" }, 403);
  }
  const now = Math.floor(Date.now() / 1000);
  const license = await env.DB.prepare("SELECT * FROM licenses WHERE id = ?").bind(payload.license_id || "").first();
  const device = await env.DB.prepare("SELECT * FROM devices WHERE id = ?").bind(payload.device_id || "").first();
  if (!licenseUsable(license, now)) return jsonResponse({ ok: false, error: "license_revoked_or_expired" }, 403);
  if (!device || device.status !== "active" || device.device_key_hash !== payload.device_key_hash) {
    return jsonResponse({ ok: false, error: "device_revoked" }, 403);
  }
  const publicJwk = validatePublicJwk(JSON.parse(device.public_jwk || "{}"));
  const deviceKey = await crypto.subtle.importKey(
    "jwk",
    publicJwk,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  let signatureRaw;
  try {
    signatureRaw = derSignatureToRaw(base64UrlDecode(body.device_signature || ""));
  } catch {
    return jsonResponse({ ok: false, error: "invalid_device_signature" }, 403);
  }
  const proofValid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    deviceKey,
    signatureRaw,
    encoder.encode(body.lease.payload),
  );
  if (!proofValid) return jsonResponse({ ok: false, error: "invalid_device_signature" }, 403);
  await env.DB.prepare("UPDATE devices SET last_seen_at = ? WHERE id = ?").bind(now, device.id).run();
  return jsonResponse({ ok: true, lease: await issueLease(env, license, device) });
}

function requireAdmin(request, env) {
  const value = request.headers.get("authorization") || "";
  return env.ADMIN_TOKEN && value === `Bearer ${env.ADMIN_TOKEN}`;
}

async function handleAdminCreateLicense(request, env) {
  if (!requireAdmin(request, env)) return jsonResponse({ ok: false, error: "unauthorized" }, 401);
  const body = await readJson(request);
  const key = normalizeLicenseKey(body.license_key);
  if (key.length < 8) return jsonResponse({ ok: false, error: "license_key_too_short" }, 400);
  const now = Math.floor(Date.now() / 1000);
  const id = body.id || crypto.randomUUID();
  const keyHash = await sha256Base64Url(encoder.encode(key));
  const features = Array.isArray(body.features)
    ? body.features
    : ["automation", "stream", "script", "admin", "shell"];
  await env.DB.prepare(
    "INSERT INTO licenses (id, key_hash, status, max_devices, features_json, expires_at, created_at, updated_at) VALUES (?, ?, 'active', ?, ?, ?, ?, ?)",
  ).bind(
    id,
    keyHash,
    Math.max(1, Number(body.max_devices || 1)),
    JSON.stringify(features),
    Math.max(0, Number(body.expires_at || 0)),
    now,
    now,
  ).run();
  return jsonResponse({ ok: true, id, license_key: key });
}

async function handleAdminRevoke(request, env) {
  if (!requireAdmin(request, env)) return jsonResponse({ ok: false, error: "unauthorized" }, 401);
  const body = await readJson(request);
  const key = normalizeLicenseKey(body.license_key);
  const license = await loadLicense(env, key);
  if (!license) return jsonResponse({ ok: false, error: "not_found" }, 404);
  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare("UPDATE licenses SET status = 'revoked', updated_at = ? WHERE id = ?").bind(now, license.id).run();
  return jsonResponse({ ok: true, id: license.id, status: "revoked" });
}

async function handleAdminResetDevices(request, env) {
  if (!requireAdmin(request, env)) return jsonResponse({ ok: false, error: "unauthorized" }, 401);
  const body = await readJson(request);
  const key = normalizeLicenseKey(body.license_key);
  const license = await loadLicense(env, key);
  if (!license) return jsonResponse({ ok: false, error: "not_found" }, 404);
  const now = Math.floor(Date.now() / 1000);
  const result = await env.DB.prepare(
    "UPDATE devices SET status = 'revoked', last_seen_at = ? WHERE license_id = ? AND status = 'active'",
  ).bind(now, license.id).run();
  return jsonResponse({
    ok: true,
    id: license.id,
    reset_devices: Number(result.meta?.changes || 0),
  });
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return jsonResponse({ ok: true });
    const url = new URL(request.url);
    try {
      if (request.method === "GET" && url.pathname === "/v1/health") {
        return jsonResponse({ ok: true, service: "tlinkauto-license", now: Math.floor(Date.now() / 1000) });
      }
      if (request.method === "GET" && url.pathname === "/v1/public-key") {
        const { publicJwk } = await signingKeys(env);
        return jsonResponse({
          ok: true,
          key_id: env.LICENSE_KEY_ID || "tlinkauto-test-2026-01",
          public_key: publicJwk,
        });
      }
      if (request.method === "POST" && url.pathname === "/v1/challenge") return handleChallenge(request, env);
      if (request.method === "POST" && url.pathname === "/v1/activate") return handleActivate(request, env);
      if (request.method === "POST" && url.pathname === "/v1/refresh") return handleRefresh(request, env);
      if (request.method === "POST" && url.pathname === "/v1/admin/licenses") return handleAdminCreateLicense(request, env);
      if (request.method === "POST" && url.pathname === "/v1/admin/revoke") return handleAdminRevoke(request, env);
      if (request.method === "POST" && url.pathname === "/v1/admin/reset-devices") return handleAdminResetDevices(request, env);
      return jsonResponse({ ok: false, error: "not_found" }, 404);
    } catch (error) {
      console.error(error);
      return jsonResponse({ ok: false, error: error.message || "internal_error" }, 500);
    }
  },
};
