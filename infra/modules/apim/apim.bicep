param name string
param location string = resourceGroup().location
param tags object = {}
param publisherEmail string
param publisherName string
param botAppId string
param botBackendUrl string

@allowed([
  'Consumption'
  'Developer'
  'BasicV2'
])
param sku string = 'Consumption'

resource apiManagement 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    capacity: sku == 'Consumption' ? 0 : 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    publicNetworkAccess: 'Enabled'
  }
}

// ── Bot API (validates Bot Framework JWT, forwards to App Service /api/messages) ──

resource botApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagement
  name: 'bot-proxy'
  properties: {
    displayName: 'Bot Proxy API'
    path: 'bot'
    protocols: [
      'https'
    ]
    serviceUrl: botBackendUrl
    subscriptionRequired: false
  }
}

resource botMessagesOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: botApi
  name: 'bot-messages'
  properties: {
    displayName: 'Bot Messages'
    method: 'POST'
    urlTemplate: '/api/messages'
  }
}

resource botApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: botApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('bot-policy.xml')
  }
  dependsOn: [
    namedValueBotAppId
  ]
}

resource namedValueBotAppId 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apiManagement
  name: 'bot-app-id'
  properties: {
    displayName: 'bot-app-id'
    value: botAppId
    secret: false
  }
}

output name string = apiManagement.name
output botMessagingEndpoint string = 'https://${apiManagement.name}.azure-api.net/bot/api/messages'
