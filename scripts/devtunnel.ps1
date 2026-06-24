# PowerShell backup of devtunnel.sh (bash is the primary path).
# Creates/reuses a persistent dev tunnel on port 3978 and writes LOCAL_TUNNEL_ENDPOINT
# + BOT_DOMAIN to the azd env, then hosts the tunnel.
# Usage: ./scripts/devtunnel.ps1
$ErrorActionPreference = "Stop"
$port = if ($env:PORT) { $env:PORT } else { "3978" }

foreach ($t in @("devtunnel", "azd")) {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { Write-Error "$t not found"; exit 1 }
}

devtunnel user login *> $null

$tunnelId = (azd env get-value TUNNEL_ID 2>$null)
if (-not $tunnelId -or -not (devtunnel show $tunnelId 2>$null)) {
  Write-Host "Creating a new persistent dev tunnel..."
  $out = devtunnel create
  $tunnelId = ($out | Select-String "Tunnel ID" | ForEach-Object { ($_ -split ":")[1].Trim() })
  if (-not $tunnelId) { Write-Error "could not parse tunnel id"; exit 1 }
  devtunnel port create $tunnelId -p $port | Out-Null
  devtunnel access create $tunnelId -p $port --anonymous | Out-Null
  azd env set TUNNEL_ID $tunnelId
}

$hostName = $tunnelId.Split(".")[0]
$cluster  = $tunnelId.Split(".")[1]
$domain   = "$hostName-$port.$cluster.devtunnels.ms"
$endpoint = "https://$domain"

$prev = (azd env get-value LOCAL_TUNNEL_ENDPOINT 2>$null)
azd env set LOCAL_TUNNEL_ENDPOINT $endpoint
azd env set BOT_DOMAIN $domain

Write-Host "TUNNEL_ID:             $tunnelId"
Write-Host "LOCAL_TUNNEL_ENDPOINT: $endpoint"
if ($prev -ne $endpoint) {
  Write-Host "NOTE: tunnel endpoint changed -> run 'azd provision' to update APIM backend."
}
Write-Host "Hosting tunnel (Ctrl+C to stop)..."
devtunnel host $tunnelId
