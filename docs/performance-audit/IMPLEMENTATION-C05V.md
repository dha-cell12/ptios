# C05v — Check remaining output before JSON append and copy

Date: 2026-11-06 (Asia/Bangkok). Baseline: `1451e7b5`; user reported C05u build passed and requested continued implementation. Shared JSON helper used by four rootfull/roothide/production TrollStore UI codecs; TouchPOC excluded. Continues C05/P1-60.

## Prefix output admission

Project an accepted JSON prefix into its eventual success-wire size with the existing exact `5 + 4 * ceil(jsonBytes / 3)` calculation. A prefix only grows, so if even that projection cannot fit the bound caller's remaining allowance, a completed success cannot fit either. Consult the captured native budget, including parent response bytes, before appending a chunk to the stream buffer. Mark the refusal terminal and return no partial JSON.

Check the minimum five-byte framing allowance before stream/writer work, full coherent JSON before immutable copy and the successful result after pool drain. Keep C05s final wire admission. These checks reserve or append no bytes in the caller's response sink; concurrent producers can consume allowance later, so final checks and actual sink admission remain necessary.

Native `outputAllowed` retains its sticky OutputLimit effect on refusal. Codecs keep their existing `ui_response_too_large` path and outer overflow/transport handling. Check existing stop first so an already-cancelled caller is not converted into an output limit merely by the new minimum check. Parent/cleanup/deadline/TLS semantics are unchanged. Hard JSON quota rejection still precedes projection and does not itself poison a live native budget.

Unbound or unlimited callers retain the hard JSON/wire ceilings. No schema, public API signature, codec branch, input/query/action/authority/tap ordering or retry change. Output failure cannot roll back a committed effect. Early output refusal can precede later JSON validation errors.

## Scope and cost

Smaller native output allowances can now stop the application buffer before the hard 786426-byte quota and avoid an immutable result copy that cannot fit. This does not stop Foundation from creating internal temporaries or doing opaque work before its next callback. NSMutableData capacity/allocator overhead, initial graphs, missing caller bindings and whole-operation/device memory bounds remain open.

Reason checks and per-chunk output mutex checks add ordinary-path work. No measured throughput/RSS/latency gain is claimed. C05/P1-60 remain partial.

## Verification

Freeze the complete preceding C05u writer and reverse only output admission/state additions. Require the full preceding writer hash before all existing writer/task/server/AX restoration chains. Four codec sources and protocol limits remain unchanged; runner count remains 90.

Add 100,000 portable cases using actual native budgets and exact wire arithmetic: parent sharing, existing response prefix, exact/short/unlimited allowance, sticky refusal and no response reservation. Check captured-budget isolation from nested TLS and hard-size rejection without mutating native limit state.

Extend the Foundation/CoreFoundation/ARC/ASan/UBSan executable with complete current/C05u writer classes. Controlled chunks cover pre-writer refusal, whole/split rejected appends, exact fits, parent prefixes and unrelated nested scopes. A producer consumes output after its last JSON write; the new helper refuses before copy while C05u returns data. A real Foundation writer under a 64-byte budget retains at most 42 JSON prefix bytes instead of returning the previous 100k-byte JSON. These are logical application-buffer counts, not physical Foundation allocation measurements.

Verify closed streams, flags/native reason, unchanged response bytes and weak budget retirement. Test already-cancelled callers under a tiny allowance. Run all four unchanged codecs against current/frozen producers: admitted JSON/framing stays equal, shortages retain the existing error without base64, and the new producer returns no rejected JSON NSData. Include 128 exact/refusal lifecycles; all prior stop/quota/count/exception/pool tests remain enabled.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete writer/task/server/AX restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Apple/iOS compilation and Foundation/ARC/ASan/UBSan execution require macOS CI. Final transport/device qualification remains pending.
