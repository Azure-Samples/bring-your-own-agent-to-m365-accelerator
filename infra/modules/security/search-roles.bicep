// RBAC role assignments for AI Search
// Grants Search Index Data Contributor to the bot managed identity
// so it can create indexes and push documents, and query with user tokens.

param searchServiceName string
param principalId string
param deployerPrincipalId string = ''

var searchIndexDataContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '8ebe5a00-799e-43f5-93ac-243d3dce84a7' // Search Index Data Contributor
)

var searchServiceContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7ca78c08-252a-4471-8644-bb5ff32d4ba0' // Search Service Contributor
)

resource searchService 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: searchServiceName
}

resource searchDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: searchService
  name: guid(searchService.id, principalId, searchIndexDataContributorRoleId)
  properties: {
    principalId: principalId
    roleDefinitionId: searchIndexDataContributorRoleId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: searchService
  name: guid(searchService.id, principalId, searchServiceContributorRoleId)
  properties: {
    principalId: principalId
    roleDefinitionId: searchServiceContributorRoleId
    principalType: 'ServicePrincipal'
  }
}

// Grant the deployer (current user) access for running seed scripts
resource searchDataContributorDeployer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  scope: searchService
  name: guid(searchService.id, deployerPrincipalId, searchIndexDataContributorRoleId)
  properties: {
    principalId: deployerPrincipalId
    roleDefinitionId: searchIndexDataContributorRoleId
    principalType: 'User'
  }
}
