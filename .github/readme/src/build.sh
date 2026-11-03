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

# SDR to HDR demo: two copies of a Sintel frame, the right one through the Fast curve.
python3 $src/make_hdr.py $src/sintel-rooftops.jpg 2000 4.0
./gainmap base.png hdr.raw 2000 $(sips -g pixelHeight base.png | awk '/pixelHeight/{print $2}') $out/sdr-to-hdr-split.jpg

rm -rf $tmp
