param name string
param location string = resourceGroup().location
param tags object = {}
param publisherEmail string
param publisherName string

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

output name string = apiManagement.name
