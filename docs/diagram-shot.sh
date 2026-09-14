#!/usr/bin/env bash
# diagram-shot.sh <name>: docs/<name>.html -> docs/<name>.png, in the README's
# palette with the viewer chrome hidden. Keeps only the block holding the
# diagram SVG, paints the page a sentinel colour, and trims to the panel.
#
# Needs chromium and ImageMagick. Run after `archify deliver` regenerates the HTML.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
name=${1:?name}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
python3 - "$here/$name.html" "$tmp/page.html" "$here/diagram-theme.css" <<'PY'
import sys, pathlib
src, dst, css = sys.argv[1:4]
h = pathlib.Path(src).read_text()
pathlib.Path(dst).write_text(h.replace("</body>", "<style>" + pathlib.Path(css).read_text() + "</style></body>", 1))
PY
chromium --headless=new --no-sandbox --disable-gpu --hide-scrollbars --window-size=1920,1400 \
  --screenshot="$tmp/shot.png" "file://$tmp/page.html" 2>/dev/null
magick "$tmp/shot.png" -fuzz 2% -trim +repage -fill '#0d1117' -opaque '#010203' -strip "$here/$name.png"
echo "wrote docs/$name.png"
