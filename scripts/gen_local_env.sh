#!/usr/bin/env bash
# Generate the repo-root .env from the single .env.template.
# Mode selection:
# - auto  (default): dev mode when DEPLOY_DEV_BOT=true and dev bot creds exist, else smoke mode
# - dev:   force dev mode
# - smoke: force anonymous smoke mode
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_VALUES="$(azd env get-values 2>/dev/null || true)"
v() { printf '%s\n' "$ENV_VALUES" | grep "^$1=" | head -1 | cut -d= -f2- | tr -d '"' || true; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

DEPLOY_DEV_BOT="$(lower "$(v DEPLOY_DEV_BOT)")"
DEV_BOT_APP_ID="$(v DEV_BOT_APP_ID)"
DEV_BOT_APP_SECRET="$(v DEV_BOT_APP_SECRET)"
LOCAL_ENV_MODE="$(lower "${LOCAL_ENV_MODE:-auto}")"

USE_DEV_MODE=false
if [ "$LOCAL_ENV_MODE" = "dev" ]; then
  if [ -z "$DEV_BOT_APP_ID" ] || [ -z "$DEV_BOT_APP_SECRET" ]; then
    echo "LOCAL_ENV_MODE=dev requires DEV_BOT_APP_ID and DEV_BOT_APP_SECRET in azd env."
    exit 1
  fi
  USE_DEV_MODE=true
elif [ "$LOCAL_ENV_MODE" = "smoke" ]; then
  USE_DEV_MODE=false
else
  if [ "$DEPLOY_DEV_BOT" = "true" ] && [ -n "$DEV_BOT_APP_ID" ] && [ -n "$DEV_BOT_APP_SECRET" ]; then
    USE_DEV_MODE=true
  fi
fi

if [ "$USE_DEV_MODE" = "true" ]; then
  AGENT_AUTH_MODE="bot"
  ANONYMOUS_ALLOWED="false"
  CONNECTIONS_CLIENTID="$DEV_BOT_APP_ID"
  CONNECTIONS_CLIENTSECRET="$DEV_BOT_APP_SECRET"
  CONNECTIONS_AUTHTYPE="ClientSecret"
  MODE_LABEL="dev"
else
  AGENT_AUTH_MODE="anonymous"
  ANONYMOUS_ALLOWED="true"
  CONNECTIONS_CLIENTID=""
  CONNECTIONS_CLIENTSECRET=""
  CONNECTIONS_AUTHTYPE=""
  MODE_LABEL="smoke"
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

echo "Wrote .env at repo root (mode: $MODE_LABEL)."
