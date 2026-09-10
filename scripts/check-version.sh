#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
version=$(sed -n 's/^version: //p' CITATION.cff)
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo 'Invalid semantic version in CITATION.cff' >&2
  exit 1
fi
client_version=$(sed -n 's/^[[:space:]]*"version": "\([^"]*\)",$/\1/p' Sources/CodexAccountSwitcher/CodexClient.swift)
if [ "$client_version" != "$version" ]; then
  echo "Client version $client_version differs from CITATION.cff $version" >&2
  exit 1
fi
for document in README.md README.zh-CN.md .github/release-notes.md; do
  if ! grep -Fq "$version" "$document"; then
    echo "$document does not describe release $version" >&2
    exit 1
  fi
done
printf 'Release version: %s\n' "$version"
