param msFoundryName string
param modelName string
param modelCapacity int
param modelVersion string

resource msFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: msFoundryName
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01'= {
  parent: msFoundry
  name: modelName
  sku : {
    capacity: modelCapacity
    name: 'GlobalStandard'
  }
  properties: {
    model:{
      name: modelName
      format: 'OpenAI'
      version: modelVersion
    }
  }
}
