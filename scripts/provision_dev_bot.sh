#!/usr/bin/env bash
# Create the dev bot app registration + secret and save them in the azd env.
set -euo pipefail

APP_NAME="m365-copilot-pro-code-dev-bot"

APP_ID="$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)"
[ -n "$APP_ID" ] || APP_ID="$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)"
az ad sp show --id "$APP_ID" >/dev/null 2>&1 || az ad sp create --id "$APP_ID" >/dev/null

SECRET="$(az ad app credential reset --id "$APP_ID" --query password -o tsv)"

azd env set DEV_BOT_APP_ID "$APP_ID"
azd env set DEV_BOT_APP_SECRET "$SECRET"
echo "DEV_BOT_APP_ID=$APP_ID saved in azd env."
