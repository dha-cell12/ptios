const encoder = new TextEncoder();
const decoder = new TextDecoder();

const LICENSE_CONTRACT_VERSION = 1;
const MAX_BODY_BYTES = 16 * 1024;
const MAX_LICENSE_KEY_LENGTH = 128;
const ALLOWED_FEATURES = new Set(["automation", "stream", "script", "admin", "shell"]);
const DEFAULT_FEATURES = ["automation", "stream", "script", "admin", "shell"];

class RequestError extends Error {
  constructor(status, code) {
    super(code);
    this.name = "RequestError";
    this.status = status;
    this.code = code;
  }
}

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

function errorResponse(code, status, details = {}) {
  return jsonResponse({ ok: false, error: code, ...details }, status);
}

function base64UrlEncode(input) {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64UrlDecode(value) {
  if (typeof value !== "string" || value.length === 0 || value.length > 4096 || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new Error("invalid_base64url");
  }
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
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
  if (typeof value !== "string") return "";
  return value.trim().toUpperCase().replace(/\s+/g, "");
}

function validatedLicenseKey(value) {
  const key = normalizeLicenseKey(value);
  if (key.length < 8 || key.length > MAX_LICENSE_KEY_LENGTH || !/^[A-Z0-9_-]+$/.test(key)) {
    throw new RequestError(400, "invalid_license_key_format");
  }
  return key;
}

function validatedIdentifier(value) {
  if (value === undefined || value === null || value === "") return crypto.randomUUID();
  if (typeof value !== "string" || value.length > 64 || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new RequestError(400, "invalid_license_id");
  }
  return value;
}

function validatedInteger(value, name, minimum, maximum, fallback) {
  if (value === undefined || value === null || value === "") return fallback;
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < minimum || number > maximum) {
    throw new RequestError(400, `invalid_${name}`);
  }
  return number;
}

function validatedFeatures(value, fallback = DEFAULT_FEATURES) {
  const features = value === undefined ? fallback : value;
  if (!Array.isArray(features) || features.length === 0 || features.length > ALLOWED_FEATURES.size) {
    throw new RequestError(400, "invalid_features");
  }
  const normalized = [];
  for (const feature of features) {
    if (typeof feature !== "string" || !ALLOWED_FEATURES.has(feature) || normalized.includes(feature)) {
      throw new RequestError(400, "invalid_features");
    }
    normalized.push(feature);
  }
  return normalized;
}

function validatedStatus(value, fallback = "active") {
  const status = value === undefined ? fallback : value;
  if (status !== "active" && status !== "revoked") throw new RequestError(400, "invalid_status");
  return status;
}

function database(env) {
  const binding = env.DB || env.tlinkauto_license;
  if (!binding || typeof binding.prepare !== "function") {
    throw new Error("d1_binding_missing expected=DB legacy=tlinkauto_license");
  }
  return binding;
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
  if (rLength < 1 || rLength > 33 || offset + rLength > der.length) throw new Error("invalid_der_r_length");
  let r = der.slice(offset, offset + rLength);
  offset += rLength;
  if (der[offset++] !== 0x02) throw new Error("invalid_der_s");
  const sLength = der[offset++];
  if (sLength < 1 || sLength > 33 || offset + sLength !== der.length) throw new Error("invalid_der_s_length");
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
  if (!value || typeof value !== "object" || value.kty !== "EC" || value.crv !== "P-256") {
    throw new RequestError(400, "invalid_device_public_key");
  }
  let x;
  let y;
  try {
    x = base64UrlDecode(value.x);
    y = base64UrlDecode(value.y);
  } catch {
    throw new RequestError(400, "invalid_device_public_key");
  }
  if (x.length !== 32 || y.length !== 32) throw new RequestError(400, "invalid_device_public_key_size");
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
  let privateJwk;
  try {
    privateJwk = JSON.parse(env.LICENSE_SIGNING_PRIVATE_JWK || "");
  } catch {
    throw new Error("license_signing_key_invalid");
  }
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

function validateLeasePayload(payload) {
  const contractVersion = payload?.license_contract_version ?? 1;
  if (!payload || payload.version !== 1 || payload.product !== "tlinkauto" || contractVersion !== LICENSE_CONTRACT_VERSION) {
    throw new Error("invalid_lease_contract");
  }
  if (typeof payload.license_id !== "string" || typeof payload.device_id !== "string" ||
      typeof payload.device_key_hash !== "string" || !Array.isArray(payload.features)) {
    throw new Error("invalid_lease_payload");
  }
  validatedFeatures(payload.features);
  return { ...payload, license_contract_version: contractVersion };
}

async function verifyLease(env, lease) {
  const expectedKeyId = env.LICENSE_KEY_ID || "tlinkauto-test-2026-01";
  if (!lease || lease.version !== 1 || lease.key_id !== expectedKeyId || !lease.payload || !lease.signature) {
    throw new Error("invalid_lease");
  }
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
  return validateLeasePayload(JSON.parse(decoder.decode(payloadBytes)));
}

async function readJson(request) {
  const declaredLength = Number(request.headers.get("content-length") || 0);
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    throw new RequestError(413, "request_body_too_large");
  }
  const text = await request.text();
  if (encoder.encode(text).length > MAX_BODY_BYTES) throw new RequestError(413, "request_body_too_large");
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    throw new RequestError(400, "invalid_json");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new RequestError(400, "invalid_json_object");
  return value;
}

