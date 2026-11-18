#!/bin/sh
# Smoke test for the AVSampleBuffer spatial audio output (macOS).
#
# Usage: APP=/path/to/MacLC.app/Contents/MacOS/MacLC sh test/spatial_audio.sh
#
# Generates its own media with ffmpeg (no binary samples in the repo), then
# asserts that:
#   - E-AC-3 is passed through compressed (spdif decoder + dec3 cookie)
#   - --no-atmos-passthrough decodes the same stream to FL32 PCM instead
#   - multichannel PCM gets a standard CoreAudio spatial layout tag
set -u
APP="${APP:-}"
TIMEOUT="${TIMEOUT:-gtimeout}"
[ -x "$APP" ] || { echo "set APP to the MacLC executable" >&2; exit 2; }
command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 2; }
command -v "$TIMEOUT" >/dev/null || { echo "$TIMEOUT required" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

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
    eac3_passthrough)
      grep -qF 'using audio decoder module "spdif"' "$2" &&
      grep -qF 'dec3 ' "$2" ;;
    eac3_decode)
      grep -qF 'Atmos passthrough disabled by preference' "$2" &&
      grep -qF "output 'f32l'" "$2" ;;
    pcm_spatial)
      grep -qF 'standard CoreAudio layout' "$2" ;;
  esac
}

run eac3_passthrough "$TMP/eac3.mkv"
run eac3_decode --no-atmos-passthrough "$TMP/eac3.mkv"
run pcm_spatial "$TMP/pcm71.wav"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
