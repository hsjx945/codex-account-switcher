#!/bin/sh
set -eu

test_list=$(mktemp -t codex-switcher-tests.XXXXXX)
trap 'rm -f "$test_list"' EXIT

swift test list --enable-swift-testing >"$test_list"

if ! grep -Fq 'CodexAccountSwitcherTests.AccountStoreTests' "$test_list"; then
  echo "Swift Testing discovered no known CodexAccountSwitcher tests." >&2
  echo "Install/select a toolchain with a working Swift Testing runner; a compiled test bundle alone is not a pass." >&2
  exit 1
fi

swift test --enable-swift-testing
