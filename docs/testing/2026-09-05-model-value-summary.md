# Model token summary and API value

User requirements: investigate live updates; enlarge bottom summary and remove gray
text; show token totals by model; estimate their API-price equivalent.

Implemented:

- Bottom total uses full grouped digits, avoiding the old 100,000-token display
  rounding step. Existing local event polling remains one second; counters can only
  change after Codex writes usage events, not necessarily while generating a response.
- Bottom typography: 13 pt title, 20 pt total, 12 pt breakdown and status; primary
  foreground throughout. Model list is visible by default and scrolls above four rows.
- Each model has its token total and USD API equivalent. Unknown models or missing
  input/cache/output components are unpriced. Partial coverage is labeled a priced
  subtotal. Reasoning output is already included and is not charged twice.
- Standard short-context rates are a dated estimate, not actual subscription cost.
  Long-context, Fast, cache-write and tool surcharges are excluded, as stated in the
  UI help. Prices are bundled as a 2026-09-05 snapshot, not live-fetched prices.
- Quota-read failures no longer suppress token reads. Missing today's server bucket
  is labeled as not yet reported, without presenting yesterday as today's usage.

Live investigation (no credentials or private response bodies saved): both account
usage calls succeeded; latest returned daily bucket was 2026-09-04 for each. This
is the reason account-level current-day tokens are unavailable at the time of the
check. Local session events still have no reliable billing-account identity.

## Price provenance

Official model pages fetched 2026-09-05; USD per million text tokens:

| Model | Uncached input | Cached input | Output |
| --- | ---: | ---: | ---: |
| [GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra) | 10 | 1 | 50 |
| [GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol) | 4 | 0.40 | 20 |
| [GPT-5.6 Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna) | 0.20 | 0.02 | 1.20 |

Formula: (uncached input × input rate + cached input × cache rate + output × output
rate) / 1,000,000. Sol's published promotional price is available at least through
2026-11-21; refresh the dated catalog when official prices change.

## Verification

- `scripts/run-swift-tests.sh`: 93 tests / 12 suites passed, including independent
  token refresh after missing weekly quota, component pricing, unknown-model
  exclusions, and native SwiftUI rendering at 420 pt.
- Synthetic native render: `.build/model-value-fixture.png`, visually checked for
  clipping, alignment and primary text color. It is a fixture, not real usage.
- `scripts/run-core-checks.sh`: Core checks passed.
- `scripts/package-local-app.sh`: release build and strict signature check passed.
- Existing installed path replaced; previous binary preserved as
  `Codex Account Switcher.before-model-value.app`.
- Runtime PID 48530 at the existing main-worktree app path; source-built and
  installed executable SHA-256 both
  `9947dc862f3c4b3c9b85ff8f1837af603915095c01a4dd847e66234b72ac3633`.
- Native menu-only app selection still timed out. Actual menu observation is
  unverified; process identity and a synthetic render do not substitute for it.

Remaining: server-side same-day account totals are delayed; shared local token
history cannot be accurately split by account. No claim of per-account real-time
usage or actual billing is made.
