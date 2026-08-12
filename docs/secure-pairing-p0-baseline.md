# Secure Pairing P0 — baseline, threat model and wire contract v1

Status: **contract only / observe only**. P0 changes no request handling,
does not create a pairing window, and does not reject an existing client. The
machine-readable source of truth is
`test/fixtures/secure-pairing-contract-v1.json`.

## Baseline frozen on 2026-08-13

Both rootfull `tlinkautod` and TrollStore `streamd` bind the task service to
`0.0.0.0:6000`. Rootfull accepts the legacy CRLF task protocol and framed
`ZXTP` JSON v1; TrollStore accepts the legacy CRLF task protocol. Neither path
currently authenticates the controlling computer, encrypts task contents, or
rejects a replayed task. TrollStore's outbound WSS bridge authenticates to its
relay with a bearer token, but that transport credential is not a locally
approved controller identity.

Ports `7001` through `7006` expose video variants after the license feature
gate. That gate establishes product entitlement, not peer identity. A valid
license must never be treated as evidence that a LAN or relay peer is trusted.

P0 publishes these exact task `97` markers in both runtimes:

```text
securePairingState=contract_only
securePairingPhase=0
securePairingContractVersion=1
securePairingTransport=zxsp_json_v1
securePairingMode=observe_only
securePairingLegacyPolicy=unchanged_p0
securePairingCrypto=p256_ecdh_ecdsa_hkdf_sha256_aes256_gcm
securePairingDeviceValidated=0
```

## Assets and trust boundaries

Protected assets include touch/control authority, screenshots and live video,
OCR output, scripts and their files, clipboard content, app/process control,
VPN operations, shell/admin tasks, device identifiers, and pairing records.

Trust boundaries are:

1. The iOS device and its local confirmation UI.
2. The controlling PC/browser, which is untrusted until explicitly paired.
3. The LAN, USB tunnel, reverse proxy, relay, and WSS service, all treated as
   attacker-controlled transports.
4. Rootfull daemon/SpringBoard IPC and TrollStore helper processes. These are
   local implementation boundaries and must not be exposed as pairing bypasses.
5. The license Worker. It grants licensed features but does not approve a
   controller.

## Threat model

The v1 design must resist:

- LAN discovery followed by unauthorized task execution or video capture;
- passive capture of tasks, images, OCR, scripts, clipboard, or credentials;
- active man-in-the-middle substitution during first pairing;
- replay, duplication, reordering, or cross-session injection;
- downgrade from a recognized secure endpoint to legacy plaintext;
- theft/reuse of a displayed bootstrap value after its short window;
- a relay or bearer-token holder impersonating a locally approved controller;
- scope escalation, revoked-client reuse, and license/pairing policy confusion;
- malformed length, oversized JSON, nonce reuse, and parser desynchronization;
- sensitive key material or raw setup secrets appearing in task/log output.

Out of scope for P0 are compromise of the unlocked iOS kernel, a compromised
paired controller, shoulder-surfing the live QR screen, and traffic-analysis
metadata. Those risks still require operational controls and key revocation.

## Security decisions

- Pairing can be opened only by local UI for 120 seconds. A network request
  cannot open it.
- Bootstrap is a 32-byte random secret delivered by local QR/copy plus a
  16-byte one-use pairing identifier. There is no six-digit mode because a
  captured handshake would make a short secret vulnerable to guessing.
- The device identity is P-256 and stored `ThisDeviceOnly`; Secure Enclave is
  preferred where available. The QR binds its SHA-256 fingerprint.
- Both peers use fresh P-256 ECDH keys. Pairing proofs use HKDF-SHA256 and
  HMAC-SHA256; identity possession uses P-256 ECDSA/SHA-256.
- A pending controller name, fingerprint, and requested scopes must be approved
  on the device before `pair.challenge` is emitted.
- Every later session uses new ephemeral ECDH, mutual identity signatures, and
  direction-specific AES-256-GCM keys/nonces.
- Sequence numbers are strict, contiguous, and independent in each direction.
  A duplicate or gap closes the session. Compression is forbidden in v1.
- Effective access is the intersection of locally granted pairing scopes and
  the signed-license feature set. Pairing never widens license rights.

## ZXSP frame

Secure Pairing uses an additive frame on TCP 6000 and equivalent binary WSS
messages. It does not overload a legacy task number.

```text
offset  size  field
0       4     ASCII "ZXSP"
4       1     contract version (1)
5       1     message type
6       2     flags, big-endian; must be zero in v1
8       4     UTF-8 JSON body length, big-endian
12      n     JSON body
```

Handshake JSON is capped at 64 KiB; every frame body is capped at 1 MiB.
Binary values use RFC 4648 base64url without padding. Once `ZXSP` is detected,
bad framing or an unsupported version must never fall through to the legacy
parser. The server returns a bounded error when possible and closes.

