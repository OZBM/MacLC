#!/bin/bash
# Builds the public MacLC disk image from a clean build directory, checks it,
# and writes its SHA-256 next to it.
#
# Usage: extras/package/macosx/make-release.sh [--samples DIR] [--build-dir DIR]
#
#   --samples DIR    after building, play every file in DIR for a few seconds
#                    and fail if MacLC crashes on any of them
#   --build-dir DIR  where to build (default: build-release in the checkout);
#                    it is wiped first
#
# Configure flags: taken from MACLC_CONFIGURE_FLAGS if set, otherwise from the
# development build's build/config.status, with debugging turned off (assertions
# compiled out, frame pointers kept for crash reports).
#
# The app is signed ad hoc: there is no Developer ID, so users confirm the
# first launch with Open Anyway (see the README and the read-me in the image).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
BUILD=$ROOT/build-release
SAMPLES=

while [ $# -gt 0 ]; do
    case $1 in
        --samples) SAMPLES=$(cd "$2" && pwd); shift 2 ;;
        --build-dir) BUILD=$2; shift 2 ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight
step "Checking the build machine"
[ "$(uname -s)" = Darwin ] || die "this script builds the macOS app and must run on a Mac"
[ "$(uname -m)" = arm64 ] || die "MacLC is built for Apple Silicon (arm64)"
xcrun -f metal >/dev/null 2>&1 \
    || die "the Metal toolchain is missing: xcodebuild -downloadComponent MetalToolchain"
command -v python3 >/dev/null || die "python3 is required"
automake --version 2>/dev/null | head -1 | grep -q ' 1\.18' \
    || die "automake 1.18 is required (the tree's aclocal.m4 declares it)"
command -v dmgbuild >/dev/null \
    || echo "note: dmgbuild not found, the image will be a plain one (pip3 install dmgbuild)"

VERSION=$(sed -n 's/^AC_INIT(\[vlc\], \[\(.*\)\])/\1/p' "$ROOT/configure.ac")
[ -n "$VERSION" ] || die "cannot read the version from configure.ac"
REVISION=$(git -C "$ROOT" rev-parse --short HEAD)
if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]; then
    echo "warning: the checkout has uncommitted changes; the image will not match $REVISION"
fi
echo "MacLC $VERSION, revision $REVISION"

# ---------------------------------------------------------- configure flags
if [ -n "${MACLC_CONFIGURE_FLAGS:-}" ]; then
    eval "set -- $MACLC_CONFIGURE_FLAGS"
elif [ -x "$ROOT/build/config.status" ]; then
    eval "set -- $("$ROOT/build/config.status" --config)"
else
    die "no configure flags: set MACLC_CONFIGURE_FLAGS, or configure build/ once as the README describes"
fi
FLAGS=()
for flag in "$@"; do
    case $flag in
        --enable-debug|--enable-debug=*|--disable-debug) ;;
        *) FLAGS+=("$flag") ;;
    esac
done
FLAGS+=(--disable-debug)
echo "configure flags: ${FLAGS[*]}"

export PATH=/opt/homebrew/bin:$PATH
export PKG_CONFIG_PATH=$ROOT/build-deps/prefix/lib/pkgconfig:$ROOT/build-deps/pkgconfig:/opt/homebrew/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
jpeg_prefix=$(brew --prefix jpeg-turbo)
png_prefix=$(brew --prefix libpng)
export CPPFLAGS="${CPPFLAGS:-} -I$jpeg_prefix/include -I$png_prefix/include"

# ------------------------------------------------------------ dependencies
if [ ! -d "$ROOT/build-deps/prefix/lib" ]; then
    step "Building the statically linked dependencies"
    if [ ! -x "$ROOT/extras/tools/build/bin/ninja" ]; then
        (cd "$ROOT/extras/tools" && ./bootstrap && make)
    fi
    "$ROOT/extras/package/macosx/build-medialibrary.sh"
    "$ROOT/extras/package/macosx/build-taglib.sh"
    "$ROOT/extras/package/macosx/build-dvbpsi.sh"
fi

if [ ! -x "$ROOT/configure" ] || [ "$ROOT/configure.ac" -nt "$ROOT/configure" ]; then
    step "Bootstrapping"
    (cd "$ROOT" && ./bootstrap)
fi

# ------------------------------------------------------------------- build
step "Building in $BUILD"
rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$BUILD"
"$ROOT/configure" "${FLAGS[@]}"
make -j"$(sysctl -n hw.ncpu)"
make MacLC.app

APP=$BUILD/MacLC.app
step "Checking MacLC.app"
codesign --verify --deep --strict "$APP"
app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[ "$app_version" = "$VERSION" ] || die "Info.plist says $app_version, expected $VERSION"
lipo -archs "$APP/Contents/MacOS/MacLC" | grep -q arm64 || die "the executable is not arm64"
echo "MacLC.app $app_version: signature valid"

# -------------------------------------------------------------- smoke test
if [ -n "$SAMPLES" ]; then
    step "Playing the samples in $SAMPLES"
    reports=$HOME/Library/Logs/DiagnosticReports
    marker=$(mktemp)
    failed=0
    for media in "$SAMPLES"/*; do
        [ -f "$media" ] || continue
        "$APP/Contents/MacOS/MacLC" --play-and-exit --run-time=10 "$media" \
            >/dev/null 2>&1 &
        pid=$!
        for _ in $(seq 60); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 1
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            echo "HANG   $(basename "$media") (did not quit within 60 s)"
            failed=1
            continue
        fi
        status=0
        wait "$pid" || status=$?
        if [ "$status" -gt 128 ]; then
            echo "CRASH  $(basename "$media") (signal $((status - 128)))"
            failed=1
        else
            echo "ok     $(basename "$media")"
        fi
    done
    new_reports=$(find "$reports" -name 'MacLC*.ips' -newer "$marker" 2>/dev/null || true)
    rm -f "$marker"
    if [ -n "$new_reports" ]; then
        echo "new crash reports:"
        echo "$new_reports"
        failed=1
    fi
    [ "$failed" -eq 0 ] || die "the smoke test failed; the disk image was not made"
fi

# ------------------------------------------------------------- disk image
step "Making the disk image"
make package-macosx
DMG=$BUILD/maclc-$VERSION.dmg
[ -f "$DMG" ] || die "make package-macosx did not produce $DMG"
hdiutil verify "$DMG"

mount=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$mount" "$DMG" >/dev/null
trap 'hdiutil detach -quiet "$mount" 2>/dev/null || true' EXIT
codesign --verify --deep --strict "$mount/MacLC.app"
dmg_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mount/MacLC.app/Contents/Info.plist")
[ "$dmg_version" = "$VERSION" ] || die "the image holds MacLC $dmg_version, expected $VERSION"
hdiutil detach -quiet "$mount"
trap - EXIT

(cd "$BUILD" && shasum -a 256 "maclc-$VERSION.dmg" > "maclc-$VERSION.dmg.sha256")

step "Done"
echo "Image:    $DMG"
echo "SHA-256:  $(cut -d' ' -f1 "$DMG.sha256")"
echo "Revision: $REVISION"
