param botName string
param botDisplayName string
param botIdentityName string
param messagingEndpoint string
param logAnalyticsId string
param appInsightsInstrumentationKey string

@description('When true, register the bot with a single-tenant app + secret (dev-tunnel local loop) instead of the user-assigned managed identity.')
param useSingleTenantApp bool = false

@description('Client (app) ID of the single-tenant bot app registration. Required when useSingleTenantApp is true.')
param singleTenantAppId string = ''

resource botIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: botIdentityName
}

var msiProperties = {
  msaAppType: 'UserAssignedMSI'
  msaAppMSIResourceId: botIdentity.id
  msaAppId: botIdentity.properties.clientId
  msaAppTenantId: botIdentity.properties.tenantId
}

var singleTenantProperties = {
  msaAppType: 'SingleTenant'
  msaAppId: singleTenantAppId
  msaAppTenantId: tenant().tenantId
}

resource bot 'Microsoft.BotService/botServices@2022-09-15' = {
  name: botName
  location: 'global'
  kind: 'sdk'
  properties: union(
    {
      displayName: botDisplayName
      endpoint: messagingEndpoint
      developerAppInsightKey: appInsightsInstrumentationKey
    },
    useSingleTenantApp ? singleTenantProperties : msiProperties
  )
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
