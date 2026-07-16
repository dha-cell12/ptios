import { webcrypto } from "node:crypto";

const { publicKey, privateKey } = await webcrypto.subtle.generateKey(
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["sign", "verify"],
);

const privateJwk = await webcrypto.subtle.exportKey("jwk", privateKey);
const publicJwk = await webcrypto.subtle.exportKey("jwk", publicKey);

console.log("Worker secret value for LICENSE_SIGNING_PRIVATE_JWK:");
console.log(JSON.stringify(privateJwk));
console.log("");
console.log("LicenseConfig.plist values:");
console.log(`LicensePublicKeyX = ${publicJwk.x}`);
console.log(`LicensePublicKeyY = ${publicJwk.y}`);
console.log("");
console.log("Set the secret with:");
console.log("npx wrangler secret put LICENSE_SIGNING_PRIVATE_JWK");
