param msFoundryName string
param location string = resourceGroup().location
param tags object = {}

resource msFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: msFoundryName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  tags: tags
  properties: {
    // required to work in AI Foundry
    allowProjectManagement: true

    // Defines developer API endpoint subdomain
    customSubDomainName: msFoundryName

    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

output name string = msFoundry.name
output aoaiEndpoint string = 'https://${msFoundry.properties.customSubDomainName}.openai.azure.com/'
