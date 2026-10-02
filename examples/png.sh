#!/bin/sh
# Renders examples/demo.svg and examples/monitor.svg to PNG, 1400 pixels wide,
# in light mode, with a headless Chromium:
#
#   CHROME=/path/to/chrome examples/png.sh
#
# Run examples/demo.pl first; the PNG files are what the README shows.

set -e
here=$(cd "$(dirname "$0")" && pwd)
chrome=${CHROME:-chromium}
width=1400

for name in demo monitor; do
  set -- $(sed -n 's/.*viewBox="0 0 \([0-9.]*\) \([0-9.]*\)".*/\1 \2/p' "$here/$name.svg" | head -1)
  height=$(awk "BEGIN { h = $width * $2 / $1; printf \"%d\", ( h == int(h) ? h : int(h) + 1 ) }")
  "$chrome" --headless --no-sandbox --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 --window-size="$width,$height" \
    --screenshot="$here/$name.png" "file://$here/$name.svg" >/dev/null 2>&1
  echo "$name.png ${width}x$height"
done
