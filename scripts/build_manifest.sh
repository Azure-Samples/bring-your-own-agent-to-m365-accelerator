#!/usr/bin/env bash
# Render the Teams manifest from azd values and zip a sideloadable app package.
set -euo pipefail
cd "$(dirname "$0")/.."

v() { azd env get-value "$1" 2>/dev/null; }

mkdir -p appPackage/build
sed -e "s|\${{BOT_ID}}|$(v BOT_ID)|g" \
    -e "s|\${{APP_SERVICE_DOMAIN}}|$(v BOT_DOMAIN)|g" \
    -e "s|\${{APP_REGISTRATION_CLIENT_ID}}|$(v AAD_APP_CLIENT_ID)|g" \
    -e "s|\${{APP_REGISTRATION_ID_URI}}|$(v AAD_APP_ID_URI)|g" \
    appPackage/manifest.tpl.json > appPackage/build/manifest.json

cp appPackage/color.png appPackage/outline.png appPackage/build/
( cd appPackage/build && zip -q -j appPackage.zip manifest.json color.png outline.png )

echo "Wrote appPackage/build/appPackage.zip (sideload it in Teams or M365 Copilot)."
