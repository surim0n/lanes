#!/usr/bin/env bash
# Render assets/banner.svg → assets/banner.png (1280×640, GitHub social-preview size) with headless Chrome.
# Works on macOS (Google Chrome) and GitHub's ubuntu runners (google-chrome / chromium preinstalled).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" google-chrome chromium chromium-browser; do
  if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then CHROME="$c"; break; fi
done
[ -n "${CHROME:-}" ] || { echo "render.sh: no Chrome/Chromium found" >&2; exit 1; }
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1280,640 \
  --screenshot="$PWD/banner.png" "file://$PWD/banner.svg" 2>/dev/null
ls -la banner.png
