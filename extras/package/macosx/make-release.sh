#!/bin/bash
# Builds the public MacLC disk image from a clean build directory, checks it,
# and writes its SHA-256 next to it.
#
# Usage: extras/package/macosx/make-release.sh [--samples DIR] [--build-dir DIR]
#
#   --samples DIR    play every file in DIR for a few seconds with the app in
#                    the image, and fail if MacLC crashes or hangs on any of
#                    them (MacLC must not be running meanwhile)
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
        --build-dir) BUILD=$(mkdir -p "$2" && cd "$2" && pwd); shift 2 ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# State the exit trap cleans up: an image is only left behind once every
# check has passed, and MacLC's preferences are put back if the smoke test
# was interrupted.
bisonwrap=
mount=
DMG=
finished=
smoke_home=
prefs_saved=
# MacLC keeps its defaults in the real preferences domain whatever HOME says:
# the smoke test saves them first and this puts back exactly what was there.
restore_prefs() {
    defaults delete org.maclc.MacLC >/dev/null 2>&1 || true
    if [ "$prefs_saved" = yes ]; then
        defaults import org.maclc.MacLC "$smoke_home/defaults.plist"
    fi
    prefs_saved=
}
cleanup() {
    if [ -n "$prefs_saved" ]; then
        restore_prefs
    fi
    if [ -n "$mount" ]; then
        hdiutil detach -quiet "$mount" 2>/dev/null || true
        rmdir "$mount" 2>/dev/null || true
    fi
    if [ -n "$DMG" ] && [ -z "$finished" ]; then
        rm -f "$DMG" "$DMG.sha256"
        echo "the disk image was removed: it did not pass every check" >&2
    fi
    if [ -n "$bisonwrap" ]; then
        rm -rf "$bisonwrap"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------- preflight
step "Checking the build machine"
[ "$(uname -s)" = Darwin ] || die "this script builds the macOS app and must run on a Mac"
[ "$(uname -m)" = arm64 ] || die "MacLC is built for Apple Silicon (arm64)"
xcrun -f metal >/dev/null 2>&1 \
    || die "the Metal toolchain is missing: xcodebuild -downloadComponent MetalToolchain"
command -v python3 >/dev/null || die "python3 is required"
automake --version 2>/dev/null | head -1 | grep -q ' 1\.18' \
    || die "automake 1.18 is required (the tree's aclocal.m4 declares it)"

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
        --enable-debug|--enable-debug=*|--disable-debug|DMGBUILD=*) ;;
        *) FLAGS+=("$flag") ;;
    esac
done
FLAGS+=(--disable-debug)
# The dmgbuild path of package-macosx leaves out the read-me files that tell
# users how to get past Gatekeeper; always make the plain image.
FLAGS+=(DMGBUILD=no)
echo "configure flags: ${FLAGS[*]}"

export PATH=/opt/homebrew/bin:$PATH
export PKG_CONFIG_PATH=$ROOT/build-deps/prefix/lib/pkgconfig:$ROOT/build-deps/pkgconfig:/opt/homebrew/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
jpeg_prefix=$(brew --prefix jpeg-turbo)
png_prefix=$(brew --prefix libpng)
export CPPFLAGS="${CPPFLAGS:-} -I$jpeg_prefix/include -I$png_prefix/include"

# A clean build generates parsers from .y files that need bison 3; macOS has
# 2.3. extras/tools builds one, but with a data directory baked into the
# binary that may no longer exist, so point it at its own.
if ! bison --version 2>/dev/null | head -1 | grep -q ' [3-9]\.'; then
    tools=$ROOT/extras/tools/build
    [ -x "$tools/bin/bison" ] \
        || die "bison 3 is required (cd extras/tools && ./bootstrap && make bison)"
    bisonwrap=$(mktemp -d)
    printf '#!/bin/sh\nBISON_PKGDATADIR="%s/share/bison" exec "%s/bin/bison" "$@"\n' \
        "$tools" "$tools" > "$bisonwrap/bison"
    chmod +x "$bisonwrap/bison"
    export PATH=$bisonwrap:$PATH
fi

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

# package-macosx makes MacLC.app from scratch (bundled libraries, ad hoc
# signature, plug-in cache) and puts it in the image with the read-me files.
step "Making MacLC.app and the disk image"
make package-macosx
APP=$BUILD/MacLC.app
DMG=$BUILD/maclc-$VERSION.dmg
[ -f "$DMG" ] || die "make package-macosx did not produce $DMG"

step "Checking MacLC.app"
codesign --verify --deep --strict "$APP"
app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[ "$app_version" = "$VERSION" ] || die "Info.plist says $app_version, expected $VERSION"
lipo -archs "$APP/Contents/MacOS/MacLC" | grep -q arm64 || die "the executable is not arm64"
echo "MacLC.app $app_version: signature valid"

# ------------------------------------------------------------- disk image
step "Checking the disk image"
hdiutil verify "$DMG"

mount=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$mount" "$DMG" >/dev/null
IMAGE_APP=$mount/MacLC.app
codesign --verify --deep --strict "$IMAGE_APP"
dmg_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$IMAGE_APP/Contents/Info.plist")
[ "$dmg_version" = "$VERSION" ] || die "the image holds MacLC $dmg_version, expected $VERSION"
for readme in "Read Me First.rtf" "Lisez-moi en premier.rtf"; do
    [ -f "$mount/$readme" ] || die "the image has no \"$readme\""
done
echo "maclc-$VERSION.dmg: MacLC $dmg_version, signature valid, read-me files present"

# -------------------------------------------------------------- smoke test
# Plays the samples with the app users get, the one in the image. A throwaway
# home keeps the media library, vlcrc and thumbnails out of the user's.
if [ -n "$SAMPLES" ]; then
    step "Playing the samples in $SAMPLES"
    if pgrep -f '/MacLC.app/Contents/MacOS/MacLC' >/dev/null; then
        die "MacLC is running: quit it first, the smoke test must not share its preferences"
    fi
    smoke_home=$(mktemp -d)
    if defaults export org.maclc.MacLC "$smoke_home/defaults.plist" 2>/dev/null; then
        prefs_saved=yes
    else
        prefs_saved=none
    fi
    reports=$HOME/Library/Logs/DiagnosticReports
    marker=$(mktemp)
    failed=0
    for media in "$SAMPLES"/*; do
        [ -f "$media" ] || continue
        HOME=$smoke_home "$IMAGE_APP/Contents/MacOS/MacLC" --play-and-exit --run-time=10 \
            --no-macosx-recentitems "$media" >/dev/null 2>&1 &
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
    restore_prefs
    rm -rf "$smoke_home"
    new_reports=$(find "$reports" -name 'MacLC*.ips' -newer "$marker" 2>/dev/null || true)
    rm -f "$marker"
    if [ -n "$new_reports" ]; then
        echo "new crash reports:"
        echo "$new_reports"
        failed=1
    fi
    [ "$failed" -eq 0 ] || die "the smoke test failed"
fi
hdiutil detach -quiet "$mount"
rmdir "$mount" 2>/dev/null || true
mount=

(cd "$BUILD" && shasum -a 256 "maclc-$VERSION.dmg" > "maclc-$VERSION.dmg.sha256")
finished=yes

step "Done"
echo "Image:    $DMG"
echo "SHA-256:  $(cut -d' ' -f1 "$DMG.sha256")"
echo "Revision: $REVISION"
