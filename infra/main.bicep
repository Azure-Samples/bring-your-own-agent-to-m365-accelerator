targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name which is used to generate a short unique hash for each resource')
param name string

@description('The location where the resources will be created.')
@allowed([
  'eastus'
  'eastus2'
  'southcentralus'
  'swedencentral'
  'westus3'
])
param location string

@description('The environment deployed')
@allowed(['sbx', 'dev', 'stg', 'prd'])
param environment string = 'sbx'

@description('Name of the application')
param application string = 'cpl'

@description('Optional. The tags to be assigned to the created resources.')
param tags object = {
  'azd-env-name': name
  Deployment: 'bicep'
  Environment: environment
  Location: location
  Application: application
  CostControl: 'Ignore'
  SecurityControl: 'Ignore'
  Project: 'm365-copilot-pro-code-approach'
}

@description('Microsoft Foundry deployment location')
@allowed([
  'eastus2'
  'swedencentral'
])
param msFoundryLocation string = 'eastus2'

@description('The small model to be used for chat completions')
param chatSmallModel object = {
  name: 'gpt-4.1-mini'
  capacity: 2000
  version: '2025-04-14'
}

@description('The orchestrator model to be used for chat completions')
param chatOrchestratorModel object = {
  name: 'gpt-5-chat'
  capacity: 500
  version: '2025-10-03'
}

@description('Tenant ID for the Entra ID application')
param tenantId string = tenant().tenantId

@description('Base64 URL encoded Tenant ID for the Entra ID application')
param tenantIdBase64Encoded string

var resourceToken = toLower(uniqueString(subscription().id, name, environment, application))
var resourceSuffix = [
  toLower(environment)
  substring(toLower(application), 0, 3)
  substring(resourceToken, 0, 8)
]
var resourceSuffixKebabcase = join(resourceSuffix, '-')

@description('The resource group.')
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-${resourceSuffixKebabcase}'
  location: location
  tags: tags
}

module logAnalytics './modules/monitor/log.bicep' = {
  name: 'logAnalytics'
  scope: resourceGroup
  params: {
    name: 'log-${resourceSuffixKebabcase}'
    location: location
    tags: tags
  }
}

module applicationInsights './modules/monitor/application-insights.bicep' = {
  name: 'applicationInsights'
  scope: resourceGroup
  params: {
    name: 'appi-${resourceSuffixKebabcase}'
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
  }
}

module msFoundry './modules/foundry/ms-foundry.bicep' = {
  name: 'msFoundry'
  scope: resourceGroup
  params: {
    msFoundryName: 'ais-${resourceSuffixKebabcase}'
    location: msFoundryLocation
    tags: tags
  }
}

module msFoundryProject './modules/foundry/ms-foundry-project.bicep' = {
  name: 'msFoundryProject'
  scope: resourceGroup
  params: {
    msFoundryName: msFoundry.outputs.name
    aiProjectName: 'prj-${resourceSuffixKebabcase}'
    location: msFoundryLocation
    tags: tags
  }
}

module chatSmallDeploymentModel './modules/foundry/ms-foundry-model.bicep' = {
  name: 'chatSmallDeploymentModel'
  scope: resourceGroup
  params: {
    msFoundryName: msFoundry.outputs.name
    modelName: chatSmallModel.name
    modelCapacity: chatSmallModel.capacity
    modelVersion: chatSmallModel.version
  }
}

module chatOrchestratorDeploymentModel './modules/foundry/ms-foundry-model.bicep' = {
  name: 'chatOrchestratorDeploymentModel'
  scope: resourceGroup
  params: {
    msFoundryName: msFoundry.outputs.name
    modelName: chatOrchestratorModel.name
    modelCapacity: chatOrchestratorModel.capacity
    modelVersion: chatOrchestratorModel.version
  }
  dependsOn: [chatSmallDeploymentModel]
}

module aiSearch './modules/data/ai_search.bicep' = {
  name: 'aiSearch'
  scope: resourceGroup
  params: {
    name: 'srch-${resourceSuffixKebabcase}'
    location: location
    tags: tags
    skuName: 'standard'
    semanticSearch: 'standard'
  }
}

module appServicePlan './modules/host/appserviceplan.bicep' = {
  name: 'appServicePlan'
  scope: resourceGroup
  params: {
    name: 'asp-${resourceSuffixKebabcase}'
    location: location
    tags: tags
  }
}

module teamsAgentAppService './modules/host/appservice.bicep' = {
  name: 'teamsAgentAppService'
  scope: resourceGroup
  params: {
    name: 'app-teams-${resourceSuffixKebabcase}'
    location: location
    userAssignedIdentityId: botUami.outputs.id
    tags: union(tags, { 'azd-service-name': 'teams-agent' })
    applicationInsightsName: applicationInsights.outputs.name
    appServicePlanId: appServicePlan.outputs.id
    runtimeVersion: '3.13'
    runtimeName: 'python'
    appCommandLine: 'python main.py'
    scmDoBuildDuringDeployment: true
    healthCheckPath: '/health'
    appSettings: {
      CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTID: botUami.outputs.clientId
      CONNECTIONS__SERVICE_CONNECTION__SETTINGS__AUTHTYPE: 'UserManagedIdentity'
      CONNECTIONS__SERVICE_CONNECTION__SETTINGS__TENANTID: tenant().tenantId
      MS_FOUNDRY_PROJECT_ENDPOINT: msFoundryProject.outputs.endpoint
      MS_FOUNDRY_SMALL_MODEL_DEPLOYMENT_NAME: chatSmallModel.name
      MS_FOUNDRY_ORCHESTRATOR_MODEL_DEPLOYMENT_NAME: chatOrchestratorModel.name
      WEBSITES_PORT: '3978'
      PORT: '3978'
    }
  }
}

