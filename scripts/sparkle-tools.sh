#!/bin/bash
# Shared paths; source this file from the release scripts.
PARROT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-com.parrot.app.sparkle}"
source "$PARROT_ROOT/scripts/build-paths.sh"
SPARKLE_TOOLS="$PARROT_ROOT/build.noindex/SourcePackages/artifacts/sparkle/Sparkle/bin"

resolve_sparkle() {
  parrot_init_build_directory "$PARROT_ROOT"
  xcodebuild -resolvePackageDependencies -project "$PARROT_ROOT/Parrot.xcodeproj" -scheme Parrot -clonedSourcePackagesDirPath "$PARROT_BUILD_ROOT/SourcePackages" >/dev/null
  if [[ ! -x "$SPARKLE_TOOLS/generate_appcast" ]]; then
    echo "Sparkle's release tools are missing from the SwiftPM artifact." >&2
    exit 1
  fi
}

check_update_key() {
  local public_key configured_key
  if ! public_key="$("$SPARKLE_TOOLS/generate_keys" --account "$SPARKLE_ACCOUNT" -p)"; then
    echo "Restore this app's existing update key from your secure backup. See docs/updates.md; do not generate a replacement for an already published app." >&2
    exit 1
  fi
  configured_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PARROT_ROOT/Parrot/Info.plist")"
  if [[ "$public_key" != "$configured_key" ]]; then
    echo "The Keychain signing key does not match Parrot/Info.plist. Do not rotate a published key accidentally." >&2
    exit 1
  fi
}
