#!/bin/sh
# Builds the media library engine (libmedialibrary) the way the macOS build
# expects it: a static library linked into the medialibrary plugin, against
# the system SQLite, installed in build-deps/prefix of the checkout.
#
# Static on purpose: the plugin throws filesystem errors that libmedialibrary
# catches. Compiled into two images with hidden visibility, the two copies of
# each exception's type information never compare equal, the catch clauses
# miss, and the app aborts on the first unreadable folder. It is also what
# the contribs do.
#
# Usage: extras/package/macosx/build-medialibrary.sh
# Then configure with
#   PKG_CONFIG_PATH=<checkout>/build-deps/prefix/lib/pkgconfig:<checkout>/build-deps/pkgconfig:...
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
DEPS=$ROOT/build-deps
VERSION=$(sed -n 's/^MEDIALIBRARY_VERSION := //p' "$ROOT/contrib/src/medialibrary/rules.mak")
TARBALL=$ROOT/contrib/tarballs/medialibrary-$VERSION.tar.bz2
URL=https://code.videolan.org/videolan/medialibrary/-/archive/$VERSION/medialibrary-$VERSION.tar.bz2
MESON="python3 $ROOT/extras/tools/meson/meson.py"
NINJA=$ROOT/extras/tools/build/bin/ninja

[ -f "$TARBALL" ] || curl -sSfL -o "$TARBALL" "$URL"
expected=$(awk '{print $1}' "$ROOT/contrib/src/medialibrary/SHA512SUMS")
actual=$(shasum -a 512 "$TARBALL" | awk '{print $1}')
if [ "$expected" != "$actual" ]; then
    echo "medialibrary-$VERSION.tar.bz2: SHA-512 mismatch" >&2
    exit 1
fi

mkdir -p "$DEPS/src" "$DEPS/pkgconfig"
# The system SQLite (SDK libsqlite3.tbd) has no .pc file: describe it.
cat > "$DEPS/pkgconfig/sqlite3.pc" <<EOF
Name: SQLite
Description: macOS system SQLite
Version: $(sed -n 's/^#define SQLITE_VERSION *"\(.*\)"/\1/p' "$(xcrun --show-sdk-path)/usr/include/sqlite3.h")
Libs: -lsqlite3
Cflags:
EOF

rm -rf "$DEPS/src/medialibrary-$VERSION" "$DEPS/ml-build-static"
tar xjf "$TARBALL" -C "$DEPS/src"
cd "$DEPS/src/medialibrary-$VERSION"
export MACOSX_DEPLOYMENT_TARGET=26.0 NINJA
PKG_CONFIG_LIBDIR=$DEPS/pkgconfig PKG_CONFIG_PATH=$DEPS/pkgconfig \
    $MESON setup "$DEPS/ml-build-static" --prefix="$DEPS/prefix" \
        -Dlibvlc=disabled -Dtests=disabled -Dlibtool_workaround=true \
        --buildtype=release -Db_ndebug=true -Ddefault_library=static
"$NINJA" -C "$DEPS/ml-build-static"
$MESON install -C "$DEPS/ml-build-static"
echo "libmedialibrary $VERSION installed in $DEPS/prefix"
