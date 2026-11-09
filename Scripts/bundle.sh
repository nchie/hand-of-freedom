#!/bin/zsh
# Builds build/Hand of Freedom.app, the menu-bar app, with its own privacy identity.
#
#   Scripts/bundle.sh                                     ad hoc signature (grants break on every rebuild)
#   HOF_IDENTITY="Hand of Freedom Dev" Scripts/bundle.sh    stable self-signed identity, see README
#   BUILD=debug Scripts/bundle.sh                         debug build, attachable with lldb
set -euo pipefail
cd "${0:A:h}/.."

CONFIG="${BUILD:-release}"
VERSION=$(git describe --tags --always --dirty 2>/dev/null || echo 0.1.0-dev)
VERSION=${VERSION#v}                  # tag v0.1.0 shows as 0.1.0
BUILD_NO=$(git rev-list --count HEAD 2>/dev/null || echo 0)
APP="build/Hand of Freedom.app"

swift build -c "$CONFIG" --product HandOfFreedom
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/HandOfFreedom" "$APP/Contents/MacOS/HandOfFreedom"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NO/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
mkdir -p "$APP/Contents/Resources/Addon"
cp -R Addon/HandOfFreedom "$APP/Contents/Resources/Addon/"

IDENTITY="${HOF_IDENTITY:--}"
ENTITLEMENTS=()
[[ "$CONFIG" == debug ]] && ENTITLEMENTS=(--entitlements Resources/debug.entitlements)
if [[ "$IDENTITY" == "-" ]]; then
    print -u2 "warning: ad hoc signature. macOS ties grants to this exact build: after a rebuild they show"
    print -u2 "         as granted but do nothing. Reset with: tccutil reset All se.nchie.handoffreedom"
fi
codesign --force --sign "$IDENTITY" --identifier se.nchie.handoffreedom "${ENTITLEMENTS[@]}" "$APP"
codesign --verify --strict "$APP"
print "Built $APP ($VERSION, build $BUILD_NO, $CONFIG)"
