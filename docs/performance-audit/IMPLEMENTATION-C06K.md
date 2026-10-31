# C06k — keyboard observer teardown name

Date: 2026-10-31 (Asia/Bangkok). Baseline: `7fc8a1c9`; user reported C06j build passed and requested continued implementation. This checkpoint fixes the confirmed notification-name mismatch in **P1-69** for the rootfull/roothide appdelegate tweak. TouchPOC excluded.

Both UIKeyboardImpl initializers register for `com.tlinkauto.tlinkauto.keyboardcontrol`. The production sender posts that same name, but dealloc removed `com.tlinkauto.tlinkauto.textinput`. Change the scoped dealloc removal to `keyboardcontrol`, preserving its observer/object arguments and original teardown call. This removes the registrations belonging to that observer for the actual command channel.

Keep both initializers and the complete notification handler unchanged. Whether initializer chaining causes duplicate registrations/delivery on a particular private UIKit implementation remains unproven; this checkpoint makes no claim to fix or measure that risk. No extra associated state, registration ordering, dispatch policy or keyboard command behavior is introduced. Production TrollStore uses a separate route and is unchanged.

Verification on Windows:

- Compare the complete file against HEAD with only the single notification-name substitution allowed. Confirm both registrations, scoped removal and production sender use the same name.
- Existing `check-native-budget-safety.mjs` source guards, portable C++ cases and macOS fixture extraction pass. Apple Foundation/ARC/UIKeyboard execution is unavailable on this host.
- Existing workflow source checks and `git diff --check` pass; artifact-only checks are skipped.

No new test fixture is needed for this one-line correction. The actual rootfull/roothide build and private UIKit/distributed-notification lifecycle require macOS CI/device qualification. C06 remains partial; the broader VPN, cancellation, persistence and device work remains tracked separately.
