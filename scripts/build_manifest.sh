#!/usr/bin/env bash
# Render appPackage/manifest.tpl.json with values from the current azd environment and
# zip a sideloadable Teams/M365 app package. Works for any azd environment, including
# the dev-tunnel one (BOT_ID then points at the dev bot app).
#
# Output: appPackage/build/appPackage.<azd-env>.zip
#
# Usage: ./scripts/build_manifest.sh
set -euo pipefail

cd "$(dirname "$0")/.."

command -v azd >/dev/null 2>&1 || { echo "ERROR: azd not found"; exit 1; }
get() { azd env get-value "$1" 2>/dev/null || true; }

BOT_ID="$(get BOT_ID)"
APP_REG_ID="$(get AAD_APP_CLIENT_ID)"
APP_REG_URI="$(get AAD_APP_ID_URI)"
APP_DOMAIN="$(get BOT_DOMAIN)"
ENV_NAME="$(get AZURE_ENV_NAME)"; ENV_NAME="${ENV_NAME:-local}"

[ -n "${BOT_ID}" ]      || { echo "ERROR: BOT_ID missing -> run 'azd provision' first"; exit 1; }
[ -n "${APP_REG_ID}" ]  || { echo "ERROR: AAD_APP_CLIENT_ID missing -> run 'azd provision' first"; exit 1; }

SRC="appPackage/manifest.tpl.json"
OUT_DIR="appPackage/build"
mkdir -p "${OUT_DIR}"

python3 - "$SRC" "${OUT_DIR}/manifest.json" "$BOT_ID" "$APP_DOMAIN" "$APP_REG_ID" "$APP_REG_URI" <<'PY'
import sys
src, dst, bot_id, domain, app_reg_id, app_reg_uri = sys.argv[1:7]
text = open(src, encoding="utf-8").read()
repl = {
    "${{BOT_ID}}": bot_id,
    "${{APP_SERVICE_DOMAIN}}": domain,
    "${{APP_REGISTRATION_CLIENT_ID}}": app_reg_id,
    "${{APP_REGISTRATION_ID_URI}}": app_reg_uri,
}
for k, v in repl.items():
    text = text.replace(k, v)
open(dst, "w", encoding="utf-8").write(text)
PY

cp appPackage/color.png appPackage/outline.png "${OUT_DIR}/"
ZIP="${OUT_DIR}/appPackage.${ENV_NAME}.zip"
rm -f "${ZIP}"
( cd "${OUT_DIR}" && zip -q -j "appPackage.${ENV_NAME}.zip" manifest.json color.png outline.png )

echo "Wrote ${ZIP}"
echo "Sideload it in Teams (Apps > Manage your apps > Upload a custom app) or M365 Copilot."
