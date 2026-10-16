# TLinkauto Performance Audit

This directory is the durable checkpoint for the long-running source audit.

## Operating rule

Do **not** attempt the whole audit in one session. Every session must:

1. Read `STATE.md` first.
2. Audit only the bounded scope listed under "Next session".
3. Append confirmed/preliminary findings to `FINDINGS.md`.
4. Update `COVERAGE.md`.
5. Update `STATE.md` last so interruption never loses the previous checkpoint.

Priority order follows the audit brief: performance, CPU/memory/battery, event latency, correctness, stability, iOS compatibility, then code quality.

## Evidence levels

- **CONFIRMED**: directly supported by source control flow / ownership rule that is known.
- **HIGH-CONFIDENCE**: source strongly indicates the issue, but device profiling is still required for magnitude.
- **INSUFFICIENT DATA**: do not guess; name the measurement or source needed.

## Severity

- **P0**: high-frequency hot-path cost or correctness issue that can materially affect recording/playback.
- **P1**: high-priority performance/stability issue.
- **P2**: medium priority, often feature-specific or idle-resource related.
- **P3**: nice-to-have/code quality.

## Ranking heuristic

Prioritize by:

`expected performance gain × frequency × execution cost`

## Files

- `STATE.md`: single source of truth for resume point.
- `FINDINGS.md`: cumulative issue register.
- `COVERAGE.md`: audited/not-yet-audited source map.
