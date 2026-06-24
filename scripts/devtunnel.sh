#!/usr/bin/env bash
# Host a persistent dev tunnel on :3978 so APIM can reach the local agent.
# Reuses the same tunnel (stable URL) and saves its endpoint in the azd env.
set -euo pipefail

PORT=3978
# Read the saved tunnel id from the azd env (empty on first run; '|| true' so a missing
# key or no-match grep does not abort the script under 'set -e -o pipefail').
TUNNEL_ID="$(azd env get-values 2>/dev/null | grep '^TUNNEL_ID=' | cut -d= -f2- | tr -d '"' || true)"
if [ -z "$TUNNEL_ID" ]; then
  CREATE_OUT="$(devtunnel create -a)"
  TUNNEL_ID="$(printf '%s\n' "$CREATE_OUT" | grep -i 'Tunnel ID' | head -1 | sed 's/.*: *//' | tr -d ' \t\r\n' || true)"
  devtunnel port create "$TUNNEL_ID" -p "$PORT" --protocol http
  azd env set TUNNEL_ID "$TUNNEL_ID"
fi

DOMAIN="${TUNNEL_ID%%.*}-${PORT}.${TUNNEL_ID#*.}.devtunnels.ms"
azd env set LOCAL_TUNNEL_ENDPOINT "https://$DOMAIN"

echo "Tunnel: https://$DOMAIN"
echo "If this URL is new, run 'azd provision' to point APIM at it."
devtunnel host "$TUNNEL_ID"