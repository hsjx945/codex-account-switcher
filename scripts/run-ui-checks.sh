#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir="$project_dir/.build/ui-checks"
mkdir -p "$output_dir"
set --
for source in "$project_dir"/Sources/CodexAccountSwitcher/*.swift; do
  case "$source" in */SwitcherApp.swift) continue ;; esac
  set -- "$@" "$source"
done
swiftc -swift-version 6 -parse-as-library "$@" "$project_dir/Checks/RenderUIChecks.swift" -o "$output_dir/RenderUIChecks"
"$output_dir/RenderUIChecks" "$output_dir"
