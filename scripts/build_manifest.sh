#!/usr/bin/env bash
# Render the Teams manifest from azd values and zip a sideloadable app package.
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_VALUES="$(azd env get-values 2>/dev/null || true)"
v() { printf '%s\n' "$ENV_VALUES" | grep "^$1=" | head -1 | cut -d= -f2- | tr -d '"'; }

# Use the dev bot when it was deployed, otherwise the prod bot.
BOT_ID="$(v DEV_BOT_ID)";              [ -n "$BOT_ID" ]  || BOT_ID="$(v BOT_ID)"
DOMAIN="$(v DEV_BOT_DOMAIN)";          [ -n "$DOMAIN" ]  || DOMAIN="$(v BOT_DOMAIN)"
APP_URI="$(v DEV_BOT_AAD_APP_ID_URI)"; [ -n "$APP_URI" ] || APP_URI="$(v AAD_APP_ID_URI)"
APP_ID="$(v AAD_APP_CLIENT_ID)"

mkdir -p appPackage/build
sed -e "s|\${{BOT_ID}}|$BOT_ID|g" \
    -e "s|\${{APP_SERVICE_DOMAIN}}|$DOMAIN|g" \
    -e "s|\${{APP_REGISTRATION_CLIENT_ID}}|$APP_ID|g" \
    -e "s|\${{APP_REGISTRATION_ID_URI}}|$APP_URI|g" \
    appPackage/manifest.tpl.json > appPackage/build/manifest.json

cp appPackage/color.png appPackage/outline.png appPackage/build/
( cd appPackage/build && zip -q -j appPackage.zip manifest.json color.png outline.png )

echo "Wrote appPackage/build/appPackage.zip (sideload it in Teams or M365 Copilot)."
