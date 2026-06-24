#!/usr/bin/env bash
# Smoke test only: open a local chat UI against the agent (no APIM, no SSO).
set -euo pipefail
npx -y @microsoft/m365agentsplayground -e http://localhost:3978/api/messages -c msteams
