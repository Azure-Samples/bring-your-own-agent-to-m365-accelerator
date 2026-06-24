#!/usr/bin/env bash
# Launch a local chat UI against the smoke-test agent (Mode A, anonymous).
# Prefers the Microsoft 365 Agents Playground, falls back to the Teams App Test Tool.
# Neither goes through APIM or SSO - this only checks the app answers on its own.
#
# Usage: ./scripts/run-test-tool.sh [endpoint]
set -euo pipefail

ENDPOINT="${1:-http://localhost:3978/api/messages}"

if command -v agentsplayground >/dev/null 2>&1; then
  exec agentsplayground -e "${ENDPOINT}" -c msteams
elif command -v teamsapptester >/dev/null 2>&1; then
  exec teamsapptester start
else
  echo "No local test UI found. Install one of:"
  echo "  npm install -g @microsoft/m365agentsplayground   # then: agentsplayground -e ${ENDPOINT} -c msteams"
  echo "  npm install -g @microsoft/teams-app-test-tool     # then: teamsapptester start"
  echo "Or run without installing: npx @microsoft/m365agentsplayground -e ${ENDPOINT} -c msteams"
  exit 1
fi
