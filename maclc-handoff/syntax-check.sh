#!/bin/sh
# Syntax-check one or more Objective-C sources from a MacLC worktree without a
# configured build directory of its own. It borrows config.h and the generated
# headers from the reference build tree, but resolves project headers against
# the worktree first.
#
#   ./syntax-check.sh modules/gui/macosx/views/Foo.m [more.m ...]
#
# Run it from the root of the worktree. Exit status 0 means every file parsed.

set -e
REFSRC=/Users/omarbenmustapha/Downloads/vlc-master
REFBUILD=$REFSRC/build
WT=$(pwd)

[ -f "$REFBUILD/config.h" ] || { echo "reference build tree missing"; exit 2; }

status=0
for f in "$@"; do
    [ -f "$f" ] || { echo "MISSING: $f"; status=1; continue; }
    if clang -fsyntax-only -x objective-c \
        -DHAVE_CONFIG_H -DMODULE_STRING=\"macosx\" -DVLC_DYNAMIC_PLUGIN \
        -D_INTL_REDIRECT_MACROS \
        -I"$WT/modules" -I"$WT/modules/gui/macosx" -I"$WT/include" \
        -I"$WT/modules/access" -I"$WT/modules/codec" -I"$WT/compat/stdbit" \
        -I"$REFBUILD" -I"$REFBUILD/include" -I"$REFBUILD/modules" \
        -fobjc-exceptions -fobjc-arc \
        -Wall -Wextra -Wno-unused-parameter -Werror=partial-availability \
        "$f" 2>&1; then
        echo "OK: $f"
    else
        echo "FAIL: $f"
        status=1
    fi
done
exit $status
