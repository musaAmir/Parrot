#!/bin/bash
# ./build.sh [debug|release] [native|universal]
set -euo pipefail
cd "$(dirname "$0")"
CONFIG="${1:-release}"
ARCHITECTURES="${2:-native}"
case "$CONFIG" in debug) XCODE_CONFIG=Debug ;; release) XCODE_CONFIG=Release ;; *) exit 2 ;; esac
ARGS=()
case "$ARCHITECTURES" in native) ARGS+=("ARCHS=$(uname -m)") ;; universal) ARGS+=("ARCHS=arm64 x86_64") ;; *) exit 2 ;; esac
[[ -z "${VERSION:-}" ]] || ARGS+=("MARKETING_VERSION=$VERSION")
[[ -z "${BUILD_NUMBER:-}" ]] || ARGS+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
# Spotlight and Alfred should index the installed app, not Xcode products/backups.
# Keep the historical build/ path usable by release scripts through a symlink.
if [[ -d build && ! -L build ]]; then
  if [[ -e build.noindex ]]; then
    echo 'Both build/ and build.noindex/ exist; consolidate build output before building.' >&2
    exit 1
  fi
  mv build build.noindex
fi
mkdir -p build.noindex
if [[ ! -e build && ! -L build ]]; then ln -s build.noindex build; fi
if ! xcodebuild -project Parrot.xcodeproj -scheme Parrot -configuration "$XCODE_CONFIG" \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES "${ARGS[@]}" build > build/xcodebuild.log 2>&1; then
  tail -80 build/xcodebuild.log >&2
  exit 1
fi
STAGING="$(mktemp -d "$PWD/build/.Parrot.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Parrot.app"
ditto "build/DerivedData/Build/Products/$XCODE_CONFIG/Parrot.app" "$APP"
cp LICENSE "$APP/Contents/Resources/"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "$SPARKLE" ]]; then
  echo 'Sparkle was not embedded in the app.' >&2; exit 1
fi
cp build/SourcePackages/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE"
# Optional sandbox services are unused by this non-sandboxed app.
rm -rf "$SPARKLE/Versions/B/XPCServices" "$SPARKLE/XPCServices"
[[ "$CONFIG" != release ]] || strip -x "$APP/Contents/MacOS/Parrot"
# Keep the same identity across local rebuilds. Never silently fall back to ad-hoc.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" && -f .signing-identity ]]; then IDENTITY="$(cat .signing-identity)"; fi
if [[ -z "$IDENTITY" ]]; then
  echo 'Choose a stable identity with CODESIGN_IDENTITY, or save its fingerprint in .signing-identity. Use CODESIGN_IDENTITY=- only for disposable unsigned builds.' >&2
  exit 1
fi
if [[ "$IDENTITY" == - ]]; then
  SIGN_ARGS=(--force --sign - --timestamp=none)
elif [[ "$IDENTITY" == "Developer ID Application:"* ]]; then
  SIGN_ARGS=(--force --sign "$IDENTITY" --options runtime --timestamp)
else
  SIGN_ARGS=(--force --sign "$IDENTITY" --options runtime --timestamp=none)
fi
codesign "${SIGN_ARGS[@]}" "$SPARKLE/Versions/B/Autoupdate"
codesign "${SIGN_ARGS[@]}" "$SPARKLE/Versions/B/Updater.app"
codesign "${SIGN_ARGS[@]}" "$SPARKLE"
# Xcode debug builds contain a separate loadable image; sign it with the same identity.
for DYLIB in "$APP"/Contents/MacOS/*.dylib; do
  [[ ! -f "$DYLIB" ]] || codesign "${SIGN_ARGS[@]}" "$DYLIB"
done
codesign "${SIGN_ARGS[@]}" --entitlements Parrot/Parrot.entitlements "$APP"
codesign --verify --deep --strict "$APP"
rm -rf build/Parrot.app
mv "$APP" build/Parrot.app
echo "Built build/Parrot.app ($CONFIG, $ARCHITECTURES)"
