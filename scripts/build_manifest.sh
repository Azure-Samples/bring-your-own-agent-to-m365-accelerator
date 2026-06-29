#!/usr/bin/env bash
# Render the Teams manifest from azd values and zip a sideloadable app package.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

All values fall back to the current azd environment when not provided.

Options:
  --app-version <version>  App version (default: 1.0.0)
  --teams-app-id <id>   Teams app ID to embed in the manifest
  --bot-id <id>         Bot Microsoft App ID (manifest bots[].botId)
  --domain <host>       App Service domain (without scheme)
  --app-uri <uri>       SSO app ID URI (manifest webApplicationInfo.resource)
  --app-id <id>         SSO app client ID (manifest webApplicationInfo.id)
  --app-name <name>     Display name  (default: app short name)
  --short-name <name>   Short name
  --full-name <name>    Full name
  --zip <filename>      Output zip filename  (default: appPackage.zip)
  -h, --help            Show this help
EOF
}

ENV_VALUES="$(azd env get-values 2>/dev/null || true)"
v() { printf '%s\n' "$ENV_VALUES" | grep "^$1=" | head -1 | cut -d= -f2- | tr -d '"' || true; }

# Defaults from azd env
APP_VERSION="1.0.0"
TEAMS_APP_ID=""
BOT_ID="$(v BOT_ID)"
DOMAIN="$(v APIM_DOMAIN)"
APP_URI="$(v SSO_APP_ID_URI)"
APP_ID="$(v SSO_APP_ID)"
SHORT_NAME=""
FULL_NAME=""
ZIP="appPackage.zip"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-version)  APP_VERSION="$2";  shift 2 ;;
    --teams-app-id) TEAMS_APP_ID="$2"; shift 2 ;;
    --bot-id)       BOT_ID="$2";       shift 2 ;;
    --domain)       DOMAIN="$2";       shift 2 ;;
    --app-uri)      APP_URI="$2";      shift 2 ;;
    --app-id)       APP_ID="$2";       shift 2 ;;
    --app-name)     APP_NAME="$2";     shift 2 ;;
    --short-name)   SHORT_NAME="$2";   shift 2 ;;
    --full-name)    FULL_NAME="$2";    shift 2 ;;
    --zip)          ZIP="$2";          shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# Derive name fields from each other when partially provided
APP_NAME="${APP_NAME:-${SHORT_NAME:-Alfred}}"
SHORT_NAME="${SHORT_NAME:-$APP_NAME}"
FULL_NAME="${FULL_NAME:-$APP_NAME}"

mkdir -p appPackage/build
sed -e "s|\${{APP_VERSION}}|$APP_VERSION|g" \
    -e "s|\${{TEAMS_APP_ID}}|$TEAMS_APP_ID|g" \
    -e "s|\${{APP_NAME}}|$APP_NAME|g" \
    -e "s|\${{APP_SHORT_NAME}}|$SHORT_NAME|g" \
    -e "s|\${{APP_FULL_NAME}}|$FULL_NAME|g" \
    -e "s|\${{BOT_ID}}|$BOT_ID|g" \
    -e "s|\${{APP_SERVICE_DOMAIN}}|$DOMAIN|g" \
    -e "s|\${{SSO_APP_ID}}|$APP_ID|g" \
    -e "s|\${{SSO_APP_ID_URI}}|$APP_URI|g" \
    appPackage/manifest.tpl.json > appPackage/build/manifest.json

cp appPackage/color.png appPackage/outline.png appPackage/build/
( cd appPackage/build && zip -q -j "$ZIP" manifest.json color.png outline.png )

echo "Wrote appPackage/build/$ZIP (name: '$SHORT_NAME') -- sideload it in Teams or M365 Copilot."
