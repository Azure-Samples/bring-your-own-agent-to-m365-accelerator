param appInsightsName string
param msFoundryName string
param aiSearchName string

// User-defined type for role assignment entries
type RoleAssignmentInput = {
  principalId: string
  principalType: string
  principalLabel: string
}

@description('Assignments for App Insights metrics publisher role')
param metricsPublisherAssignments array

@description('Assignments for OpenAI Contributor role on Azure AI Foundry')
param openAIContributorAssignments array

@description('Assignments for Azure AI User role on Azure AI Foundry')
param aiUserAssignments array

@description('Assignments for Azure AI Project Manager role on Azure AI Foundry')
param aiProjectManagerAssignments array

@description('Assignments for Search Index Data Contributor role on Azure AI Foundry')
param searchIndexDataContributorAssignments array

@description('Assignments for Search Service Contributor role on Azure AI Foundry')
param searchServiceContributorAssignments array

// https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/monitor#monitoring-metrics-publisher
var metricsPublisherRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '3913510d-42f4-4e42-8a64-420c390055eb'
)

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

// Metrics Publisher role assignments (iterable)
resource monitoringMetricsPublisherAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for assignment in metricsPublisherAssignments: if (!empty(assignment.principalId)) {
    name: guid(
      appInsights.id,
      assignment.principalId,
      metricsPublisherRoleId,
      'monitoring-metrics-publisher-${assignment.principalLabel}'
    )
    scope: appInsights
    properties: {
      roleDefinitionId: metricsPublisherRoleId
      principalId: assignment.principalId
      principalType: assignment.principalType
    }
  }
]

resource msFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: msFoundryName
}

resource aiSearch 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: aiSearchName
}

// Use Cognitive Services OpenAI Contributor for model access
var cognitiveServicesOpenAIContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'a001fd3d-188f-4b5d-821b-7da978bf7442'
)

resource msFoundryOpenAIContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for assignment in openAIContributorAssignments: if (!empty(assignment.principalId)) {
    name: guid(
      msFoundry.id,
      assignment.principalId,
      cognitiveServicesOpenAIContributorRoleId,
      'openai-contributor-${assignment.principalLabel}'
    )
    scope: msFoundry
    properties: {
      roleDefinitionId: cognitiveServicesOpenAIContributorRoleId
      principalId: assignment.principalId
      principalType: assignment.principalType
    }
  }
]

// Azure AI User role assignments (iterable)
var azureAIUserRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '53ca6127-db72-4b80-b1b0-d745d6d5456d'
)

resource msFoundryAIUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for assignment in aiUserAssignments: if (!empty(assignment.principalId)) {
    name: guid(msFoundry.id, assignment.principalId, azureAIUserRoleId, 'azure-ai-user-${assignment.principalLabel}')
    scope: msFoundry
    properties: {
      roleDefinitionId: azureAIUserRoleId
      principalId: assignment.principalId
      principalType: assignment.principalType
    }
  }
]

// Azure AI Project Manager (iterable)
var azureAIProjectManagerRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'eadc314b-1a2d-4efa-be10-5d325db5065e'
)

resource msFoundryAIProjectManagerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for assignment in aiProjectManagerAssignments: if (!empty(assignment.principalId)) {
    name: guid(
      msFoundry.id,
      assignment.principalId,
      azureAIProjectManagerRoleId,
      'azure-ai-project-manager-${assignment.principalLabel}'
    )
    scope: msFoundry
    properties: {
      roleDefinitionId: azureAIProjectManagerRoleId
      principalId: assignment.principalId
      principalType: assignment.principalType
    }
  }
]

// Search Index Data Contributor (iterable)
var searchIndexDataContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
)

resource aiSearchIndexDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for assignment in searchIndexDataContributorAssignments: if (!empty(assignment.principalId)) {
    name: guid(
      aiSearch.id,
      assignment.principalId,
      searchIndexDataContributorRoleId,
      'search-index-data-contributor-${assignment.principalLabel}'
    )
    scope: aiSearch
    properties: {
      roleDefinitionId: searchIndexDataContributorRoleId
      principalId: assignment.principalId
      principalType: assignment.principalType
    }
  }
]

// Search Service Contributor (iterable)
var searchServiceContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
)

resource aiSearchServiceContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for assignment in searchServiceContributorAssignments: if (!empty(assignment.principalId)) {
    name: guid(
      aiSearch.id,
      assignment.principalId,
      searchServiceContributorRoleId,
      'search-service-contributor-${assignment.principalLabel}'
    )
    scope: aiSearch
    properties: {
      roleDefinitionId: searchServiceContributorRoleId
      principalId: assignment.principalId
      principalType: assignment.principalType
    }
  }
]
