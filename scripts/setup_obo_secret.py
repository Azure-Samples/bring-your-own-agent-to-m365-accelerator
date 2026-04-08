"""
Post-provision hook: creates a client secret on the app registration
and sets it as AAD_APP_CLIENT_SECRET on the App Service.

Required for MSAL OBO exchange (SSO token -> AI Search token).
Uses azd env values: AAD_APP_CLIENT_ID, AZURE_RESOURCE_GROUP, BOT_DOMAIN.
"""

import json
import os
import subprocess
import sys


def run(cmd: str) -> str:
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Command failed: {cmd}\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def main():
    app_id = os.environ.get("AAD_APP_CLIENT_ID")
    rg = os.environ.get("AZURE_RESOURCE_GROUP")
    bot_domain = os.environ.get("BOT_DOMAIN", "")
    app_service_name = bot_domain.replace(".azurewebsites.net", "") if bot_domain else ""

    if not all([app_id, rg, app_service_name]):
        print("Missing AAD_APP_CLIENT_ID, AZURE_RESOURCE_GROUP, or BOT_DOMAIN — skipping")
        return

    # Check if secret already exists on the App Service
    settings_json = run(
        f"az webapp config appsettings list --name {app_service_name} --resource-group {rg} "
        f"--query \"[?name=='AAD_APP_CLIENT_SECRET'].value\" -o json"
    )
    existing = json.loads(settings_json)
    if existing and existing[0]:
        print("AAD_APP_CLIENT_SECRET already set — skipping")
        return

    print(f"Creating client secret on app registration {app_id}...")
    secret = run(
        f"az ad app credential reset --id {app_id} --append "
        f"--display-name OBO-AI-Search --years 1 --query password -o tsv"
    )

    print(f"Setting AAD_APP_CLIENT_SECRET and OBO_CONNECTION secret on {app_service_name}...")
    run(
        f"az webapp config appsettings set --name {app_service_name} --resource-group {rg} "
        f"--settings AAD_APP_CLIENT_SECRET={secret} "
        f"CONNECTIONS__OBO_CONNECTION__SETTINGS__CLIENTSECRET={secret} --output none"
    )

    print("Done — AAD_APP_CLIENT_SECRET configured")


if __name__ == "__main__":
    main()
