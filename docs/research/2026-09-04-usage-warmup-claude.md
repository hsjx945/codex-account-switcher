# Token statistics, warmup, and Claude research

Date: 2026-09-04

## Conclusions

- Per-account today/7-day/30-day totals can use the official Codex app-server `account/usage/read` daily buckets.
- Model names can be reconstructed from local Codex rollout JSONL. Those files do not reliably identify the ChatGPT account, so this app must present model totals as **all accounts on this Mac**, not attach them to an individual account.
- A warmup is a real inference request, not a free metadata refresh. Community implementations suggest that a minimal request can start an inactive five-hour window, but no OpenAI source found in this research guarantees that behavior.
- Claude Pro/Max quota switching should not be merged into the Codex path. There is no public subscription-quota API equivalent to the Codex app-server surface used here.

## Primary and pinned sources

- OpenAI Codex app-server documentation: <https://learn.chatgpt.com/docs/app-server>
  - `account/usage/read` provides summary and daily usage buckets for an authenticated account.
  - `model/list` provides the models available to that account.
- CodexBar at `392310c665485f8d57c93881e7416c5ebf69d8ef`: <https://github.com/steipete/CodexBar/tree/392310c665485f8d57c93881e7416c5ebf69d8ef>
  - MIT-licensed reference for local rollout scanning, cumulative-token delta accounting, model analytics, date windows, and coverage semantics.
- xjoker/codex-switch at `a3392f6155f137149f44cd3a81337d35ec6739b5`: <https://github.com/xjoker/codex-switch/tree/a3392f6155f137149f44cd3a81337d35ec6739b5>
  - MIT-licensed reference for default-off warmup, model selection, active-window skipping, caching, and retry behavior.
- Anthropic Messages Usage Report: <https://docs.anthropic.com/zh-CN/api/admin-api/usage-cost/get-messages-usage-report>
  - Organization Admin API usage, not Claude Pro/Max subscription quota.
- OpenAI organization Usage API: <https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage>
  - Organization API usage and model grouping, not ChatGPT Plus subscription usage.

## Implemented data contract

### Per-account totals

`CodexClient.readTokenActivity` reads official daily buckets and aggregates them by the user's local natural day: today, the latest 7 natural days including today, and the latest 30 natural days including today.

The result is cached alongside the account's server quota snapshot. An unavailable token endpoint does not replace a previous value with a fabricated zero.

### Local model totals

`LocalSessionUsageScanner` scans only JSONL files under the current shared Codex `sessions` and `archived_sessions` roots that were modified in the recent window. It streams files in bounded chunks and:

1. reads the current model from `turn_context.payload.model`;
2. reads cumulative `total_token_usage.total_tokens` from `event_msg/token_count`;
3. records only the positive delta, so duplicate rate-limit-only events are not double counted;
4. handles a cumulative counter reset as a new baseline;
5. aggregates today/7-day/30-day totals per model.

This is a local observation. Deleted sessions, unavailable history, future schema changes, or records without model context can reduce coverage.

## Warmup policy

The setting is disabled by default. When explicitly enabled:

1. the app checks once the configured local time has passed;
2. it skips accounts whose five-hour server window is still active;
3. it records the attempt before the request to avoid duplicate requests after a crash;
4. it asks `model/list` and prefers an available Luna, Spark, or Mini model;
5. it runs one ephemeral, read-only, no-tools Codex request;
6. it refreshes server quota after success and reports whether a future five-hour reset was actually observed.

The process has a timeout and refuses to fall back to an unverified large model. No browser cookies or private ChatGPT web endpoint are used. The UI persists the latest attempt time, model, and outcome as confirmed, unconfirmed, or failed; it states that the request is real, consumes a small amount of usage, and only **attempts** to start the window.

## Claude recommendation

Do not add Claude account switching and quota in this milestone. A later opt-in provider should keep Codex and Claude credentials, schemas, and caches isolated. The safest first slice is read-only local Claude JSONL model/token statistics. If switching is later added through an external tool such as `claude-swap`, use fixed JSON commands, strict schema validation, explicit user selection, and no automatic quota-based rotation.

## Next efficiency candidates

1. Incremental index: persist file mtime, size, parsed offset, and rolling cumulative baseline instead of rescanning recent JSONL files.
2. Statistics provenance: show complete, partial, stale-cache, and no-data states plus coverage start date.
3. Model aliases: retain raw model names while presenting a normalized family name.
4. Usage alerts: local notification for a selected remaining-percent threshold and reset time.
5. Project binding: remember a preferred account per local project, but still require a visible confirmed switch.
6. Redacted diagnostics: export identities as hashes and omit tokens, credentials, session text, and full emails.

## License boundary

The implementation was written independently against local fixtures and the official app-server contract. CodexBar and xjoker/codex-switch are pinned as research references. No source was copied from repositories without an explicit license; wwrrj/Codex-Switcher was treated as requirements-only because no clear root license was found.
