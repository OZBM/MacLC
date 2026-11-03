#!/bin/zsh
# Rebuilds the README pictures in .github/readme/ from the sources in this folder.
# Needs Google Chrome, Python 3 with numpy and Pillow, and the Xcode command-line tools.
# After a release, add it to `rel` in make_charts.py and run this script.
set -euo pipefail
src=${0:A:h}
out=${src:h}
repo=${out:h:h}
tmp=$(mktemp -d)
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
shot() { "$chrome" --headless=new --disable-gpu --hide-scrollbars --user-data-dir=$tmp/chrome "$@" 2>/dev/null; }

cp $src/*.html $src/art-banner.jpg $src/icon.png $tmp/
cd $tmp
swiftc -O $src/gainmap.swift -o gainmap

# Charts: the SDR to HDR curve comes from the app's own header.
cc -O2 -I$repo/modules/video_output/apple -I$repo/include -o curve $src/curve.c -lm
./curve > curve.csv
python3 $src/make_charts.py curve.csv $out

# Banner: rendered with and without its text, so only the artwork gets the HDR gain map.
for name mode in bA "" bA-art notext; do
  sed "s/ART/art-banner.jpg/; s#POS#right center / auto 100%#; s/MODE/$mode/" banner.html > $name.html
  shot --force-device-scale-factor=2 --window-size=1280,440 --screenshot=$name.png "file://$tmp/$name.html"
done
python3 $src/banner_hdr.py
./gainmap banner-base.png banner-hdr.raw 2560 880 $out/banner.jpg

# Social preview (uploaded by hand in the repository settings, 1280 x 640).
sed "s/ART/art-banner.jpg/" social.html > s.html
shot --window-size=1280,640 --screenshot=s.png "file://$tmp/s.html"
sips -s format jpeg -s formatOptions 88 s.png --out $out/social-preview.jpg >/dev/null

# SDR to HDR demo, from two HDR captures of MacLC playing a still clip of sintel-rooftops.jpg
# (cropped from x = 900, scaled to 1280x872, H.264 BT.709), with SDR to HDR off and at Maximum:
# raw float32 RGBA, extended-linear Display P3, 1.0 = SDR white. Skipped unless both are given.
if [[ -n "${SPLIT_OFF:-}" && -n "${SPLIT_ON:-}" ]]; then
  python3 $src/make_split.py $SPLIT_OFF $SPLIT_ON ${SPLIT_SIZE:-1500x872} ${SPLIT_CROP:-20,20,1260,852} "MacLC SDR to HDR" 2000 > split.txt
  ./gainmap base.raw hdr.raw $(cut -d' ' -f1,2 split.txt) $out/sdr-to-hdr-split.jpg
fi

# The SDR/HDR illustration: a made-up frame rendered by Blender (about 10 minutes on an M3 Max),
# then graded for SDR and HDR. Skipped unless ILLUSTRATION is set.
if [[ -n "${ILLUSTRATION:-}" ]]; then
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P $src/hdr_scene.py -- $tmp/frame.exr 2000 834 128 >/dev/null
  python3 $src/grade_illustration.py $tmp/frame.exr 0.75 $tmp
  ./gainmap split-base.raw split-hdr.raw 2000 834 $out/hdr-illustration.jpg
fi

rm -rf $tmp
