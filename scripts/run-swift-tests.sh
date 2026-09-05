#!/bin/sh
set -eu

test_list=$(mktemp -t codex-switcher-tests.XXXXXX)
trap 'rm -f "$test_list"' EXIT

# SwiftPM's generated runner is a separate target. Package.swift target flags
# alone can leave canImport(Testing) false and silently execute zero tests on CLT.
swift_path=$(xcrun --find swift)
toolchain_root=$(dirname "$(dirname "$(dirname "$swift_path")")")
frameworks="$toolchain_root/Library/Developer/Frameworks"
set --
if [ -d "$frameworks/Testing.framework" ]; then
  set -- -Xswiftc -F -Xswiftc "$frameworks"
fi

swift test list --enable-swift-testing "$@" >"$test_list"

if ! grep -Fq 'CodexAccountSwitcherTests.AccountStoreTests' "$test_list"; then
  echo "Swift Testing discovered no known CodexAccountSwitcher tests." >&2
  echo "Install/select a toolchain with a working Swift Testing runner; a compiled test bundle alone is not a pass." >&2
  exit 1
fi

# These integration fixtures launch short-lived processes with tight deadlines.
# Explicitly disable Swift Testing parallelism so load does not masquerade as RPC failure.
swift test --enable-swift-testing --no-parallel "$@"
