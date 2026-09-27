#!/bin/sh
# Builds TagLib the way the macOS build expects it: a static library linked
# into the taglib plugin, installed in build-deps/prefix of the checkout, so
# the app carries it and nobody has to install it separately.
#
# TagLib is what reads the tags the media library shows: genre, track and
# disc numbers, year and the embedded artwork of MP3, M4A, FLAC, Ogg...
# Without it only title, artist and album come through (the demuxers' own
# ID3 reading).
#
# Versions and checksums come from the contribs (contrib/src/taglib and its
# header-only dependency contrib/src/utfcpp).
#
# Usage: extras/package/macosx/build-taglib.sh
# Then configure with
#   PKG_CONFIG_PATH=<checkout>/build-deps/prefix/lib/pkgconfig:<checkout>/build-deps/pkgconfig:...
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
DEPS=$ROOT/build-deps
TARBALLS=$ROOT/contrib/tarballs
TAGLIB_VERSION=$(sed -n 's/^TAGLIB_VERSION := //p' "$ROOT/contrib/src/taglib/rules.mak")
UTFCPP_VERSION=$(sed -n 's/^UTFCPP_VERSION := //p' "$ROOT/contrib/src/utfcpp/rules.mak")

# fetch <name> <tarball> <url>: download once, then check the contribs' SHA-512.
fetch() {
    [ -f "$TARBALLS/$2" ] || curl -sSfL -o "$TARBALLS/$2" "$3"
    expected=$(awk -v f="$2" '$2 == f {print $1}' "$ROOT/contrib/src/$1/SHA512SUMS")
    actual=$(shasum -a 512 "$TARBALLS/$2" | awk '{print $1}')
    if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
        echo "$2: SHA-512 mismatch" >&2
        exit 1
    fi
}

mkdir -p "$TARBALLS" "$DEPS/src"
fetch utfcpp "utfcpp-$UTFCPP_VERSION.tar.gz" \
    "https://github.com/nemtrif/utfcpp/archive/refs/tags/v$UTFCPP_VERSION.tar.gz"
fetch taglib "taglib-$TAGLIB_VERSION.tar.gz" \
    "https://github.com/taglib/taglib/releases/download/v$TAGLIB_VERSION/taglib-$TAGLIB_VERSION.tar.gz"

CMAKE_COMMON="-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$DEPS/prefix -DCMAKE_PREFIX_PATH=$DEPS/prefix
    -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF"

rm -rf "$DEPS/src/utfcpp-$UTFCPP_VERSION" "$DEPS/src/taglib-$TAGLIB_VERSION" \
       "$DEPS/utfcpp-build" "$DEPS/taglib-build"
tar xzf "$TARBALLS/utfcpp-$UTFCPP_VERSION.tar.gz" -C "$DEPS/src"
tar xzf "$TARBALLS/taglib-$TAGLIB_VERSION.tar.gz" -C "$DEPS/src"

# shellcheck disable=SC2086 # CMAKE_COMMON is a list of arguments
cmake -S "$DEPS/src/utfcpp-$UTFCPP_VERSION" -B "$DEPS/utfcpp-build" $CMAKE_COMMON \
    -DUTF8_TESTS=OFF -DUTF8_SAMPLES=OFF
cmake --install "$DEPS/utfcpp-build"

# shellcheck disable=SC2086
cmake -S "$DEPS/src/taglib-$TAGLIB_VERSION" -B "$DEPS/taglib-build" $CMAKE_COMMON \
    -DBUILD_BINDINGS=OFF -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF -DWITH_ZLIB=ON
cmake --build "$DEPS/taglib-build" -j "$(sysctl -n hw.ncpu)"
cmake --install "$DEPS/taglib-build"
echo "TagLib $TAGLIB_VERSION (static) installed in $DEPS/prefix"
