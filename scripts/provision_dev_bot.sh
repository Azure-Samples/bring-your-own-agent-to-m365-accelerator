#!/usr/bin/env bash
# Create (or reuse) the single-tenant Entra app + secret used as the *dev bot* identity
# for the dev-tunnel-behind-APIM local loop. The secret is held only by your local
# process to authenticate outbound calls to the Bot Connector (prod uses a managed
# identity, which cannot be used from a laptop).
#
# Stores DEV_BOT_APP_ID and DEV_BOT_APP_SECRET in the current azd environment.
#
# Usage: ./scripts/provision_dev_bot.sh [app-display-name]
set -euo pipefail

APP_NAME="${1:-m365-copilot-pro-code-dev-bot}"

command -v az  >/dev/null 2>&1 || { echo "ERROR: az CLI not found"; exit 1; }
command -v azd >/dev/null 2>&1 || { echo "ERROR: azd not found"; exit 1; }

APP_ID="$(azd env get-value DEV_BOT_APP_ID 2>/dev/null || true)"
if [ -z "${APP_ID}" ] || ! az ad app show --id "${APP_ID}" >/dev/null 2>&1; then
  echo "Looking up app registration '${APP_NAME}'..."
  APP_ID="$(az ad app list --display-name "${APP_NAME}" --query '[0].appId' -o tsv 2>/dev/null || true)"
  if [ -z "${APP_ID}" ]; then
    echo "Creating single-tenant app registration '${APP_NAME}'..."
    APP_ID="$(az ad app create --display-name "${APP_NAME}" \
      --sign-in-audience AzureADMyOrg --query appId -o tsv)"
  fi
fi

# Bot Service (single-tenant) requires a service principal in the tenant.
az ad sp show --id "${APP_ID}" >/dev/null 2>&1 || az ad sp create --id "${APP_ID}" >/dev/null

echo "Resetting client secret..."
SECRET="$(az ad app credential reset --id "${APP_ID}" \
  --display-name devtunnel --years 1 --query password -o tsv)"

azd env set DEV_BOT_APP_ID "${APP_ID}"
azd env set DEV_BOT_APP_SECRET "${SECRET}"

echo "Done. DEV_BOT_APP_ID=${APP_ID} (secret stored in azd env, not printed)."
echo "Next: ./scripts/devtunnel.sh   then   azd provision"
