#!/bin/bash
# Assembles ClaudeUsage.app from the SwiftPM build product.
#
# SwiftPM cannot emit a bundle on its own, so this wraps the executable with an
# Info.plist and ad hoc signs it. Ad hoc signing is enough for local runs and
# keeps the keychain ACL prompt to a single approval per rebuild identity.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/ClaudeUsage.app"

cd "$ROOT"
swift build -c "$CONFIG" --product ClaudeUsage
BIN="$(swift build -c "$CONFIG" --show-bin-path)/ClaudeUsage"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeUsage"
cp "$ROOT/Config/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep \
	--sign - \
	--entitlements "$ROOT/Config/ClaudeUsage.entitlements" \
	"$APP" >/dev/null 2>&1

echo "Built $APP"
