param name string
param location string = resourceGroup().location
param tags object = {}
param publisherEmail string
param publisherName string
param tenantId string
param backendBaseUrl string
param foundryBackendUrl string
param managedIdentityClientId string
param managedIdentityResourceId string
param apiPath string = 'foundry'
param allowedAudiences array
param botAppId string
param botBackendUrl string

@allowed([
  'Consumption'
  'Developer'
  'BasicV2'
])
param sku string = 'Consumption'

var apiName = 'foundry-proxy'
var botApiName = 'bot-proxy'
var openIdConfigUrl = '${environment().authentication.loginEndpoint}${tenantId}/v2.0/.well-known/openid-configuration'

resource apiManagement 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityResourceId}': {}
    }
  }
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

resource proxyApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagement
  name: apiName
  properties: {
    displayName: 'Foundry Proxy API'
    path: apiPath
    protocols: [
      'https'
    ]
    serviceUrl: backendBaseUrl
    subscriptionRequired: false
  }
}

resource proxyCatchAllOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: proxyApi
  name: 'catch-all'
  properties: {
    displayName: 'Foundry Catch-All'
    method: 'POST'
    urlTemplate: '/{*path}'
    templateParameters: [
      {
        name: 'path'
        required: true
        type: 'string'
      }
    ]
  }
}

resource proxyApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: proxyApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('foundry-policy.xml')
  }
  dependsOn: [
    namedValueOpenIdConfig
    namedValueAudienceAadAppId
    namedValueAudienceAadAppIdUri
    namedValueAudienceApiAppId
    namedValueAudienceApiAppIdUri
    namedValueIssuerV2
    namedValueIssuerV1
    namedValueManagedIdentityClientId
    namedValueFoundryBackendUrl
  ]
}

// ── Bot API (validates Bot Framework JWT, forwards to App Service /api/messages) ──

resource botApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagement
  name: botApiName
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

// ── Named Values (Foundry) ─────────────────────────────────────────────────────

resource namedValueOpenIdConfig 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apiManagement
  name: 'openid-config-url'
  properties: {
    displayName: 'openid-config-url'
    value: openIdConfigUrl
    secret: false
  }
}

resource namedValueAudienceAadAppId 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apiManagement
  name: 'audience-aad-app-id'
  properties: {
    displayName: 'audience-aad-app-id'
    value: allowedAudiences[0]
    secret: false
  }
}

resource namedValueAudienceAadAppIdUri 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apiManagement
  name: 'audience-aad-app-id-uri'
  properties: {
    displayName: 'audience-aad-app-id-uri'
    value: allowedAudiences[1]
    secret: false
  }
}

resource namedValueAudienceApiAppId 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apiManagement
  name: 'audience-api-app-id'
  properties: {
    displayName: 'audience-api-app-id'
    value: allowedAudiences[2]
    secret: false
  }
}

resource namedValueAudienceApiAppIdUri 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apiManagement
  name: 'audience-api-app-id-uri'
  properties: {
    displayName: 'audience-api-app-id-uri'
    value: allowedAudiences[3]
    secret: false
  }
}

resource namedValueIssuerV2 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apiManagement
  name: 'issuer-v2'
  properties: {
    displayName: 'issuer-v2'
    value: '${environment().authentication.loginEndpoint}${tenantId}/v2.0'
    secret: false
  }
}

resource namedValueIssuerV1 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apiManagement
  name: 'issuer-v1'
  properties: {
    displayName: 'issuer-v1'
    value: 'https://sts.windows.net/${tenantId}/'
    secret: false
  }
}

resource namedValueBackendBaseUrl 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apiManagement
  name: 'backend-base-url'
  properties: {
    displayName: 'backend-base-url'
    value: backendBaseUrl
    secret: false
  }
}

resource namedValueManagedIdentityClientId 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apiManagement
  name: 'managed-identity-client-id'
  properties: {
    displayName: 'managed-identity-client-id'
    value: managedIdentityClientId
    secret: false
  }
}

resource namedValueFoundryBackendUrl 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apiManagement
  name: 'foundry-backend-url'
  properties: {
    displayName: 'foundry-backend-url'
    value: foundryBackendUrl
    secret: false
  }
}

output name string = apiManagement.name
output proxyUrl string = 'https://${apiManagement.name}.azure-api.net/${apiPath}'
output botMessagingEndpoint string = 'https://${apiManagement.name}.azure-api.net/bot/api/messages'
