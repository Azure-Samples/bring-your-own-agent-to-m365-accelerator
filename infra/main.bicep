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
@allowed(['dev', 'stg', 'prd'])
param environment string = 'dev'

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
param msFoundryLocation string = 'swedencentral'

@description('The orchestrator model to be used for chat completions')
param chatOrchestratorModel object = {
  name: 'gpt-5.4'
  capacity: 100
  version: '2026-03-05'
}

@description('Tenant ID for the Entra ID application')
param tenantId string = tenant().tenantId

@description('Base64 URL encoded Tenant ID for the Entra ID application')
param tenantIdBase64Encoded string

@description('Publisher email used for API Management metadata.')
param apimPublisherEmail string = 'apimgmt-noreply@mail.windowsazure.com'

@description('SKU used for the API Management instance.')
@allowed([
  'Consumption'
  'Developer'
  'BasicV2'
])
param apimSku string = 'BasicV2'

// ── Dev-tunnel (local development behind APIM) ──
// When localTunnelEndpoint is set, the agent runs locally and is exposed through a
// dev tunnel; APIM forwards Bot Framework traffic to the tunnel instead of the App
// Service, and the Bot Service uses a single-tenant app + secret (held only by the
// local process) instead of the managed identity. Leave empty for normal Azure deploys.
@description('Optional. Public dev tunnel base URL (e.g. https://abc-3978.euw.devtunnels.ms) used as the APIM backend for local development. Empty = use the deployed App Service.')
param localTunnelEndpoint string = ''

@description('Optional. Client (app) ID of the single-tenant dev bot app registration used for the dev-tunnel loop. Required when localTunnelEndpoint is set.')
param devBotAppId string = ''

var devTunnelMode = !empty(localTunnelEndpoint)
// Bot Framework JWT audience validated by APIM and the messaging identity of the bot.
var effectiveBotAppId = devTunnelMode ? devBotAppId : botUami.outputs.clientId
// APIM forwards to the tunnel in dev mode, otherwise to the App Service.
var apimBackendUrl = devTunnelMode ? localTunnelEndpoint : teamsAgentAppService.outputs.uri


var resourceToken = toLower(uniqueString(subscription().id, name, environment, application))
var resourceSuffix = [
  toLower(environment)
  substring(toLower(application), 0, 3)
  substring(resourceToken, 0, 8)
]
var resourceSuffixKebabcase = join(resourceSuffix, '-')
var resourceSuffixLowercase = join(resourceSuffix, '')

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

