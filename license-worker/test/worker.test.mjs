import assert from "node:assert/strict";
import test from "node:test";

import worker, { __test } from "../src/index.js";

class FakeStatement {
  constructor(database, sql) {
    this.database = database;
    this.sql = sql.replace(/\s+/g, " ").trim().toLowerCase();
    this.values = [];
  }

  bind(...values) {
    this.values = values;
    return this;
  }

  async first() {
    const [a, b] = this.values;
    if (this.sql === "select * from licenses where key_hash = ?") {
      return [...this.database.licenses.values()].find((row) => row.key_hash === a) || null;
    }
    if (this.sql === "select * from licenses where id = ?") {
      return this.database.licenses.get(a) || null;
    }
    if (this.sql === "select * from activation_challenges where id = ? and license_id = ?") {
      const row = this.database.challenges.get(a);
      return row?.license_id === b ? row : null;
    }
    if (this.sql === "select * from devices where license_id = ? and device_key_hash = ?") {
      return [...this.database.devices.values()].find(
        (row) => row.license_id === a && row.device_key_hash === b,
      ) || null;
    }
    if (this.sql === "select * from devices where id = ?") {
      return this.database.devices.get(a) || null;
    }
    if (this.sql === "select count(*) as count from devices where license_id = ? and status = 'active'") {
      return {
        count: [...this.database.devices.values()].filter(
          (row) => row.license_id === a && row.status === "active",
        ).length,
      };
    }
    throw new Error(`fake_d1_unhandled_first: ${this.sql}`);
  }

  async run() {
    const v = this.values;
    let changes = 0;
    if (this.sql.startsWith("insert into licenses ")) {
      const [id, keyHash, maxDevices, featuresJson, expiresAt, createdAt, updatedAt] = v;
      this.database.licenses.set(id, {
        id,
        key_hash: keyHash,
        status: "active",
        max_devices: maxDevices,
        features_json: featuresJson,
        expires_at: expiresAt,
        created_at: createdAt,
        updated_at: updatedAt,
      });
      changes = 1;
    } else if (this.sql.startsWith("insert into activation_challenges ")) {
      const [id, licenseId, deviceKeyHash, challenge, expiresAt, createdAt] = v;
      this.database.challenges.set(id, {
        id,
        license_id: licenseId,
        device_key_hash: deviceKeyHash,
        challenge,
        expires_at: expiresAt,
        created_at: createdAt,
      });
      changes = 1;
    } else if (this.sql === "delete from activation_challenges where expires_at < ?") {
      for (const [id, row] of this.database.challenges) {
        if (row.expires_at < v[0]) {
          this.database.challenges.delete(id);
          changes++;
        }
      }
    } else if (this.sql.startsWith("delete from activation_challenges where id = ? and license_id = ?")) {
      const [id, licenseId, deviceKeyHash, now] = v;
      const row = this.database.challenges.get(id);
      if (row && row.license_id === licenseId && row.device_key_hash === deviceKeyHash && row.expires_at >= now) {
        this.database.challenges.delete(id);
        changes = 1;
      }
    } else if (this.sql === "delete from activation_challenges where license_id = ?") {
      for (const [id, row] of this.database.challenges) {
        if (row.license_id === v[0]) {
          this.database.challenges.delete(id);
          changes++;
        }
      }
    } else if (this.sql.startsWith("insert into devices ")) {
      const [id, licenseId, deviceKeyHash, publicJwk, createdAt, lastSeenAt] = v;
      this.database.devices.set(id, {
        id,
        license_id: licenseId,
        device_key_hash: deviceKeyHash,
        public_jwk: publicJwk,
        status: "active",
        created_at: createdAt,
        last_seen_at: lastSeenAt,
      });
      changes = 1;
    } else if (this.sql === "update devices set last_seen_at = ?, public_jwk = ? where id = ?") {
      changes = this.database.update(this.database.devices, v[2], {
        last_seen_at: v[0],
        public_jwk: v[1],
      });
    } else if (this.sql === "update devices set status = 'active', public_jwk = ?, last_seen_at = ? where id = ?") {
      changes = this.database.update(this.database.devices, v[2], {
        status: "active",
        public_jwk: v[0],
        last_seen_at: v[1],
      });
    } else if (this.sql === "update devices set last_seen_at = ? where id = ?") {
      changes = this.database.update(this.database.devices, v[1], { last_seen_at: v[0] });
    } else if (this.sql === "update devices set status = 'revoked', last_seen_at = ? where id = ?") {
      changes = this.database.update(this.database.devices, v[1], {
        status: "revoked",
        last_seen_at: v[0],
      });
    } else if (this.sql.startsWith("update devices set status = 'revoked', last_seen_at = ? where license_id = ?")) {
      for (const row of this.database.devices.values()) {
        if (row.license_id === v[1] && row.status === "active") {
          row.status = "revoked";
          row.last_seen_at = v[0];
          changes++;
        }
      }
    } else if (this.sql.startsWith("update licenses set status = ?, max_devices = ?")) {
      changes = this.database.update(this.database.licenses, v[5], {
        status: v[0],
        max_devices: v[1],
        features_json: v[2],
        expires_at: v[3],
        updated_at: v[4],
      });
    } else if (this.sql === "update licenses set status = 'revoked', updated_at = ? where id = ?") {
      changes = this.database.update(this.database.licenses, v[1], {
        status: "revoked",
        updated_at: v[0],
      });
    } else {
      throw new Error(`fake_d1_unhandled_run: ${this.sql}`);
    }
    return { success: true, meta: { changes } };
  }
}

