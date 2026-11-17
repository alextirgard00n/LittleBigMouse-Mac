#!/usr/bin/env bash
#
# packaging/macos/build-app.sh — build LittleBigMouse.app and a .dmg to share.
#
# The app is self-contained: the .NET runtime is bundled, so it runs on a Mac with
# nothing installed. The hook daemon (lbm-hook) sits next to the UI inside the bundle,
# where the UI looks for it first.
#
# Usage:
#   packaging/macos/build-app.sh [--arch arm64|x64|both] [--version X.Y.Z] [--no-dmg]
#
#   --arch      arm64 = Apple Silicon, x64 = Intel (default: this Mac's architecture)
#   --version   version shown in Finder / About (default: from the latest mac-v* tag,
#               else Directory.Build.props)
#   --no-dmg    stop after the .app
#
# Output: dist/<arch>/LittleBigMouse.app and dist/LittleBigMouse-<version>-mac-<arch>.dmg
#
# Signing: ad-hoc by default (free; Gatekeeper asks once, see docs/macos.md). With an
# Apple Developer ID, set SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" to
# sign with the hardened runtime, and NOTARY_PROFILE=<keychain profile created with
# `xcrun notarytool store-credentials`> to notarize and staple the .dmg as well.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$ROOT/packaging/macos"
DIST="$ROOT/dist"
UI_PROJ="$ROOT/LittleBigMouse.Ui/LittleBigMouse.Ui.Avalonia"

ARCHES=""
VERSION=""
MAKE_DMG=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)    ARCHES="${2:-}"; shift 2 ;;
        --version) VERSION="${2:-}"; shift 2 ;;
        --no-dmg)  MAKE_DMG=0; shift ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$ARCHES" ]]; then
    [[ "$(uname -m)" == "arm64" ]] && ARCHES="arm64" || ARCHES="x64"
fi
[[ "$ARCHES" == "both" ]] && ARCHES="arm64 x64"

if [[ -z "$VERSION" ]]; then
    VERSION="$(git -C "$ROOT" describe --tags --match 'mac-v*' --abbrev=0 2>/dev/null | sed 's/^mac-v//' || true)"
    [[ -z "$VERSION" ]] && VERSION="$(grep -E '^\s*<Version>[0-9]' "$ROOT/Directory.Build.props" | head -1 | sed -E 's/.*<Version>([^<]+)<.*/\1/')"
fi
BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"

step() { echo; echo "==> $*"; }

# --- icon (once) -------------------------------------------------------------------
make_icns() {
    local out="$1" set
    set="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$set"
    for s in 16 32 128 256; do
        sips -z $s $s "$HERE/AppIcon.png" --out "$set/icon_${s}x${s}.png" >/dev/null
    done
    for s in 16 32 128; do
        sips -z $((s * 2)) $((s * 2)) "$HERE/AppIcon.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$set" -o "$out"
}

sign() {  # sign <path> [entitlements]
    if [[ -n "${SIGN_IDENTITY:-}" ]]; then
        codesign --force --timestamp --options runtime \
            --entitlements "$HERE/entitlements.plist" --sign "$SIGN_IDENTITY" "$1"
    else
        codesign --force --sign - "$1"
    fi
}

build_one() {
    local arch="$1" rid rust_target app macos
    case "$arch" in
        arm64) rid="osx-arm64"; rust_target="aarch64-apple-darwin" ;;
        x64)   rid="osx-x64";   rust_target="x86_64-apple-darwin" ;;
        *) echo "Unknown arch: $arch" >&2; exit 2 ;;
    esac

    step "[$arch] hook daemon (cargo, $rust_target)"
    (cd "$ROOT/rust" && rustup target add "$rust_target" >/dev/null)
    cargo build --release -p lbm-hook --target "$rust_target" --manifest-path "$ROOT/rust/Cargo.toml"

    step "[$arch] UI (dotnet publish, $rid, self-contained)"
    local publish="$DIST/$arch/publish"
    rm -rf "$publish"
    # -f: the UI project uses <TargetFrameworks> (plural), and publish needs exactly one.
    dotnet publish "$UI_PROJ" -c Release -f net10.0 -r "$rid" --self-contained true \
        -p:UseAppHost=true -p:SatelliteResourceLanguages=en -o "$publish"

    step "[$arch] LittleBigMouse.app"
    app="$DIST/$arch/LittleBigMouse.app"
    macos="$app/Contents/MacOS"
    rm -rf "$app"
    mkdir -p "$macos" "$app/Contents/Resources"
    cp -R "$publish/." "$macos/"
    cp "$ROOT/rust/target/$rust_target/release/lbm-hook" "$macos/lbm-hook"
    sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" "$HERE/Info.plist" >"$app/Contents/Info.plist"
    printf 'APPL????' >"$app/Contents/PkgInfo"
    make_icns "$app/Contents/Resources/AppIcon.icns"

    step "[$arch] signing (${SIGN_IDENTITY:-ad-hoc})"
    # Everything in Contents/MacOS is code to macOS, managed .dll files included
    # (they get their signature in extended attributes): sign every file first, then
    # the bundle, which seals them and signs the main executable.
    local main="$macos/LittleBigMouse.Ui.Avalonia"
    while IFS= read -r -d '' f; do
        [[ "$f" == "$main" ]] || sign "$f"
    done < <(find "$macos" -type f -print0)
    sign "$app"
    codesign --verify --deep --strict "$app" || echo "    warning: signature verification reported a problem (see above)"

    if [[ "$MAKE_DMG" -eq 1 ]]; then
        step "[$arch] disk image"
        local stage dmg="$DIST/LittleBigMouse-$VERSION-mac-$arch.dmg"
        stage="$(mktemp -d)"
        cp -R "$app" "$stage/"
        ln -s /Applications "$stage/Applications"
        rm -f "$dmg"
        hdiutil create -volname "Little Big Mouse" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null
        rm -rf "$stage"
        if [[ -n "${SIGN_IDENTITY:-}" ]]; then
            codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg"
            if [[ -n "${NOTARY_PROFILE:-}" ]]; then
                xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
                xcrun stapler staple "$dmg"
            fi
        fi
        echo "    $dmg"
    fi
    rm -rf "$publish"
}

mkdir -p "$DIST"
for arch in $ARCHES; do build_one "$arch"; done

step "Done — version $VERSION (build $BUILD)"
ls -1 "$DIST"/*.dmg 2>/dev/null || true
