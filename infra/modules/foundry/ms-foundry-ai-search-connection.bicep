param msFoundryName string
param aiProjectName string
param aiSearchName string

resource aiSearchService 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: aiSearchName
}

resource msFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: msFoundryName
}

resource msFoundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  parent: msFoundry
  name: aiProjectName
}

resource aisearch_connection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: msFoundryProject
  name: 'conn-${aiSearchName}'
  properties: {
    authType: 'AAD'
    category: 'CognitiveSearch'
    target: 'https://${aiSearchName}.search.windows.net/'
    useWorkspaceManagedIdentity: false
    isSharedToAll: false
    sharedUserList: []
    peRequirement: 'NotRequired'
    peStatus: 'NotApplicable'
    metadata: {
      displayName: aiSearchName
      type: 'azure_ai_search'
      ApiType: 'Azure'
      ResourceId: aiSearchService.id
      ApiVersion: '2024-05-01-preview'
      DeploymentApiVersion: '2023-11-01'
    }
  }
}
