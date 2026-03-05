param name string
param location string = resourceGroup().location
param tags object = {}
param skuName string = 'free'
@allowed([
  'disabled'
  'free'
  'standard'
])
param semanticSearch string = 'free'

resource aiSearchService 'Microsoft.Search/searchServices@2025-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    endpoint: 'https://${name}.search.windows.net'
    hostingMode: 'Default'
    computeType: 'Default'
    publicNetworkAccess: 'Enabled'
    networkRuleSet: {
      ipRules: []
      bypass: 'None'
    }
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
    disableLocalAuth: false
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    dataExfiltrationProtections: []
    semanticSearch: semanticSearch
    upgradeAvailable: 'notAvailable'
  }
}

output name string = aiSearchService.name
