// API Application Registration Module
// Represents the client's API (exposed via APIM)
// Separate from the bot app registration — proper separation of concerns:
//   Bot = OAuth client, API = OAuth resource

extension microsoftGraphV1

@description('Application name for the API app registration')
param apiAppName string

@description('The bot app client ID — will be pre-authorized to call this API')
param botAppClientId string

// API Application Registration
resource apiApplication 'Microsoft.Graph/applications@v1.0' = {
  displayName: apiAppName
  uniqueName: apiAppName
  signInAudience: 'AzureADMyOrg'
  identifierUris: [
    'api://${apiAppName}'
  ]

  api: {
    requestedAccessTokenVersion: 2
    oauth2PermissionScopes: [
      {
        id: guid(resourceGroup().id, apiAppName, 'access_as_user')
        adminConsentDescription: 'Access the API on behalf of the signed-in user'
        adminConsentDisplayName: 'Access API as user'
        userConsentDescription: 'Access the API on your behalf'
        userConsentDisplayName: 'Access API as user'
        value: 'access_as_user'
        type: 'User'
        isEnabled: true
      }
    ]
    preAuthorizedApplications: [
      {
        // The bot app registration — pre-authorized so no admin consent needed
        appId: botAppClientId
        delegatedPermissionIds: [
          guid(resourceGroup().id, apiAppName, 'access_as_user')
        ]
      }
    ]
  }
}

// Service Principal for the API application
resource apiServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: apiApplication.appId
  accountEnabled: true
  displayName: apiAppName
  servicePrincipalType: 'Application'
  tags: [
    'WindowsAzureActiveDirectoryIntegratedApp'
  ]
}

output apiAppId string = apiApplication.appId
output apiAppIdUri string = 'api://${apiAppName}'
