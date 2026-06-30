// One bot API on an existing APIM service: validates the Bot Framework JWT (audience =
// botAppId) and forwards /api/messages to the given backend. Used once for the prod
// bot (backend = App Service) and once for the local bot (backend = dev tunnel).

param apimName string
param apiName string
param apiPath string
param botAppId string
param botBackendUrl string

resource apiManagement 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource botApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagement
  name: apiName
  properties: {
    displayName: apiName
    path: apiPath
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
    // Inline the expected audience (the bot app id) into the validate-jwt policy.
    value: replace(loadTextContent('bot-policy.xml'), '{{bot-app-id}}', botAppId)
  }
}

output messagingEndpoint string = uri('${apiManagement.properties.gatewayUrl}/', '${apiPath}/api/messages')