Message types are `pair.begin` `0x01`, `pair.challenge` `0x02`, `pair.finish`
`0x03`, `pair.complete` `0x04`, `session.open` `0x10`, `session.accept`
`0x11`, `secure.data` `0x20`, `secure.close` `0x21`, and `error` `0x7f`.
The numeric header type and JSON `type` must agree.

## Pairing transcript

Public keys use the 65-byte uncompressed ANSI X9.63 P-256 representation.
ECDSA signatures use the fixed 64-byte IEEE P1363 `r || s` representation.
JSON included in a signature/proof is canonicalized using RFC 8785 JCS.

The transcript hash is domain-separated and length-delimited:

```text
Tpair = SHA256(
  ASCII("TLINK-SP-V1-PAIR\0") ||
  UINT32_BE(len(JCS(pair.begin))) || JCS(pair.begin) ||
  UINT32_BE(len(JCS(pair.challenge_without_proofs))) ||
  JCS(pair.challenge_without_proofs)
)
```

`pair_key` is HKDF-SHA256 over the ephemeral ECDH secret, with the bootstrap
secret as salt and `tlinkauto/secure-pairing/v1/pair-proof` as info. Device and
client proofs are HMAC-SHA256 over `TLINK-SP-V1-DEVICE\0 || Tpair` and
`TLINK-SP-V1-CLIENT\0 || Tpair`, respectively; both identity keys also sign
`Tpair`. The completion proof is HMAC-SHA256 over
`TLINK-SP-V1-COMPLETE\0 || Tpair || JCS(pair.complete_without_complete_proof)`.
It binds the assigned client ID and locally granted scopes. Pair IDs and setup
secrets are single-use and are erased on success, rejection, expiry, app
restart, or window close.

## Authenticated sessions

`session.open` identifies the stored client and contains a fresh ephemeral key,
32-byte nonce, timestamp, and client identity signature. `session.accept`
contains the matching device values and device signature. Both sides derive 72
bytes with HKDF-SHA256: two 32-byte AES keys followed by two four-byte nonce
prefixes. The nonce is the direction prefix followed by a big-endian 64-bit
sequence number.

The client signs:

```text
Hopen = SHA256(
  ASCII("TLINK-SP-V1-OPEN\0") ||
  UINT32_BE(len(JCS(session.open_without_client_signature))) ||
  JCS(session.open_without_client_signature)
)
```

After verifying that signature, the device signs:

```text
Haccept = SHA256(
  ASCII("TLINK-SP-V1-ACCEPT\0") ||
  UINT32_BE(len(JCS(complete_session.open))) || JCS(complete_session.open) ||
  UINT32_BE(len(JCS(session.accept_without_device_signature))) ||
  JCS(session.accept_without_device_signature)
)
```

Session HKDF input is the fresh ephemeral ECDH secret, salt is
`SHA256(client_nonce || device_nonce)`, and info is the ASCII string
`tlinkauto/secure-pairing/v1/session`.

`secure.data` leaves only version, type, session ID, direction, sequence,
ciphertext, and tag outside encryption. Its authenticated additional data is
the domain string `TLINK-SP-V1-DATA\0` followed by the JCS metadata object.
Plaintext is either the existing JSON task request (`id`, `task`, `args`) or
response (`id`, `ok`, `data`, `error`). This preserves task semantics without
letting legacy delimiters enter the secure parser.

A session expires after eight hours, at `2^32` frames in either direction, on
revocation, or when pairing/license policy stops permitting it. Session-open
nonces are cached for ten minutes and timestamps allow at most 60 seconds of
skew.

## Authorization and migration

Scopes are `observe`, `automation`, `stream`, `script`, `admin`, and `shell`.
New clients request `observe` by default; expansion always requires local UI
approval. Revocation denies new sessions and closes active ones.

- P0: contract/capability only; legacy behavior is byte-for-byte unchanged.
- P1: implement optional pairing/session telemetry; legacy stays available.
- P2: move task clients to protected data and bind H264 access to a short-lived
  session-derived stream ticket.
- P3: add explicit opt-in enforcement, collect compatibility evidence, then
  make it the release default. Only task `97` capability and task `99` health
  remain available before authentication.

A client that has observed secure capability must not silently retry plaintext.
At P3, unpaired legacy requests receive `secure_pairing_required`; this is not
enabled in P0.

## P0 acceptance

P0 is complete when the fixture, cryptographic/frame vectors, task `97`
markers, documentation, CI checker, and read-only device baseline probe agree
for rootfull and TrollStore. No runtime may claim pairing is implemented or
device-validated during P0.
