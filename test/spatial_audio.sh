#!/bin/sh
# Smoke test for the opt-in AVSampleBuffer spatial audio output (macOS).
#
# Usage: APP=/path/to/MacLC.app/Contents/MacOS/MacLC sh test/spatial_audio.sh
#
# Exits 77 (SKIP) when APP is not set, so this can be listed in check_SCRIPTS.
# Media is generated locally (ffmpeg + a tiny bitstream generator), so no
# binary samples are shipped in the repository.
set -u
APP="${APP:-}"
if [ -z "$APP" ]; then
  echo "SKIP: set APP to the MacLC executable"
  exit 77
fi
[ -x "$APP" ] || { echo "APP is not executable: $APP" >&2; exit 2; }

TIMEOUT="${TIMEOUT:-}"
if [ -z "$TIMEOUT" ]; then
  for t in gtimeout timeout; do
    if command -v "$t" >/dev/null 2>&1; then TIMEOUT="$t"; break; fi
  done
fi
[ -n "$TIMEOUT" ] || { echo "gtimeout or timeout required" >&2; exit 2; }
command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 2; }
command -v cc >/dev/null || { echo "a C compiler is required" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
SRCDIR="$(cd "$(dirname "$0")" && pwd)"

# A silent E-AC-3 JOC (Dolby Atmos) stream, generated from the same bitstream
# construction used by the plugin's Atmos registration helper.
cc -O2 -o "$TMP/gen_joc" "$SRCDIR/generate_silent_joc.c" || exit 2
"$TMP/gen_joc" > "$TMP/silent.ec3" || exit 2
ffmpeg -v error -y -f ac3 -i "$TMP/silent.ec3" -c copy "$TMP/joc.mkv" || exit 2

ffmpeg -v error -y -f lavfi -i "sine=frequency=1000:duration=2" \
  -filter_complex "pan=5.1|c0=c0|c1=c0|c2=c0|c3=c0|c4=c0|c5=c0" \
  -c:a eac3 -b:a 384k "$TMP/eac3.mkv" || exit 2
ffmpeg -v error -y -f lavfi -i "sine=frequency=1000:duration=2" \
  -filter_complex "pan=7.1|c0=c0|c1=c0|c2=c0|c3=c0|c4=c0|c5=c0|c6=c0|c7=c0" \
  -c:a pcm_f32le "$TMP/pcm71.wav" || exit 2

run() {
  name="$1"; shift
  log="$TMP/$name.log"
  if $TIMEOUT 20s "$APP" --intf dummy -vvv --no-video \
      --aout=avsamplebuffer --run-time=2 --play-and-exit "$@" >"$log" 2>&1; then
    if check "$name" "$log"; then
      echo "PASS $name"; PASS=$((PASS+1)); return
    fi
  fi
  echo "FAIL $name (see $log)"; FAIL=$((FAIL+1))
}

check() {
  case "$1" in
    joc_passthrough)
      grep -qF 'E-AC-3 JOC/Atmos' "$2" &&
      grep -qF 'using audio decoder module "spdif"' "$2" &&
      ! grep -qF 'failed to start passthrough audio output' "$2" ;;
    eac3_passthrough)
      grep -qF 'using audio decoder module "spdif"' "$2" &&
      grep -qF 'dec3 ' "$2" &&
      ! grep -qF 'failed to start passthrough audio output' "$2" ;;
    eac3_decode)
      grep -qF 'Atmos passthrough disabled by preference' "$2" &&
      grep -qF "output 'f32l'" "$2" &&
      ! grep -qF 'using audio decoder module "spdif"' "$2" ;;
    pcm_spatial)
      grep -qF 'using standard CoreAudio layout 0x00800008' "$2" &&
      grep -qF 'format description layout tag 0x00800008' "$2" ;;
    *) return 1 ;;
  esac
}

run joc_passthrough "$TMP/joc.mkv"
run eac3_passthrough "$TMP/eac3.mkv"
run eac3_decode --no-atmos-passthrough "$TMP/eac3.mkv"
run pcm_spatial "$TMP/pcm71.wav"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
