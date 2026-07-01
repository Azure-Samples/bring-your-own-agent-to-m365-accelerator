#!/usr/bin/env bash
# Render the architecture Mermaid diagrams (docs/*.mmd) to PNG.
#
# The .mmd sources reference the SVG icons with relative paths (./docs/icons/...)
# so they render natively on GitHub. When rendering locally with mermaid-cli the
# page is loaded from a temp directory, so those relative paths do not resolve.
# This script inlines each icon as a base64 data URI into a temporary copy before
# rendering, leaving the source .mmd untouched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Diagrams to render (without extension).
DIAGRAMS=(
  "architecture-overview"
  "architecture-production"
  "architecture-development"
)

# Puppeteer needs --no-sandbox when Chrome headless runs inside a container.
PUPPETEER_CONFIG="$(mktemp)"
echo '{ "args": ["--no-sandbox", "--disable-setuid-sandbox"] }' > "$PUPPETEER_CONFIG"

for name in "${DIAGRAMS[@]}"; do
  src="docs/${name}.mmd"
  [[ -f "$src" ]] || { echo "skip: $src not found"; continue; }

  tmp="$(mktemp --suffix=.mmd)"
  ROOT="$ROOT" SRC="$src" TMP="$tmp" python3 - <<'PY'
import base64, os, re, pathlib
root = pathlib.Path(os.environ["ROOT"])
src = pathlib.Path(os.environ["SRC"]).read_text()
def repl(m):
    data = (root / "docs/icons" / m.group(1)).read_bytes()
    return "src='data:image/svg+xml;base64," + base64.b64encode(data).decode() + "'"
out = re.sub(r"src='\./docs/icons/([^']+)'", repl, src)
pathlib.Path(os.environ["TMP"]).write_text(out)
PY

  echo "rendering docs/${name}.png"
  mmdc -i "$tmp" -o "docs/${name}.png" -b white --scale 3 -p "$PUPPETEER_CONFIG"
  rm -f "$tmp"
done

rm -f "$PUPPETEER_CONFIG"
echo "Done."