class FakeD1 {
  constructor() {
    this.licenses = new Map();
    this.devices = new Map();
    this.challenges = new Map();
  }

  prepare(sql) {
    return new FakeStatement(this, sql);
  }

  update(table, id, values) {
    const row = table.get(id);
    if (!row) return 0;
    Object.assign(row, values);
    return 1;
  }
}

async function createEnvironment() {
  const signingPair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const privateJwk = await crypto.subtle.exportKey("jwk", signingPair.privateKey);
  return {
    DB: new FakeD1(),
    LICENSE_SIGNING_PRIVATE_JWK: JSON.stringify(privateJwk),
    LICENSE_KEY_ID: "phase-test-key",
    ADMIN_TOKEN: "phase-test-admin",
    LEASE_SECONDS: "300",
    OFFLINE_GRACE_SECONDS: "600",
  };
}

async function createDevice() {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  return {
    pair,
    publicJwk: await crypto.subtle.exportKey("jwk", pair.publicKey),
  };
}

async function call(env, path, body, admin = false) {
  const headers = { "content-type": "application/json" };
  if (admin) headers.authorization = `Bearer ${env.ADMIN_TOKEN}`;
  const response = await worker.fetch(new Request(`https://license.test${path}`, {
    method: body === undefined ? "GET" : "POST",
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  }), env);
  return { response, json: await response.json() };
}

async function sign(privateKey, message) {
  const raw = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    new TextEncoder().encode(message),
  );
  return __test.base64UrlEncode(__test.rawSignatureToDer(raw));
}

async function createLicense(env, overrides = {}) {
  return call(env, "/v1/admin/licenses", {
    license_key: "TLINK-PHASE-0001",
    max_devices: 1,
    features: ["automation", "stream", "script", "admin", "shell"],
    ...overrides,
  }, true);
}

async function activate(env, device, licenseKey = "TLINK-PHASE-0001") {
  const challenge = await call(env, "/v1/challenge", {
    license_key: licenseKey,
    device_public_key: device.publicJwk,
  });
  assert.equal(challenge.response.status, 200);
  const signature = await sign(device.pair.privateKey, challenge.json.challenge);
  const activation = await call(env, "/v1/activate", {
    license_key: licenseKey,
    device_public_key: device.publicJwk,
    challenge_id: challenge.json.challenge_id,
    signature,
  });
  return { challenge, activation };
}

async function authenticatedCall(env, path, lease, privateKey) {
  return call(env, path, {
    lease,
    device_signature: await sign(privateKey, lease.payload),
  });
}

function decodeLease(lease) {
  return JSON.parse(new TextDecoder().decode(__test.base64UrlDecode(lease.payload)));
}

