# C04i — bounded VPN daemon task lane

Date: 2026-10-31 (Asia/Bangkok). Baseline: `f418a508`, user reported build passed including C04h and its shared envelope C++11 correction. Complete normalized pre-change daemon SocketServer SHA-256: `bcfa821cf065dd85104fe4bd5eaccd3a59bcccda9dbb3e0847268dbd6c7b30f3`.
Status: **source/core implemented; new Foundation/GCD/ARC/ASan/UBSan cases pending macOS CI; independent device qualification pending**.
Finding: **P0-19/P1-14/P1-63 daemon task admission/owner portion**.

## Change

C04h separated VPN IPC owners, but ordinary daemon task work still waited behind task 59 on one serial work queue. Add a third serial work lane for network task 59, alongside the existing ordinary and image lanes. Classify only its existing two task bytes; retain the actual parser, task/license gates, private IPC/broker path and healthy replies.

Allow at most two VPN tasks, counting running, queued and completion-pending work. These are a subset of the existing fourteen ordinary slots, not an increase to total admission or a new reservation. Preserve the two reserved image slots and total sixteen-task cap. Two VPN tasks can coexist with twelve ordinary and two image tasks. A full ordinary allowance can still refuse VPN admission; no new fairness guarantee is added. Invalid counter states fail closed. An excess VPN client is closed through existing overload cleanup before entering an owner queue; there is no new busy reply or automatic retry.

Create a cancellation token and native 30-second VPN budget on the socket owner before enqueueing, using the existing request-token field/cleanup. Queue residence therefore consumes that deadline. The child budgets in C04h's sender preserve it instead of starting a fresh 30 seconds. Disconnect cancels the captured budget; queued closed/expired work does not call the task handler. Work stopped before/after dispatch uses vpn_request_expired. C01 retains its existing c01_request_expired behavior. Already submitted effects are not replayed or rolled back.

Publish both pending counts at admission and retire them only in the existing socket-owner completion ACK. Client disconnect does not free a still-running or queued slot. Worker exit also does not free capacity before that ACK. Preserve per-client parsing pause/FIFO and response framing, including JSON and fire-and-forget policy. Different clients in different lanes may now complete/interleave differently; VPN tasks themselves remain serial. No client context/FD ownership is transferred to the worker.

Rootfull/roothide daemon network dispatch is covered. Direct in-process/helper callers do not acquire these daemon slots and remain under their existing budgets/broker admission. Production TrollStore and TouchPOC are unchanged.

## Verification

The existing VPN runner extends its portable suite with exhaustive counter combinations, raw task classification and 100,000 admission/ACK lifecycles covering two VPN plus twelve ordinary plus two image tasks, third-VPN rejection and no early disconnect release. It remains C++11 on Clang hosts; MSVC uses its minimum C++14 mode.

A shared test-script reversal helper removes only the new include/count/queue/classification/admission/budget/expiry/ACK changes, then compares the complete daemon with its frozen source/hash. Both VPN and Event Channel historical guards use it before their existing reversals/digests. Actual runtime extraction continues to use the current source. C01 source assertions now recognize three owners while retaining its existing reservation/budget checks.

The actual socket parser/owner/output fixture adds a held VPN task while ordinary and image clients finish independently; per-client work stays paused until its VPN reply. It verifies third-VPN refusal, queued disconnect without early replacement, and both worker bodies finishing while the socket owner is held: counts remain charged until completion ACK. Additional cases cover a cooperative running-task disconnect, NS/C++ handler failures and recovery, controlled expired-budget rejection while queued, JSON reply identity, 64 balanced VPN cycles and final zero pending counts. The expiry fixture substitutes only the budget factory to supply an already-expired budget deterministically, avoiding a 30-second test sleep; default cases still use the actual factory. Historical FIFO tests start with a fresh call oracle afterward. The actual CF/private-port integration remains covered by C04h's separate fixture. These new Foundation/GCD/ARC/sanitizer cases require macOS CI and were not run on Windows. No actual VPN/profile/license/radio state is changed.

Windows verification: all 69 workflow runners (36 source checks, 33 safety runners), 521 existing workflow source checks, focused admission/socket/C01/source guards, expanded assert preprocessing and git diff --check. Sixteen artifact-only checks are skipped. No device throughput, latency, memory or power result is claimed.

## Remaining work

An already executing CFMessagePortSendRequest is still opaque: disconnect cancellation cannot preempt it, and its slot stays charged until return/completion. Only deadline crosses the private IPC envelope; no remote cancellation command is added. Native queue deadlines and the client's continuous-clock ceiling retain their existing clock policies; real sleep/scheduling behavior is unqualified. Direct legacy IPC callers can still hold legacy owners, and direct callers outside daemon admission are unaffected. Shared ordinary admission can refuse VPN, and cross-client completion ordering changes require device qualification. Manager cancellation/coalescing, effect recovery after timeout, mixed-version deployment/startup and backend/device qualification remain open. C04/P0-19/P1-14/P1-63 are not fully closed.