async function loadLicense(env, normalizedKey) {
  const keyHash = await sha256Base64Url(encoder.encode(normalizedKey));
  return database(env).prepare("SELECT * FROM licenses WHERE key_hash = ?").bind(keyHash).first();
}

function licenseUsable(license, now) {
  return license && license.status === "active" && (!license.expires_at || license.expires_at > now);
}

function featuresFromLicense(license) {
  let features;
  try {
    features = JSON.parse(license.features_json || "[]");
  } catch {
    throw new Error("stored_license_features_invalid");
  }
  return validatedFeatures(features);
}

async function issueLease(env, license, device) {
  const now = Math.floor(Date.now() / 1000);
  const leaseSeconds = Math.max(300, Number(env.LEASE_SECONDS || 86400));
  const graceSeconds = Math.max(leaseSeconds, Number(env.OFFLINE_GRACE_SECONDS || 259200));
  return signPayload(env, {
    version: 1,
    license_contract_version: LICENSE_CONTRACT_VERSION,
    product: "tlinkauto",
    token_id: crypto.randomUUID(),
    license_id: license.id,
    device_id: device.id,
    device_key_hash: device.device_key_hash,
    issued_at: now,
    not_before: now - 30,
    expires_at: now + leaseSeconds,
    offline_until: now + graceSeconds,
    features: featuresFromLicense(license),
  });
}

async function cleanupExpiredChallenges(env, now) {
  await database(env).prepare("DELETE FROM activation_challenges WHERE expires_at < ?").bind(now).run();
}

async function handleChallenge(request, env) {
  const body = await readJson(request);
  const key = validatedLicenseKey(body.license_key);
  const publicJwk = validatePublicJwk(body.device_public_key);
  const license = await loadLicense(env, key);
  const now = Math.floor(Date.now() / 1000);
  if (!licenseUsable(license, now)) return errorResponse("invalid_license", 403);

  await cleanupExpiredChallenges(env, now);
  const id = crypto.randomUUID();
  const challenge = randomToken(32);
  const keyHash = await deviceKeyHash(publicJwk);
  await database(env).prepare(
    "INSERT INTO activation_challenges (id, license_id, device_key_hash, challenge, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)",
  ).bind(id, license.id, keyHash, challenge, now + 300, now).run();
  return jsonResponse({ ok: true, license_contract_version: LICENSE_CONTRACT_VERSION, challenge_id: id, challenge, expires_at: now + 300 });
}

async function verifyDeviceSignature(publicJwk, signature, message) {
  let signatureRaw;
  try {
    signatureRaw = derSignatureToRaw(base64UrlDecode(signature));
  } catch {
    return false;
  }
  const deviceKey = await crypto.subtle.importKey(
    "jwk",
    publicJwk,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  return crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    deviceKey,
    signatureRaw,
    encoder.encode(message),
  );
}

