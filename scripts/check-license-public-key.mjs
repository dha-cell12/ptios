import assert from "node:assert/strict";

function parseArgs(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    const value = argv[index + 1];
    assert.ok(name?.startsWith("--") && value, `invalid argument near ${name || "end"}`);
    values[name.slice(2)] = value;
  }
  return values;
}

const args = parseArgs(process.argv.slice(2));
for (const name of ["endpoint", "keyId", "publicKeyX", "publicKeyY"]) {
  assert.ok(args[name], `missing --${name}`);
}

assert.match(args.endpoint, /^https:\/\//, "license endpoint must use HTTPS");
assert.match(args.publicKeyX, /^[A-Za-z0-9_-]{43}$/, "invalid P-256 public x coordinate");
assert.match(args.publicKeyY, /^[A-Za-z0-9_-]{43}$/, "invalid P-256 public y coordinate");

const url = `${args.endpoint.replace(/\/+$/, "")}/v1/public-key`;
const response = await fetch(url, {
  headers: { accept: "application/json" },
  signal: AbortSignal.timeout(15_000),
});
assert.ok(response.ok, `public-key endpoint returned HTTP ${response.status}`);

const body = await response.json();
assert.equal(body?.ok, true, "public-key endpoint did not return ok=true");
assert.equal(body?.public_key?.kty, "EC", "Worker signing key must be EC");
assert.equal(body?.public_key?.crv, "P-256", "Worker signing key must use P-256");

const comparisons = [
  ["key_id", args.keyId, body.key_id],
  ["public_key.x", args.publicKeyX, body.public_key?.x],
  ["public_key.y", args.publicKeyY, body.public_key?.y],
];
for (const [field, configured, deployed] of comparisons) {
  assert.equal(
    configured,
    deployed,
    `${field} does not match ${url}; update the app build variables before packaging`,
  );
}

console.log(`License signing key matches ${url} (${body.key_id}).`);
