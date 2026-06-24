#!/usr/bin/env bash
# Create (or reuse) a PERSISTENT dev tunnel that exposes the locally-running agent
# (port 3978) to APIM. The tunnel id is stored in the azd environment so the public
# URL stays stable across restarts. Writes LOCAL_TUNNEL_ENDPOINT + BOT_DOMAIN to the
# azd environment so `azd provision` points APIM's backend at the tunnel.
#
# Daily loop: just run this script, then `python main.py`. Re-run `azd provision`
# ONLY when LOCAL_TUNNEL_ENDPOINT changed (it usually does not, thanks to the reused id).
#
# Usage: ./scripts/devtunnel.sh
set -euo pipefail

PORT="${PORT:-3978}"

command -v devtunnel >/dev/null 2>&1 || {
  echo "ERROR: devtunnel CLI not found. Install: https://aka.ms/devtunnels/cli"; exit 1; }
command -v azd >/dev/null 2>&1 || { echo "ERROR: azd not found"; exit 1; }

devtunnel user login >/dev/null 2>&1 || true

TUNNEL_ID="$(azd env get-value TUNNEL_ID 2>/dev/null || true)"

if [ -z "${TUNNEL_ID}" ] || ! devtunnel show "${TUNNEL_ID}" >/dev/null 2>&1; then
  echo "Creating a new persistent dev tunnel..."
  CREATE_OUT="$(devtunnel create)"
  TUNNEL_ID="$(printf '%s\n' "${CREATE_OUT}" | grep -i 'Tunnel ID' | head -1 | sed 's/.*: *//' | tr -d '[:space:]')"
  [ -n "${TUNNEL_ID}" ] || { echo "ERROR: could not parse tunnel id"; exit 1; }
  devtunnel port create "${TUNNEL_ID}" -p "${PORT}" >/dev/null
  devtunnel access create "${TUNNEL_ID}" -p "${PORT}" --anonymous >/dev/null
  azd env set TUNNEL_ID "${TUNNEL_ID}"
fi

HOST="${TUNNEL_ID%%.*}"
CLUSTER="${TUNNEL_ID#*.}"
DOMAIN="${HOST}-${PORT}.${CLUSTER}.devtunnels.ms"
ENDPOINT="https://${DOMAIN}"

PREV="$(azd env get-value LOCAL_TUNNEL_ENDPOINT 2>/dev/null || true)"
azd env set LOCAL_TUNNEL_ENDPOINT "${ENDPOINT}"
azd env set BOT_DOMAIN "${DOMAIN}"

echo "TUNNEL_ID:             ${TUNNEL_ID}"
echo "LOCAL_TUNNEL_ENDPOINT: ${ENDPOINT}"
if [ "${PREV}" != "${ENDPOINT}" ]; then
  echo "NOTE: tunnel endpoint changed since last time -> run 'azd provision' to update APIM backend."
fi
echo "Hosting tunnel (Ctrl+C to stop)..."
devtunnel host "${TUNNEL_ID}"