async function activeDeviceCount(env, licenseId) {
  const row = await database(env).prepare(
    "SELECT COUNT(*) AS count FROM devices WHERE license_id = ? AND status = 'active'",
  ).bind(licenseId).first();
  return Number(row?.count || 0);
}

async function handleActivate(request, env) {
  const body = await readJson(request);
  const key = validatedLicenseKey(body.license_key);
  const publicJwk = validatePublicJwk(body.device_public_key);
  const challengeId = typeof body.challenge_id === "string" && body.challenge_id.length <= 64 ? body.challenge_id : "";
  const signature = typeof body.signature === "string" && body.signature.length <= 512 ? body.signature : "";
  if (!challengeId || !signature) throw new RequestError(400, "invalid_activation_request");

  const deviceHash = await deviceKeyHash(publicJwk);
  const license = await loadLicense(env, key);
  const now = Math.floor(Date.now() / 1000);
  if (!licenseUsable(license, now)) return errorResponse("invalid_license", 403);
  await cleanupExpiredChallenges(env, now);

  const challengeRow = await database(env).prepare(
    "SELECT * FROM activation_challenges WHERE id = ? AND license_id = ?",
  ).bind(challengeId, license.id).first();
  if (!challengeRow || challengeRow.expires_at < now || challengeRow.device_key_hash !== deviceHash) {
    return errorResponse("invalid_or_expired_challenge", 403);
  }

  const proofValid = await verifyDeviceSignature(publicJwk, signature, challengeRow.challenge);
  if (!proofValid) return errorResponse("invalid_device_signature", 403);

  const consume = await database(env).prepare(
    "DELETE FROM activation_challenges WHERE id = ? AND license_id = ? AND device_key_hash = ? AND expires_at >= ?",
  ).bind(challengeRow.id, license.id, deviceHash, now).run();
  if (Number(consume.meta?.changes || 0) !== 1) return errorResponse("challenge_already_consumed", 409);

  let device = await database(env).prepare(
    "SELECT * FROM devices WHERE license_id = ? AND device_key_hash = ?",
  ).bind(license.id, deviceHash).first();
  if (!device) {
    const activeDevices = await activeDeviceCount(env, license.id);
    const maxDevices = Number(license.max_devices || 1);
    if (activeDevices >= maxDevices) {
      return errorResponse("device_limit_reached", 409, {
        recovery: "deactivate_old_device_or_admin_reset",
        active_devices: activeDevices,
        max_devices: maxDevices,
      });
    }
    const deviceId = crypto.randomUUID();
    await database(env).prepare(
      "INSERT INTO devices (id, license_id, device_key_hash, public_jwk, status, created_at, last_seen_at) VALUES (?, ?, ?, ?, 'active', ?, ?)",
    ).bind(deviceId, license.id, deviceHash, JSON.stringify(publicJwk), now, now).run();
    device = await database(env).prepare("SELECT * FROM devices WHERE id = ?").bind(deviceId).first();
  } else if (device.status === "active") {
    await database(env).prepare("UPDATE devices SET last_seen_at = ?, public_jwk = ? WHERE id = ?")
      .bind(now, JSON.stringify(publicJwk), device.id).run();
  } else {
    const activeDevices = await activeDeviceCount(env, license.id);
    const maxDevices = Number(license.max_devices || 1);
    if (activeDevices >= maxDevices) {
      return errorResponse("device_limit_reached", 409, {
        recovery: "deactivate_old_device_or_admin_reset",
        active_devices: activeDevices,
        max_devices: maxDevices,
      });
    }
    await database(env).prepare("UPDATE devices SET status = 'active', public_jwk = ?, last_seen_at = ? WHERE id = ?")
      .bind(JSON.stringify(publicJwk), now, device.id).run();
  }
  device = await database(env).prepare("SELECT * FROM devices WHERE id = ?").bind(device.id).first();
  return jsonResponse({ ok: true, license_contract_version: LICENSE_CONTRACT_VERSION, lease: await issueLease(env, license, device) });
}

