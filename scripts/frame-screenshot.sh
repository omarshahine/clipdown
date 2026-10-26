#!/bin/bash
# Frames a window screenshot for the README: soft shadow on the icon's blue.
# usage: scripts/frame-screenshot.sh window.png framed.png
set -euo pipefail
IN=$1 OUT=$2 PAD=120
W=$(magick identify -format %w "$IN") H=$(magick identify -format %h "$IN")
magick -size $((W + 2 * PAD))x$((H + 2 * PAD)) gradient:'#6F8FF5'-'#2E4BB8' \
    \( "$IN" \( +clone -background '#0B1A4A' -shadow 45x28+0+22 \) +swap \
       -background none -layers merge +repage \) \
    -gravity center -compose over -composite \
    -resize 1400x\> -strip "$OUT"
