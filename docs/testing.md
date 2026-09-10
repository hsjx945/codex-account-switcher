# Testing / 验证

Current version: **0.2.2**. Run all commands from the repository root with Swift 6.2 and macOS SDK tools.

```sh
./scripts/check-version.sh
./scripts/run-swift-tests.sh
./scripts/run-core-checks.sh
./scripts/run-ui-checks.sh
node scripts/check-site-geo.mjs
./scripts/package-local-dmg.sh
```

## Automated behavior

`run-swift-tests.sh` verifies Swift Testing discovery before running tests serially. Temporary directories and fake executables isolate account storage, RPC, login, cancellation, credential activation, encrypted rollback, startup recovery, identity mismatch, process failure and timeouts. No real credentials or signed session URLs belong in fixtures.

`run-core-checks.sh` runs standalone acceptance checks. A stale cached quota with remaining allowance must not acquire an exhaustion warning; zero allowance still does. A failure exits nonzero and blocks CI.

`run-ui-checks.sh` compiles the actual SwiftUI components and creates synthetic English/Chinese light/dark renders in `.build/ui-checks/`. It is a maintained command, not a copied `swiftc` invocation with an outdated source list. Inspect the renders for clipping and contrast. Rendering a fixture does not prove actual menu-bar navigation.

`check-version.sh` checks the source version and client identity. Packaging reads `CITATION.cff` directly and rejects a mismatched override. `check-site-geo.mjs` checks public page titles, descriptions, canonical URLs, reciprocal language links, JSON-LD versions, sitemap coverage and internal links. It does not establish indexing or traffic growth.

## Native interaction acceptance

Use synthetic profiles in an isolated app model to verify:

1. Begin browser sign-in, close and reopen the popover, and still reach Cancel Adding Account.
2. Cancel the pending login, then confirm account actions become usable again.
3. Closing an unconfirmed switch discards the selection; reopening shows the account list.
4. During a switch, presentation rebuilds retain progress from the shared model and do not start another switch.
5. English/Chinese account rows, loading/cached Token summaries and Settings remain readable.

Actual Desktop account switching is separate: it can close the task-hosting app and change live credentials. Do not use real `~/.codex` as test storage. Report a real account handoff only when observed in an explicitly authorized separate runtime.

## Package and release

Verify the exact app/DMG path printed by the scripts, bundle version, architecture, signature and checksum. Ad-hoc signing is not Apple notarization. CI reports signing mode; partial configured signing secrets fail, absent secrets create an explicitly unnotarized artifact. The release tag must identify the current remote main commit. Existing releases are preserved.

Main pushes run CI; site changes also deploy Pages. Tag pushes run release validation, tests, packaging and bilingual Release creation. Check the resulting GitHub job and live website separately from local validation.

## 中文边界

自动测试使用临时目录、合成凭据和假进程，不会证明真实账号已切换。渲染成功不等于真实菜单交互验收；本地网页检查不等于正式网站上线、搜索引擎收录或流量增长。最终结果需分别说明测试、真实运行、Git/CI、网站与 Release 状态。
