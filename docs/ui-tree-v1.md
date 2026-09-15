# TLinkauto UI Tree v1

UI Tree v1 adds a shared, private-AXRuntime accessibility snapshot to the rootfull and TrollStore runtimes. It is additive: legacy tasks and Smart Wait v1 visual locators keep their existing wire responses.

## Runtime routes

- Rootfull TCP requests run in `tlinkautod`. Rootfull in-process scripts use the same shared core through the SpringBoard script bridge.
- TrollStore TCP requests and scripts run in `streamd`. `StreamControl.app` may remain in the background while the target application is foreground.
- `TLinkUIService` is not used. UI Tree does not create a scene or window.

The first contract is a flat accessibility snapshot because numeric AX attribute `3015` does not expose a proven, stable parent/child relationship. Hierarchy is deliberately reported as unavailable.

## Tasks

All request objects use base64-encoded UTF-8 JSON and successful responses contain base64-encoded UTF-8 JSON.

- `77`: capability and entitlement diagnostics.
- `78`: foreground snapshot.
- `79`: foreground selector lookup.
- `80`: element hit-test using `{ "x": 10, "y": 20 }`.
- `81`: context-validated selector lookup and native tap.

Tasks 77-81 require the `automation` license feature. Task 81 rechecks foreground bundle ID and PID before injecting the tap. It fails with `ui_context_changed` instead of tapping a stale coordinate.

Selectors support `text`, `identifier`, `role`, `index`, `visibleOnly`, `clickableOnly`, `caseSensitive`, and `match` (`contains`, `exact`, or `prefix`). Snake-case option aliases are accepted.
Every find or tap selector must contain a non-empty `text`, `identifier`, or `role`; an index by itself is rejected so an empty selector can never tap the first element accidentally.

AX frames and activation points use UIKit points. Task 81 converts the selected activation point to TLink's native-pixel HID coordinate space immediately before dispatch.

## Limits and safety

- Default 250 elements; hard maximum 1,000.
- Default query deadline 1,500 ms; hard maximum 3,000 ms.
- Screen-off and locked-device requests fail closed.
- Logs contain status and counters only; element labels and values are not logged by the UI-tree core.
- The snapshot reports `partial`, `truncated`, serialization failures, duration, and foreground context changes.

## JavaScript

```javascript
const tree = device.uiTree({ visibleOnly: true, maxElements: 250 });
const login = device.uiFind({ identifier: "login.button", match: "exact" });
const ready = device.waitForElement(
  { text: "Login", role: "button", clickableOnly: true },
  { timeoutMs: 5000, intervalMs: 250 }
);
if (ready.ok) device.tapElement({ text: "Login", role: "button", clickableOnly: true });
```

Use `scripts/Test-TLinkUITree.ps1` for device qualification. Promotion from `experimental` requires UIKit, SwiftUI, WebView, rotation, lock-state, app-switch race, and repeated-snapshot soak testing on both runtimes.
