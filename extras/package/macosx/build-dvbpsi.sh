#!/bin/sh
# Builds libdvbpsi the way the macOS build expects it: a static library linked
# into the ts demux plugin, installed in build-deps/prefix of the checkout, so
# the app carries it and nobody has to install it separately.
#
# Without libdvbpsi, configure silently skips the MPEG transport stream
# demuxer, and libavformat refuses MPEG-TS unless forced: .ts, .m2ts and .mts
# files (camcorders, TV recordings, Blu-ray remuxes) and HLS streams made of
# TS segments then do not open at all.
#
# Version, checksum and patches come from the contribs (contrib/src/dvbpsi):
# the patches are the upstream bounds checks on malformed packets, which the
# release tarball lacks.
#
# Usage: extras/package/macosx/build-dvbpsi.sh
# Then configure with
#   PKG_CONFIG_PATH=<checkout>/build-deps/prefix/lib/pkgconfig:<checkout>/build-deps/pkgconfig:...
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
DEPS=$ROOT/build-deps
TARBALLS=$ROOT/contrib/tarballs
CONTRIB=$ROOT/contrib/src/dvbpsi
VERSION=$(sed -n 's/^DVBPSI_VERSION := //p' "$CONTRIB/rules.mak")
TARBALL=libdvbpsi-$VERSION.tar.bz2

mkdir -p "$TARBALLS" "$DEPS/src"
[ -f "$TARBALLS/$TARBALL" ] || curl -sSfL -o "$TARBALLS/$TARBALL" \
    "https://download.videolan.org/pub/libdvbpsi/$VERSION/$TARBALL"
expected=$(awk -v f="$TARBALL" '$2 == f {print $1}' "$CONTRIB/SHA512SUMS")
actual=$(shasum -a 512 "$TARBALLS/$TARBALL" | awk '{print $1}')
if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    echo "$TARBALL: SHA-512 mismatch" >&2
    exit 1
fi

SRC=$DEPS/src/libdvbpsi-$VERSION
rm -rf "$SRC"
tar xjf "$TARBALLS/$TARBALL" -C "$DEPS/src"

# Same patches, same order as contrib/src/dvbpsi/rules.mak.
for p in dvbpsi-noexamples.patch dvbpsi-sys-types.patch \
         0001-really-identify-duplicates.patch 0002-really-reset-packet-counter.patch \
         0001-dvbpsi_packet_push-compute-sizes-using-pointer-to-en.patch \
         0002-dvbpsi_packet_push-check-adaptation-field-length.patch \
         0003-dvbpsi_packet_push-check-section-pointers-field.patch \
         0004-dvbpsi_packet_push-check-section-length.patch; do
    patch -d "$SRC" -fp1 < "$CONTRIB/$p"
done

# The tarball's config.guess predates Apple silicon.
AUTOMAKE_DIR=$(automake --print-libdir)
cp "$AUTOMAKE_DIR/config.guess" "$AUTOMAKE_DIR/config.sub" "$SRC/.auto/" 2>/dev/null \
    || cp "$AUTOMAKE_DIR/config.guess" "$AUTOMAKE_DIR/config.sub" "$SRC/"

cd "$SRC"
./configure --prefix="$DEPS/prefix" --disable-shared --enable-static --with-pic \
    CFLAGS="-O2 -g -mmacosx-version-min=26.0"
make -j "$(sysctl -n hw.ncpu)"
make install
echo "libdvbpsi $VERSION (static) installed in $DEPS/prefix"