module botUami './modules/security/uami.bicep' = {
  name: 'botUami'
  scope: resourceGroup
  params: {
    name: 'bot-identity-${resourceSuffixKebabcase}'
    location: location
    tags: tags
  }
}

module botService './modules/bot/bot-service.bicep' = {
  name: 'botService'
  scope: resourceGroup
  params: {
    botName: 'bot-${resourceSuffixKebabcase}'
    botDisplayName: 'Orchestrator Agent'
    botIdentityName: botUami.outputs.name
    hostName: teamsAgentAppService.outputs.uri
    logAnalyticsId: logAnalytics.outputs.id
    appInsightsInstrumentationKey: applicationInsights.outputs.instrumentationKey
  }
}

module roles './modules/security/roles.bicep' = {
  name: 'roles'
  scope: resourceGroup
  params: {
    appInsightsName: applicationInsights.outputs.name
    msFoundryName: msFoundry.outputs.name
    // Move role assignment arrays to main and pass into module
    metricsPublisherAssignments: [
      {
        principalId: botUami.outputs.principalId
        principalType: 'ServicePrincipal'
        principalLabel: 'teams-agent'
      }
      {
        principalId: deployer().objectId
        principalType: 'User'
        principalLabel: 'current-user'
      }
    ]
    openAIContributorAssignments: [
      {
        principalId: botUami.outputs.principalId
        principalType: 'ServicePrincipal'
        principalLabel: 'teams-agent'
      }
      {
        principalId: deployer().objectId
        principalType: 'User'
        principalLabel: 'current-user'
      }
    ]
    aiUserAssignments: [
      {
        principalId: botUami.outputs.principalId
        principalType: 'ServicePrincipal'
        principalLabel: 'teams-agent'
      }
      {
        principalId: deployer().objectId
        principalType: 'User'
        principalLabel: 'current-user'
      }
    ]
    aiProjectManagerAssignments: [
      {
        principalId: botUami.outputs.principalId
        principalType: 'ServicePrincipal'
        principalLabel: 'teams-agent'
      }
      {
        principalId: deployer().objectId
        principalType: 'User'
        principalLabel: 'current-user'
      }
    ]
  }
}

// Create App Registration with all required parameters
module appRegistration './modules/security/app-registration.bicep' = {
  name: 'deploy-app-registration'
  scope: resourceGroup
  params: {
    aadAppName: 'app-reg-${resourceSuffixKebabcase}'
    botId: botUami.outputs.clientId
    tenantId: tenantId
    tenantIdBase64Encoded: tenantIdBase64Encoded
  }
  dependsOn: [
    botService
  ]
}

// Configure OAuth Connection with Azure AD v2 and Federated Credentials
module botOAuthConnection './modules/security/bot-oauth-connection.bicep' = {
  name: 'deploy-bot-oauth-connection-user'
  scope: resourceGroup
  params: {
    botServiceName: botService.outputs.botName
    connectionName: 'default_user_access_token'
    aadAppId: appRegistration.outputs.aadAppId
    aadAppIdUri: appRegistration.outputs.aadAppIdUri
    federatedCredentialName: appRegistration.outputs.fciName
    scopes: '${appRegistration.outputs.aadAppIdUri}/access_as_user'
    tenantId: tenantId
    location: 'global'
  }
}

module botOAuthConnectionmsFoundry './modules/security/bot-oauth-connection.bicep' = {
  name: 'deploy-bot-oauth-connection-ms-foundry'
  scope: resourceGroup
  params: {
    botServiceName: botService.outputs.botName
    connectionName: 'ai_foundry_access_token'
    aadAppId: appRegistration.outputs.aadAppId
    aadAppIdUri: appRegistration.outputs.aadAppIdUri
    federatedCredentialName: appRegistration.outputs.fciName
    scopes: 'https://ai.azure.com/user_impersonation'
    tenantId: tenantId
    location: 'global'
  }
}

module botOAuthCopilotStudio './modules/security/bot-oauth-connection.bicep' = {
  name: 'deploy-bot-oauth-connection-copilot-studio'
  scope: resourceGroup
  params: {
    botServiceName: botService.outputs.botName
    connectionName: 'copilot_studio_access_token'
    aadAppId: appRegistration.outputs.aadAppId
    aadAppIdUri: appRegistration.outputs.aadAppIdUri
    federatedCredentialName: appRegistration.outputs.fciName
    scopes: 'https://api.powerplatform.com/CopilotStudio.Copilots.Invoke'
    tenantId: tenantId
    location: 'global'
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroup.name
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenantId

// Bot Service outputs
output BOT_ID string = botUami.outputs.clientId
output BOT_SERVICE_NAME string = botService.outputs.botName
output BOT_ENDPOINT string = '${teamsAgentAppService.outputs.uri}/api/messages'

// App Registration outputs
output AAD_APP_CLIENT_ID string = appRegistration.outputs.aadAppId
output AAD_APP_ID_URI string = appRegistration.outputs.aadAppIdUri
output FEDERATED_CREDENTIAL_NAME string = appRegistration.outputs.fciName
