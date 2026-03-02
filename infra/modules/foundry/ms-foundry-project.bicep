param msFoundryName string
param aiProjectName string
param location string = resourceGroup().location
param tags object = {}

resource msFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: msFoundryName
}

resource aiProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  name: aiProjectName
  parent: msFoundry
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

output endpoint string = 'https://${msFoundryName}.services.ai.azure.com/api/projects/${aiProjectName}'
