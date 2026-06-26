#!/usr/bin/env bash
# Generate the repo-root .env from the single .env.template.
#
# Everything (prod bot, local bot, its app registration, APIM, OAuth connections) is created
# by `azd provision`. This script only:
#   - mints the local bot CLIENT SECRET once (Bicep cannot output an Entra secret) and
#     caches it in the azd env as LOCAL_BOT_APP_SECRET, then
#   - renders .env from .env.template.
#
# Usage: ./scripts/gen_local_env.sh [local|smoke]
#   local (default)  real local-bot flow (Bot Service + APIM + SSO)
#   smoke            anonymous smoke test (no Bot Service / APIM / SSO)
set -euo pipefail
cd "$(dirname "$0")/.."

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

MODE="$(lower "${1:-${LOCAL_ENV_MODE:-local}}")"
case "$MODE" in
  local|dev|auto) MODE="local" ;;
  smoke) ;;
  *) echo "Unknown mode: '$MODE'. Use: local | smoke." >&2; exit 1 ;;
esac

ENV_VALUES="$(azd env get-values 2>/dev/null || true)"
v() { printf '%s\n' "$ENV_VALUES" | grep "^$1=" | head -1 | cut -d= -f2- | tr -d '"' || true; }

if [ "$MODE" = "local" ]; then
  # The local bot authenticates to Bot Service as its single-tenant app registration
  # (bot-service-local.bicep: msaAppId = the app registration's appId). The Teams manifest
  # bot id is this same app registration, so mint/auth against the app registration.
  LOCAL_BOT_APP_REG_ID="$(v LOCAL_BOT_APP_REGISTRATION_ID)"
  if [ -z "$LOCAL_BOT_APP_REG_ID" ]; then
    echo "LOCAL_BOT_APP_REGISTRATION_ID is empty. Run 'azd provision' first (it creates the local bot)," >&2
    echo "or generate an anonymous env: ./scripts/gen_local_env.sh smoke" >&2
    exit 1
  fi
  # Bicep cannot output an Entra client secret, so mint it once and cache it in the azd env.
  # (The deployer is an owner of the app via local-bot-app-registration.bicep.)
  # To rotate: azd env set LOCAL_BOT_APP_SECRET '' && ./scripts/gen_local_env.sh
  LOCAL_BOT_APP_SECRET="$(v LOCAL_BOT_APP_SECRET)"
  if [ -z "$LOCAL_BOT_APP_SECRET" ]; then
    echo "Minting local bot client secret (az ad app credential reset)..."
    LOCAL_BOT_APP_SECRET="$(az ad app credential reset --id "$LOCAL_BOT_APP_REG_ID" --query password -o tsv)"
    azd env set LOCAL_BOT_APP_SECRET "$LOCAL_BOT_APP_SECRET" >/dev/null
  fi
  AGENT_AUTH_MODE="bot"
  ANONYMOUS_ALLOWED="false"
  CONNECTIONS_CLIENTID="$LOCAL_BOT_APP_REG_ID"
  CONNECTIONS_CLIENTSECRET="$LOCAL_BOT_APP_SECRET"
  CONNECTIONS_AUTHTYPE="ClientSecret"
else
  AGENT_AUTH_MODE="anonymous"
  ANONYMOUS_ALLOWED="true"
  CONNECTIONS_CLIENTID=""
  CONNECTIONS_CLIENTSECRET=""
  CONNECTIONS_AUTHTYPE=""
fi

sed \
  -e "s|\${{AGENT_AUTH_MODE}}|$AGENT_AUTH_MODE|g" \
  -e "s|\${{ANONYMOUS_ALLOWED}}|$ANONYMOUS_ALLOWED|g" \
  -e "s|\${{CONNECTIONS_CLIENTID}}|$CONNECTIONS_CLIENTID|g" \
  -e "s|\${{CONNECTIONS_CLIENTSECRET}}|$CONNECTIONS_CLIENTSECRET|g" \
  -e "s|\${{CONNECTIONS_AUTHTYPE}}|$CONNECTIONS_AUTHTYPE|g" \
  -e "s|\${{AZURE_TENANT_ID}}|$(v AZURE_TENANT_ID)|g" \
  -e "s|\${{FOUNDRY_PROJECT_ENDPOINT}}|$(v FOUNDRY_PROJECT_ENDPOINT)|g" \
  -e "s|\${{MS_FOUNDRY_ORCHESTRATOR_MODEL_DEPLOYMENT_NAME}}|$(v MS_FOUNDRY_ORCHESTRATOR_MODEL_DEPLOYMENT_NAME)|g" \
  -e "s|\${{AZURE_SEARCH_ENDPOINT}}|$(v AZURE_SEARCH_ENDPOINT)|g" \
  -e "s|\${{AZURE_SEARCH_INDEX}}|$(v AZURE_SEARCH_INDEX)|g" \
  .env.template > .env

# Remove any stale src/.env so the repo-root .env is the one picked up by load_dotenv().
rm -f src/.env

echo "Wrote .env at repo root (mode: $MODE)."
