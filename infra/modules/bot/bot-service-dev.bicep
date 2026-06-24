// Dev bot service for the dev-tunnel local loop.
// Single-tenant app + secret (the secret is held only by the locally-running process,
// since a managed identity cannot be used from a laptop). Follows the same naming and
// shape as the prod bot (modules/bot/bot-service.bicep).

param botName string
param botDisplayName string
param messagingEndpoint string
param logAnalyticsId string
param appInsightsInstrumentationKey string

@description('Client (app) ID of the single-tenant dev bot app registration.')
param botAppId string

resource bot 'Microsoft.BotService/botServices@2022-09-15' = {
  name: botName
  location: 'global'
  kind: 'sdk'
  properties: {
    displayName: botDisplayName
    msaAppType: 'SingleTenant'
    msaAppId: botAppId
    msaAppTenantId: tenant().tenantId
    endpoint: messagingEndpoint
    developerAppInsightKey: appInsightsInstrumentationKey
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: bot
  name: 'diagnostics'
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

resource botServiceMsTeamsChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: bot
  location: 'global'
  name: 'MsTeamsChannel'
  properties: {
    channelName: 'MsTeamsChannel'
    acceptedTerms: true
    isEnabled: true
  }
}

output botName string = bot.name