test("health and request validation expose contract v1", async () => {
  const env = await createEnvironment();
  const health = await call(env, "/v1/health");
  assert.equal(health.response.status, 200);
  assert.equal(health.json.license_contract_version, 1);

  const unauthorized = await call(env, "/v1/admin/licenses", { license_key: "TLINK-TEST-0001" });
  assert.equal(unauthorized.response.status, 401);
  assert.equal(unauthorized.json.error, "unauthorized");

  const invalid = await createLicense(env, { features: ["automation", "unknown"] });
  assert.equal(invalid.response.status, 400);
  assert.equal(invalid.json.error, "invalid_features");

  const invalidLimit = await createLicense(env, { max_devices: 0 });
  assert.equal(invalidLimit.response.status, 400);
  assert.equal(invalidLimit.json.error, "invalid_max_devices");

  const malformedChallenge = await call(env, "/v1/challenge", {
    license_key: "bad",
    device_public_key: {},
  });
  assert.equal(malformedChallenge.response.status, 400);
  assert.equal(malformedChallenge.json.error, "invalid_license_key_format");

  const malformedRefresh = await call(env, "/v1/refresh", { device_signature: "bad" });
  assert.equal(malformedRefresh.response.status, 400);
  assert.equal(malformedRefresh.json.error, "invalid_device_request");

  const oversized = await worker.fetch(new Request("https://license.test/v1/challenge", {
    method: "POST",
    headers: { "content-type": "application/json", "content-length": "20000" },
    body: "{}",
  }), env);
  assert.equal(oversized.status, 413);
  assert.equal((await oversized.json()).error, "request_body_too_large");
});

test("create, activate and refresh issue a device-bound contract v1 lease", async () => {
  const env = await createEnvironment();
  assert.equal((await createLicense(env)).response.status, 200);
  const device = await createDevice();
  const { activation } = await activate(env, device);
  assert.equal(activation.response.status, 200);

  const payload = decodeLease(activation.json.lease);
  assert.equal(payload.license_contract_version, 1);
  assert.deepEqual(payload.features, ["automation", "stream", "script", "admin", "shell"]);

  const refresh = await authenticatedCall(env, "/v1/refresh", activation.json.lease, device.pair.privateKey);
  assert.equal(refresh.response.status, 200);
  assert.equal(decodeLease(refresh.json.lease).device_id, payload.device_id);
});

test("activation challenge rejects bad proof, expiry and reuse", async () => {
  const env = await createEnvironment();
  await createLicense(env);
  const device = await createDevice();
  const wrongDevice = await createDevice();

  const challenge = await call(env, "/v1/challenge", {
    license_key: "TLINK-PHASE-0001",
    device_public_key: device.publicJwk,
  });
  const badProof = await call(env, "/v1/activate", {
    license_key: "TLINK-PHASE-0001",
    device_public_key: device.publicJwk,
    challenge_id: challenge.json.challenge_id,
    signature: await sign(wrongDevice.pair.privateKey, challenge.json.challenge),
  });
  assert.equal(badProof.response.status, 403);
  assert.equal(badProof.json.error, "invalid_device_signature");

  const goodBody = {
    license_key: "TLINK-PHASE-0001",
    device_public_key: device.publicJwk,
    challenge_id: challenge.json.challenge_id,
    signature: await sign(device.pair.privateKey, challenge.json.challenge),
  };
  assert.equal((await call(env, "/v1/activate", goodBody)).response.status, 200);
  const reused = await call(env, "/v1/activate", goodBody);
  assert.equal(reused.response.status, 403);
  assert.equal(reused.json.error, "invalid_or_expired_challenge");

  const racingChallenge = await call(env, "/v1/challenge", {
    license_key: "TLINK-PHASE-0001",
    device_public_key: device.publicJwk,
  });
  const racingBody = {
    license_key: "TLINK-PHASE-0001",
    device_public_key: device.publicJwk,
    challenge_id: racingChallenge.json.challenge_id,
    signature: await sign(device.pair.privateKey, racingChallenge.json.challenge),
  };
  const racingResults = await Promise.all([
    call(env, "/v1/activate", racingBody),
    call(env, "/v1/activate", racingBody),
  ]);
  assert.equal(racingResults.filter((result) => result.response.status === 200).length, 1);
  assert.equal(racingResults.filter((result) => result.response.status !== 200).length, 1);

  const expired = await call(env, "/v1/challenge", {
    license_key: "TLINK-PHASE-0001",
    device_public_key: device.publicJwk,
  });
  env.DB.challenges.get(expired.json.challenge_id).expires_at = 1;
  const expiredResult = await call(env, "/v1/activate", {
    license_key: "TLINK-PHASE-0001",
    device_public_key: device.publicJwk,
    challenge_id: expired.json.challenge_id,
    signature: await sign(device.pair.privateKey, expired.json.challenge),
  });
  assert.equal(expiredResult.response.status, 403);
  assert.equal(expiredResult.json.error, "invalid_or_expired_challenge");
});

