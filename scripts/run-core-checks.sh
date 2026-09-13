#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir="$project_dir/.build/core-checks"
mkdir -p "$output_dir"

swiftc \
  -swift-version 6 \
  -parse-as-library \
  "$project_dir/Sources/CodexAccountSwitcher/Models.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/LocalSessionUsageScanner.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/TaskUsageAnalytics.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/WeeklyUsageNormalizer.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/AccountStore.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/SwitchRecovery.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/SwitchService.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/DesktopController.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/CodexClient.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/QuotaNotificationService.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/Localization.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/AppModel.swift" \
  "$project_dir/Checks/CoreChecks.swift" \
  -framework AppKit \
  -framework CryptoKit \
  -framework Security \
  -framework SwiftUI \
  -framework UserNotifications \
  -o "$output_dir/CoreChecks"

"$output_dir/CoreChecks"
