metadata description = 'Creates an Azure App Service plan (Linux).'

@description('App Service plan name')
param name string

@description('Region for the plan')
param location string = resourceGroup().location

@description('Optional tags')
param tags object = {}

@allowed([
  'P0v3'
  'P1v3'
  'P2v3'
  'P3v3'
  'P0v4'
  'P1v4'
  'P2v4'
  'P3v4'
])
@description('SKU name for Premium v3/v4')
param skuName string = 'P1v4'

@minValue(1)
@description('Initial instance count')
param capacity int = 1

resource appServicePlan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: name
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: skuName // ex: P0v3
    tier: contains(skuName, 'v4') ? 'PremiumV4' : 'PremiumV3'
    capacity: capacity
  }
  properties: {
    reserved: true // required for Linux
  }
}

output id string = appServicePlan.id
output name string = appServicePlan.name
output sku string = appServicePlan.sku.name