async function authenticatedDeviceRequest(body, env) {
  if (!body.lease || typeof body.device_signature !== "string" || body.device_signature.length > 512) {
    throw new RequestError(400, "invalid_device_request");
  }
  let payload;
  try {
    payload = await verifyLease(env, body.lease);
  } catch (error) {
    throw new RequestError(403, error.message || "invalid_lease");
  }
  const now = Math.floor(Date.now() / 1000);
  const license = await database(env).prepare("SELECT * FROM licenses WHERE id = ?").bind(payload.license_id).first();
  const device = await database(env).prepare("SELECT * FROM devices WHERE id = ?").bind(payload.device_id).first();
  if (!licenseUsable(license, now)) throw new RequestError(403, "license_revoked_or_expired");
  if (!device || device.status !== "active" || device.license_id !== license.id || device.device_key_hash !== payload.device_key_hash) {
    throw new RequestError(403, "device_revoked");
  }
  let publicJwk;
  try {
    publicJwk = validatePublicJwk(JSON.parse(device.public_jwk || "{}"));
  } catch {
    throw new RequestError(403, "device_public_key_invalid");
  }
  const proofValid = await verifyDeviceSignature(publicJwk, body.device_signature, body.lease.payload);
  if (!proofValid) throw new RequestError(403, "invalid_device_signature");
  return { payload, license, device, now };
}

async function handleRefresh(request, env) {
  const body = await readJson(request);
  const context = await authenticatedDeviceRequest(body, env);
  await database(env).prepare("UPDATE devices SET last_seen_at = ? WHERE id = ?")
    .bind(context.now, context.device.id).run();
  return jsonResponse({
    ok: true,
    license_contract_version: LICENSE_CONTRACT_VERSION,
    lease: await issueLease(env, context.license, context.device),
  });
}

async function handleDeactivate(request, env) {
  const body = await readJson(request);
  const context = await authenticatedDeviceRequest(body, env);
  await database(env).prepare("UPDATE devices SET status = 'revoked', last_seen_at = ? WHERE id = ?")
    .bind(context.now, context.device.id).run();
  return jsonResponse({ ok: true, license_contract_version: LICENSE_CONTRACT_VERSION, device_id: context.device.id, status: "revoked" });
}

function requireAdmin(request, env) {
  const value = request.headers.get("authorization") || "";
  return Boolean(env.ADMIN_TOKEN) && value === `Bearer ${env.ADMIN_TOKEN}`;
}

async function handleAdminCreateLicense(request, env) {
  if (!requireAdmin(request, env)) return errorResponse("unauthorized", 401);
  const body = await readJson(request);
  const key = validatedLicenseKey(body.license_key);
  if (await loadLicense(env, key)) return errorResponse("license_exists", 409);

  const now = Math.floor(Date.now() / 1000);
  const id = validatedIdentifier(body.id);
  const keyHash = await sha256Base64Url(encoder.encode(key));
  const features = validatedFeatures(body.features);
  const maxDevices = validatedInteger(body.max_devices, "max_devices", 1, 1000, 1);
  const expiresAt = validatedInteger(body.expires_at, "expires_at", 0, 4102444800, 0);
  await database(env).prepare(
    "INSERT INTO licenses (id, key_hash, status, max_devices, features_json, expires_at, created_at, updated_at) VALUES (?, ?, 'active', ?, ?, ?, ?, ?)",
  ).bind(id, keyHash, maxDevices, JSON.stringify(features), expiresAt, now, now).run();
  return jsonResponse({ ok: true, id, license_key: key, status: "active", max_devices: maxDevices, expires_at: expiresAt, features });
}

async function licenseForAdminBody(body, env) {
  const key = validatedLicenseKey(body.license_key);
  const license = await loadLicense(env, key);
  if (!license) throw new RequestError(404, "not_found");
  return { key, license };
}

