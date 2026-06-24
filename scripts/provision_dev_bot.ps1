# PowerShell backup of provision_dev_bot.sh (bash is the primary path).
# Creates/reuses the single-tenant dev bot app + secret, stores them in the azd env.
# Usage: ./scripts/provision_dev_bot.ps1 [-AppName <name>]
param([string]$AppName = "m365-copilot-pro-code-dev-bot")
$ErrorActionPreference = "Stop"

foreach ($t in @("az", "azd")) {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { Write-Error "$t not found"; exit 1 }
}

$appId = (azd env get-value DEV_BOT_APP_ID 2>$null)
if (-not $appId -or -not (az ad app show --id $appId 2>$null)) {
  Write-Host "Looking up app registration '$AppName'..."
  $appId = (az ad app list --display-name $AppName --query "[0].appId" -o tsv 2>$null)
  if (-not $appId) {
    Write-Host "Creating single-tenant app registration '$AppName'..."
    $appId = (az ad app create --display-name $AppName --sign-in-audience AzureADMyOrg --query appId -o tsv)
  }
}

if (-not (az ad sp show --id $appId 2>$null)) { az ad sp create --id $appId | Out-Null }

Write-Host "Resetting client secret..."
$secret = (az ad app credential reset --id $appId --display-name devtunnel --years 1 --query password -o tsv)

azd env set DEV_BOT_APP_ID $appId
azd env set DEV_BOT_APP_SECRET $secret
Write-Host "Done. DEV_BOT_APP_ID=$appId (secret stored in azd env, not printed)."
Write-Host "Next: ./scripts/devtunnel.ps1   then   azd provision"