module storageAccount './modules/storage/storage-account.bicep' = {
  name: 'storageAccount'
  scope: resourceGroup
  params: {
    name: 'sto${resourceSuffixLowercase}'
    location: location
    tags: tags
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: true
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containers: [
      {
        name: 'product-data'
        publicAccess: 'None'
      }
      {
        name: 'pricing-data'
        publicAccess: 'None'
      }
    ]
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

module chatOrchestratorDeploymentModel './modules/foundry/ms-foundry-model.bicep' = {
  name: 'chatOrchestratorDeploymentModel'
  scope: resourceGroup
  params: {
    msFoundryName: msFoundry.outputs.name
    modelName: chatOrchestratorModel.name
    modelCapacity: chatOrchestratorModel.capacity
    modelVersion: chatOrchestratorModel.version
  }
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

module msFoundryAISearchConnection './modules/foundry/ms-foundry-ai-search-connection.bicep' = {
  name: 'msFoundryAISearchConnection'
  scope: resourceGroup
  params: {
    msFoundryName: msFoundry.outputs.name
    aiProjectName: msFoundryProject.outputs.name
    aiSearchName: aiSearch.outputs.name
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
      PORT: '3978'
      WEBSITES_PORT: '3978'
      // M365 Agents SDK settings (Python uses CONNECTIONS__ prefix from env)
      CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTID: botUami.outputs.clientId
      CONNECTIONS__SERVICE_CONNECTION__SETTINGS__AUTHTYPE: 'UserManagedIdentity'
      CONNECTIONS__SERVICE_CONNECTION__SETTINGS__TENANTID: tenant().tenantId
      // SSO auth handler
      AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__SSO__SETTINGS__AZUREBOTOAUTHCONNECTIONNAME: 'default_user_access_token'
      AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__SEARCH__SETTINGS__AZUREBOTOAUTHCONNECTIONNAME: 'search_access_token'
      // Foundry agent configuration (direct mode — agent-framework in-process)
      MS_FOUNDRY_PROJECT_ENDPOINT: msFoundryProject.outputs.endpoint
      MS_FOUNDRY_RESOURCE_ENDPOINT: msFoundry.outputs.aoaiEndpoint
      MS_FOUNDRY_ORCHESTRATOR_MODEL_DEPLOYMENT_NAME: chatOrchestratorModel.name
      // Connections map
      CONNECTIONSMAP__0__CONNECTION: 'SERVICE_CONNECTION'
      CONNECTIONSMAP__0__SERVICEURL: '*'
      // BOT Client ID for managed identity
      BOT_CLIENT_ID: botUami.outputs.clientId
      // AI Search (document-level access control)
      AZURE_SEARCH_ENDPOINT: 'https://${aiSearch.outputs.name}.search.windows.net'
      AZURE_SEARCH_INDEX: 'secure-docs'
    }
  }
}

module aiSearch './modules/data/ai_search.bicep' = {
  name: 'aiSearch'
  scope: resourceGroup
  params: {
    name: 'search-${resourceSuffixKebabcase}'
    location: location
    tags: tags
  }
}

// RBAC: Search Index Data Contributor + Reader for bot identity
module searchRoles './modules/security/search-roles.bicep' = {
  name: 'searchRoles'
  scope: resourceGroup
  params: {
    searchServiceName: aiSearch.outputs.name
    principalId: botUami.outputs.principalId
    deployerPrincipalId: deployer().objectId
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
    messagingEndpoint: apiManagement.outputs.botMessagingEndpoint
    logAnalyticsId: logAnalytics.outputs.id
    appInsightsInstrumentationKey: applicationInsights.outputs.instrumentationKey
    // Dev-tunnel loop: use a single-tenant app + secret instead of the managed identity,
    // so the locally-running process can authenticate outbound calls to the Bot Connector.
    useSingleTenantApp: devTunnelMode
    singleTenantAppId: devBotAppId
  }
}

module roles './modules/security/roles.bicep' = {
  name: 'roles'
  scope: resourceGroup
  params: {
    appInsightsName: applicationInsights.outputs.name
    msFoundryName: msFoundry.outputs.name
    aiSearchName: aiSearch.outputs.name
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
    searchIndexDataContributorAssignments: [
      {
        principalId: botUami.outputs.principalId
        principalType: 'ServicePrincipal'
        principalLabel: 'teams-agent'
      }
      {
        principalId: msFoundryProject.outputs.identityPrincipalId
        principalType: 'ServicePrincipal'
        principalLabel: 'ms-foundry-project-identity'
      }
      {
        principalId: deployer().objectId
        principalType: 'User'
        principalLabel: 'current-user'
      }
    ]
    searchServiceContributorAssignments: [
      {
        principalId: botUami.outputs.principalId
        principalType: 'ServicePrincipal'
        principalLabel: 'teams-agent'
      }
      {
        principalId: msFoundryProject.outputs.identityPrincipalId
        principalType: 'ServicePrincipal'
        principalLabel: 'ms-foundry-project-identity'
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
    botId: effectiveBotAppId
    tenantId: tenantId
    tenantIdBase64Encoded: tenantIdBase64Encoded
  }
}

module apiManagement './modules/apim/apim.bicep' = {
  name: 'apiManagement'
  scope: resourceGroup
  params: {
    name: apimServiceName
    location: location
    tags: tags
    publisherEmail: apimPublisherEmail
    publisherName: 'm365-copilot-pro-code-approach'
    sku: apimSku
    botAppId: effectiveBotAppId
    botBackendUrl: apimBackendUrl
  }
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

module botOAuthSearch './modules/security/bot-oauth-connection.bicep' = {
  name: 'deploy-bot-oauth-connection-search'
  scope: resourceGroup
  params: {
    botServiceName: botService.outputs.botName
    connectionName: 'search_access_token'
    aadAppId: appRegistration.outputs.aadAppId
    aadAppIdUri: appRegistration.outputs.aadAppIdUri
    federatedCredentialName: appRegistration.outputs.fciName
    scopes: 'https://search.azure.com/user_impersonation'
    tenantId: tenantId
    location: 'global'
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroup.name
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenantId

// Bot Service outputs
output BOT_ID string = effectiveBotAppId
output BOT_SERVICE_NAME string = botService.outputs.botName
output BOT_ENDPOINT string = apiManagement.outputs.botMessagingEndpoint
output BOT_DOMAIN string = replace(teamsAgentAppService.outputs.uri, 'https://', '')


// App Registration outputs
output AAD_APP_CLIENT_ID string = appRegistration.outputs.aadAppId
output AAD_APP_ID_URI string = appRegistration.outputs.aadAppIdUri
output FEDERATED_CREDENTIAL_NAME string = appRegistration.outputs.fciName

// SharePoint indexer outputs

// AI Search outputs
output AZURE_SEARCH_ENDPOINT string = 'https://${aiSearch.outputs.name}.search.windows.net'
output AZURE_SEARCH_INDEX string = 'secure-docs'

// Foundry outputs
output FOUNDRY_PROJECT_ENDPOINT string = msFoundryProject.outputs.endpoint
output MS_FOUNDRY_RESOURCE_ENDPOINT string = msFoundry.outputs.aoaiEndpoint
output MS_FOUNDRY_ORCHESTRATOR_MODEL_DEPLOYMENT_NAME string = chatOrchestratorModel.name

// Dev-tunnel (local development) outputs
output LOCAL_TUNNEL_MODE bool = devTunnelMode
output APIM_BACKEND_URL string = apimBackendUrl