test("device limit, deactivate and same-key reactivation have coherent slots", async () => {
  const env = await createEnvironment();
  await createLicense(env);
  const first = await createDevice();
  const second = await createDevice();
  const firstActivation = (await activate(env, first)).activation;
  assert.equal(firstActivation.response.status, 200);

  const secondActivation = (await activate(env, second)).activation;
  assert.equal(secondActivation.response.status, 409);
  assert.equal(secondActivation.json.error, "device_limit_reached");

  const deactivated = await authenticatedCall(env, "/v1/deactivate", firstActivation.json.lease, first.pair.privateKey);
  assert.equal(deactivated.response.status, 200);
  assert.equal(deactivated.json.status, "revoked");

  const repeatedDeactivate = await authenticatedCall(env, "/v1/deactivate", firstActivation.json.lease, first.pair.privateKey);
  assert.equal(repeatedDeactivate.response.status, 403);
  assert.equal(repeatedDeactivate.json.error, "device_revoked");

  const revokedRefresh = await authenticatedCall(env, "/v1/refresh", firstActivation.json.lease, first.pair.privateKey);
  assert.equal(revokedRefresh.response.status, 403);
  assert.equal(revokedRefresh.json.error, "device_revoked");

  const reactivated = (await activate(env, first)).activation;
  assert.equal(reactivated.response.status, 200);
});

test("reset, feature update, expiry and revoke are reflected by refresh", async () => {
  const env = await createEnvironment();
  await createLicense(env);
  const device = await createDevice();
  const original = (await activate(env, device)).activation;

  const reset = await call(env, "/v1/admin/reset-devices", { license_key: "TLINK-PHASE-0001" }, true);
  assert.equal(reset.response.status, 200);
  assert.equal(reset.json.reset_devices, 1);
  assert.equal((await activate(env, device)).activation.response.status, 200);

  const active = (await activate(env, device)).activation;
  const update = await call(env, "/v1/admin/update", {
    license_key: "TLINK-PHASE-0001",
    max_devices: 2,
    features: ["automation", "stream"],
  }, true);
  assert.equal(update.response.status, 200);
  assert.equal(update.json.max_devices, 2);
  const refreshed = await authenticatedCall(env, "/v1/refresh", active.json.lease, device.pair.privateKey);
  assert.deepEqual(decodeLease(refreshed.json.lease).features, ["automation", "stream"]);

  const expiredUpdate = await call(env, "/v1/admin/update", {
    license_key: "TLINK-PHASE-0001",
    expires_at: 1,
  }, true);
  assert.equal(expiredUpdate.response.status, 200);
  const expiredRefresh = await authenticatedCall(env, "/v1/refresh", refreshed.json.lease, device.pair.privateKey);
  assert.equal(expiredRefresh.response.status, 403);
  assert.equal(expiredRefresh.json.error, "license_revoked_or_expired");

  await call(env, "/v1/admin/update", {
    license_key: "TLINK-PHASE-0001",
    expires_at: 0,
    status: "active",
  }, true);
  const revoke = await call(env, "/v1/admin/revoke", { license_key: "TLINK-PHASE-0001" }, true);
  assert.equal(revoke.response.status, 200);
  const revokedRefresh = await authenticatedCall(env, "/v1/refresh", active.json.lease, device.pair.privateKey);
  assert.equal(revokedRefresh.response.status, 403);
  assert.equal(revokedRefresh.json.error, "license_revoked_or_expired");

  assert.ok(original.json.lease);
});
