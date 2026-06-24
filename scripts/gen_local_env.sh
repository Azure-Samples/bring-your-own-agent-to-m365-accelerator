#!/usr/bin/env bash
# Write src/.env for the local run (dev tunnel behind APIM) from azd env values.
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_VALUES="$(azd env get-values 2>/dev/null || true)"
v() { printf '%s\n' "$ENV_VALUES" | grep "^$1=" | head -1 | cut -d= -f2- | tr -d '"'; }

LOCAL_BOT_ID="$(v LOCAL_BOT_ID)"
if [[ -z "$LOCAL_BOT_ID" ]]; then
  echo "ERROR: LOCAL_BOT_ID is empty. Run 'azd provision' first." >&2
  exit 1
fi

# The local bot client secret cannot be produced by Bicep (Entra secrets are write-only and
# Microsoft.Resources/deploymentScripts is blocked on this subscription). Mint it here with
# the developer's az identity (the deployer is an owner of the app, set in Bicep) and cache
# it in the azd env so re-running this script does not rotate the secret unnecessarily.
LOCAL_BOT_APP_SECRET="$(v LOCAL_BOT_APP_SECRET)"
if [[ -z "$LOCAL_BOT_APP_SECRET" ]]; then
  echo "Minting a client secret for the local bot app ($LOCAL_BOT_ID)..." >&2
  LOCAL_BOT_APP_SECRET="$(az ad app credential reset --id "$LOCAL_BOT_ID" --append false --display-name local-dev --years 1 --query password -o tsv 2>/dev/null || true)"
  if [[ -z "$LOCAL_BOT_APP_SECRET" ]]; then
    echo "ERROR: could not create a client secret for app $LOCAL_BOT_ID." >&2
    echo "       Ensure you are 'az login'ed as an owner of the app (the deployer) or an" >&2
    echo "       Application Administrator. To rotate later, run:" >&2
    echo "         azd env set LOCAL_BOT_APP_SECRET '' && ./scripts/gen_local_env.sh" >&2
    exit 1
  fi
  azd env set LOCAL_BOT_APP_SECRET "$LOCAL_BOT_APP_SECRET" >/dev/null
fi

cat > src/.env <<EOF
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTID=${LOCAL_BOT_ID}
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTSECRET=${LOCAL_BOT_APP_SECRET}
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__TENANTID=$(v AZURE_TENANT_ID)
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__AUTHTYPE=ClientSecret
AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__SSO__SETTINGS__AZUREBOTOAUTHCONNECTIONNAME=default_user_access_token
AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__SEARCH__SETTINGS__AZUREBOTOAUTHCONNECTIONNAME=search_access_token
CONNECTIONSMAP__0__CONNECTION=SERVICE_CONNECTION
CONNECTIONSMAP__0__SERVICEURL=*
BOT_CLIENT_ID=
MS_FOUNDRY_PROJECT_ENDPOINT=$(v FOUNDRY_PROJECT_ENDPOINT)
MS_FOUNDRY_ORCHESTRATOR_MODEL_DEPLOYMENT_NAME=$(v MS_FOUNDRY_ORCHESTRATOR_MODEL_DEPLOYMENT_NAME)
AZURE_SEARCH_ENDPOINT=$(v AZURE_SEARCH_ENDPOINT)
AZURE_SEARCH_INDEX=$(v AZURE_SEARCH_INDEX)
PORT=3978
EOF

echo "Wrote src/.env"
