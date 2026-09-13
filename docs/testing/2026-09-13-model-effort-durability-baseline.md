# Model / effort durability baseline (2026-09-13)

This report separates local token evidence from subscription quota evidence. It
does not treat public API prices as Codex subscription billing.

## Reuse audit

Repository snapshots were checked on 2026-09-13.

| Project | License | Reusable capability | Missing for this product |
| --- | --- | --- | --- |
| [zJay26/codex-usage](https://github.com/zJay26/codex-usage) (`733df621`) | MIT | Modern response accounting, fork/task trees, SQLite incremental scanning, cache-write and Fast-mode fields | No model/effort comparison or account quota history |
| [luyh7/codex-usage-dashboard](https://github.com/luyh7/codex-usage-dashboard) (`038d577c`) | MIT | Per-session model/effort, task duration, fork-aware history, local dashboard | API-equivalent cost only; no task-to-weekly-quota attribution |
| [hashmil/codex-usage](https://github.com/hashmil/codex-usage) (`0573ab19`) | MIT | Small CLI and model/effort report | Its 30-day result was 3.46 times the fork-aware total on this history; not suitable as the authoritative counter here |
| [CodexBar](https://github.com/bcharleson/codexbar) | MIT | Current official 5-hour/weekly quota snapshot | No per-session token-to-quota attribution |

No single reviewed project closes the requested loop. The implementation keeps
the existing native scanner, adopts the proven task/fork and duration semantics,
and adds only the missing adjacent-quota-snapshot attribution layer.

## Local 30-day baseline

Window: the 30-day interval ending 2026-09-13. Source: retained local Codex
session and archived-session JSONL. The fork-aware scan found 928 sessions and
12.637 billion total tokens. The table assigns a session to its recorded primary
model/effort; mixed-model sessions are therefore an approximation at this report
level. Active duration is the sum of recorded completed-task durations, not idle
wall-clock time.

The installed native build independently found 12.707 billion tokens across 670
canonical token-bearing task streams, only 0.56% above the reused analyzer's
total. Its task count is lower because it globally deduplicates modern response
IDs and collapses copied/forked streams. The close total supports the aggregate
baseline while the native event-level model/effort attribution remains the
product's source of truth going forward.

The “work-rate index” uses one stable denominator:

`Sol-equivalent tokens = uncached input + 0.1 x cached input + 5 x output`

The 0.1 and 5 weights are Sol Medium's relative standard API token weights. This
normalizes cache-heavy histories; it is not OpenAI's unpublished quota formula.

| Model / effort | Sessions | Total tokens | Active hours | Tokens / 10 active min | Work-rate index vs Sol Medium |
| --- | ---: | ---: | ---: | ---: | ---: |
| Luna high | 64 | 313.24M | 25.7 | 2.03M | 0.55x |
| Luna xhigh | 186 | 1.392B | 54.1 | 4.29M | 1.14x |
| Luna max | 210 | 2.539B | 102.4 | 4.13M | 1.05x |
| Sol medium | 193 | 4.950B | 196.0 | 4.21M | 1.00x |
| Sol high | 128 | 707.89M | 38.3 | 3.08M | 0.84x |
| Sol xhigh | 91 | 1.882B | 82.0 | 3.82M | 0.95x |
| Astra low | 13 | 96.90M | 4.05 | 3.99M | 1.00x |
| Astra medium | 29 | 653.07M | 25.9 | 4.20M | 1.00x |
| Astra high | 1 | 11.62M | unavailable | unavailable | unavailable |

These ratios describe observed token-processing intensity, not durability. For
example, Luna xhigh processed 1.14 times the normalized work per active minute of
Sol Medium in this sample; that does not prove that it burns 1.14 times the weekly
quota.

## Available subscription evidence

The existing application cache retains only the latest official snapshot per
account, not a time series. At 2026-09-13 10:09 Japan time the two saved-account
snapshots showed 42% and 11% of their current weekly windows used. Their recent
official daily token buckets were 304.53M and 25.02M respectively, but the bucket
day and the weekly reset boundary do not align, and local session logs do not
identify the billed account. Those values cannot be divided into model multipliers
without inventing attribution.

Historical “actual weekly quota drop per task” is therefore unavailable. New
measurements become valid prospectively after the app records two official weekly
snapshots in the same reset window while the active account identity is confirmed.

## Prospective quota algorithm

For adjacent samples `S0` and `S1` in one weekly reset window:

1. `quota_drop = used_percent(S1) - used_percent(S0)`; reset transitions and
   negative changes are excluded.
2. Compute each changed session/profile's incremental Sol-equivalent tokens.
3. If exactly one session/model/effort profile changed, assign the measured drop
   directly to it.
4. If several sessions or model/effort profiles changed, allocate the drop by
   incremental work share and mark each result with `~`; allocated intervals do
   not train model multipliers.
   Legacy increments without a complete input/cache/output split also do not
   train multipliers.
5. For direct single-task intervals, calculate
   `quota points per million Sol-equivalent tokens`.
6. Divide each model/effort rate by the Sol Medium direct-sample rate. Sol Medium
   is exactly `1.00x`. Missing direct evidence remains `—`, never zero.

This produces both the requested per-task measurement and a defensible durability
multiplier while keeping measured, allocated and unavailable values distinct.
