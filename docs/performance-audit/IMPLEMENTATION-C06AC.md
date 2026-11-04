# C06ac — Private VPN record merge membership

Date: 2026-11-04 (Asia/Bangkok). Baseline: `46f34d54`; user reported C06ab build passed and requested continued implementation. Shared manager, active production TrollStore private backend; TouchPOC excluded.

## Per-call index

`TLinkVPNPrivateConfigurationRecords` rebuilt the primary records, then scanned every accumulated record for each valid fallback service identifier. With 1,000 primary and 1,000 distinct fallback identifiers, that merge performs 1,499,500 duplicate comparisons. Creation verification may rebuild this list up to fifty times within its existing operation budget (P1-67).

Use a function-local NSMutableSet for ordinary immutable NSString identifiers. Retain every valid primary record, including duplicate identifiers. For fallback records, check membership before append and insert accepted identifiers into the set. Preserve provider enumeration order, first accepted fallback name, raw_identifier ownership, normalization, invalid-input filtering and both provider reads. There is no persistent cache or new private selector.

Identifiers may alias NSMutableString objects. If any retained identifier is mutable, use the complete preceding linear comparison loop for the rest of that call. An incoming mutable identifier also uses the linear loop. A rejected mutable query is not retained and does not disable the index. This preserves comparisons against primary/fallback identifiers changed by a later service read, without depending on stale mutable hashes. Ordinary immutable NSString equality/hash behavior is the index contract; arbitrary custom subclasses with inconsistent hash/equality or side effects are not qualified.

Additional index storage is O(unique immutable identifiers) per call. Full provider enumeration, record/dictionary allocation, synchronous private calls, fifty-attempt verification and 100ms cadence remain. This removes quadratic merge membership for ordinary identifiers; it does not make full enumeration constant-time, cache private state, preempt opaque calls or complete P1-67. Profile, credentials, authority, marker, transition/cleanup budgets and the public NEVPNManager path retain their preceding source.

## Verification

Freeze the entire preceding collector. Source guards require exactly the membership/index/mutable additions, and restoring the frozen collector verifies the complete preceding manager SHA-256 before the C06s/C06n/C06m/C06l baseline chain. Both root and production TrollStore workflows run the new safety runner.

The macOS Foundation/ARC/ASan/UBSan fixture extracts complete current/frozen collectors and the actual identifier normalizer. Private store/service providers are controlled, including a dictionary-shaped ordered provider; ordinary NSDictionary/NSSet inputs are also covered. Production record arrays, dictionaries and membership sets are real Foundation objects. Instrument only duplicate comparison/set lookup counters, preserving the actual comparisons and set operations.

Cases cover 3,000 ordered golden inputs, invalid/missing providers/names/IDs, preserved primary duplicates, fallback first-wins, UUID/raw identifier identity, mutable primary/fallback mutation during later service reads, rejected mutable queries, fresh subsequent reads, returned ownership across pools, NS/C++ service faults and 1,000 repeated lifecycles. The 1,000+1,000 distinct-record case expects identical records and provider call counts, zero linear comparisons and 1,000 set lookups versus 1,499,500 preceding comparisons. Counts describe fixture operations, not measured device gains.

Windows validation: all **88 workflow runners** (36 source, 52 safety), **521 existing workflow source checks**, full preceding-manager/earlier checkpoint hashes, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Sixteen artifact-only checks skipped. New Apple compilation/native execution/iOS builds require macOS CI. Real private-store behavior, device allocations/latency and polling/backoff/cancellation qualification remain open; C06/P1-67 stay partial.
