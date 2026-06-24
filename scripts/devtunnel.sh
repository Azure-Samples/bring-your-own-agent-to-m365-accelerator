#!/usr/bin/env bash
# Host a persistent dev tunnel on :3978 so APIM can reach the local agent.
# Reuses the same tunnel (stable URL) and saves its endpoint in the azd env.
set -euo pipefail

PORT=3978
devtunnel user login >/dev/null 2>&1 || true

TUNNEL_ID="$(azd env get-value TUNNEL_ID 2>/dev/null || true)"
if [ -z "$TUNNEL_ID" ]; then
  TUNNEL_ID="$(devtunnel create -a | grep -i "Tunnel ID" | sed "s/.*: *//" | tr -d "[:space:]")"
  devtunnel port create "$TUNNEL_ID" -p "$PORT" --protocol http
  azd env set TUNNEL_ID "$TUNNEL_ID"
fi

DOMAIN="${TUNNEL_ID%%.*}-${PORT}.${TUNNEL_ID#*.}.devtunnels.ms"
azd env set LOCAL_TUNNEL_ENDPOINT "https://$DOMAIN"

echo "Tunnel: https://$DOMAIN"
echo "If this URL is new, run 'azd provision' to point APIM at it."
devtunnel host "$TUNNEL_ID"