async function handleAdminUpdate(request, env) {
  if (!requireAdmin(request, env)) return errorResponse("unauthorized", 401);
  const body = await readJson(request);
  const { license } = await licenseForAdminBody(body, env);
  const hasUpdate = ["status", "max_devices", "expires_at", "features"].some((key) => Object.hasOwn(body, key));
  if (!hasUpdate) throw new RequestError(400, "no_license_updates");

  const status = validatedStatus(body.status, license.status);
  const maxDevices = validatedInteger(body.max_devices, "max_devices", 1, 1000, Number(license.max_devices));
  const expiresAt = validatedInteger(body.expires_at, "expires_at", 0, 4102444800, Number(license.expires_at));
  const currentFeatures = featuresFromLicense(license);
  const features = validatedFeatures(body.features, currentFeatures);
  const now = Math.floor(Date.now() / 1000);
  await database(env).prepare(
    "UPDATE licenses SET status = ?, max_devices = ?, features_json = ?, expires_at = ?, updated_at = ? WHERE id = ?",
  ).bind(status, maxDevices, JSON.stringify(features), expiresAt, now, license.id).run();
  return jsonResponse({ ok: true, id: license.id, status, max_devices: maxDevices, expires_at: expiresAt, features });
}

async function handleAdminRevoke(request, env) {
  if (!requireAdmin(request, env)) return errorResponse("unauthorized", 401);
  const body = await readJson(request);
  const { license } = await licenseForAdminBody(body, env);
  const now = Math.floor(Date.now() / 1000);
  await database(env).prepare("UPDATE licenses SET status = 'revoked', updated_at = ? WHERE id = ?").bind(now, license.id).run();
  return jsonResponse({ ok: true, id: license.id, status: "revoked" });
}

async function handleAdminResetDevices(request, env) {
  if (!requireAdmin(request, env)) return errorResponse("unauthorized", 401);
  const body = await readJson(request);
  const { license } = await licenseForAdminBody(body, env);
  const now = Math.floor(Date.now() / 1000);
  const result = await database(env).prepare(
    "UPDATE devices SET status = 'revoked', last_seen_at = ? WHERE license_id = ? AND status = 'active'",
  ).bind(now, license.id).run();
  await database(env).prepare("DELETE FROM activation_challenges WHERE license_id = ?").bind(license.id).run();
  return jsonResponse({
    ok: true,
    id: license.id,
    reset_devices: Number(result.meta?.changes || 0),
  });
}

const worker = {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return jsonResponse({ ok: true });
    const url = new URL(request.url);
    try {
      if (request.method === "GET" && url.pathname === "/v1/health") {
        return jsonResponse({
          ok: true,
          service: "tlinkauto-license",
          license_contract_version: LICENSE_CONTRACT_VERSION,
          now: Math.floor(Date.now() / 1000),
        });
      }
      if (request.method === "GET" && url.pathname === "/v1/public-key") {
        const { publicJwk } = await signingKeys(env);
        return jsonResponse({
          ok: true,
          license_contract_version: LICENSE_CONTRACT_VERSION,
          key_id: env.LICENSE_KEY_ID || "tlinkauto-test-2026-01",
          public_key: publicJwk,
        });
      }
      if (request.method === "POST" && url.pathname === "/v1/challenge") return await handleChallenge(request, env);
      if (request.method === "POST" && url.pathname === "/v1/activate") return await handleActivate(request, env);
      if (request.method === "POST" && url.pathname === "/v1/refresh") return await handleRefresh(request, env);
      if (request.method === "POST" && url.pathname === "/v1/deactivate") return await handleDeactivate(request, env);
      if (request.method === "POST" && url.pathname === "/v1/admin/licenses") return await handleAdminCreateLicense(request, env);
      if (request.method === "POST" && url.pathname === "/v1/admin/update") return await handleAdminUpdate(request, env);
      if (request.method === "POST" && url.pathname === "/v1/admin/revoke") return await handleAdminRevoke(request, env);
      if (request.method === "POST" && url.pathname === "/v1/admin/reset-devices") return await handleAdminResetDevices(request, env);
      return errorResponse("not_found", 404);
    } catch (error) {
      if (error instanceof RequestError) return errorResponse(error.code, error.status);
      console.error(error);
      return errorResponse("internal_error", 500);
    }
  },
};

export const __test = {
  LICENSE_CONTRACT_VERSION,
  base64UrlEncode,
  base64UrlDecode,
  rawSignatureToDer,
  derSignatureToRaw,
  deviceKeyHash,
};

export default worker;
