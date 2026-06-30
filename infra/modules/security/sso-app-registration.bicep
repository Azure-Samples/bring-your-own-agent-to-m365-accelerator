// SSO (user authorization) App Registration Module
// Required Role: Application Administrator or Cloud Application Administrator
// Deploys: the Entra app registration used for USER authentication/SSO (federated
// credential + access_as_user), its service principal, and OAuth settings.
//
// Two-identity model (see docs/LOCAL_DEVELOPMENT.md):
//   • BOT app  : the bot's Microsoft App ID (msaAppId). Prod = user-assigned managed
//                identity; local = modules/security/local-bot-app-registration.bicep.
//                Goes into the Teams manifest as bots[].botId.
//   • SSO app  : THIS app. Its Application (client) ID is the Teams manifest
//                webApplicationInfo.id. Instantiated once PER ENVIRONMENT (a prod SSO app
//                and a dedicated local SSO app), each fronting that environment's bot.
//
// Naming follows the M365 Agents Toolkit ProxyAgent sample: the SSO app's client id is
// SSO_APP_ID and its Application ID URI is SSO_APP_ID_URI. Note the URI value is
// api://botid-<botAppId> (it embeds the BOT's app id, not the SSO app's), and is used as
// webApplicationInfo.resource and the OAuth connection's Token Exchange URL.

extension microsoftGraphV1

@description('Display/unique name for the SSO (user authorization) app registration.')
param ssoAppName string

@description('Bot Microsoft App ID this SSO app fronts. Builds the SSO Application ID URI (api://botid-<botAppId>).')
param botAppId string

@description('Tenant ID where the application will be registered')
param tenantId string

@description('Base64 URL encoded Tenant ID for the Entra ID application')
param tenantIdBase64Encoded string

// SSO Application ID URI. Value is api://botid-<botAppId> so it identifies the BOT the
// token is exchanged for, even though it is exposed by this SSO app.
var ssoAppIdUri = 'api://botid-${botAppId}'

// Microsoft Entra ID Application Registration
// Note: identifierUris cannot be set on initial creation with appId reference
// Note: Retdirect URIs might vary based on your bot configuration
// Note: List of redirect URL : https://learn.microsoft.com/en-us/microsoft-365/agents-sdk/azure-bot-user-authorization-federated-credentials#create-the-microsoft-entra-id-identity-provider
resource ssoApplication 'Microsoft.Graph/applications@v1.0' = {
  displayName: ssoAppName
  uniqueName: ssoAppName
  signInAudience: 'AzureADMyOrg'
  identifierUris: [
    ssoAppIdUri
  ]
  web: {
    redirectUris: [
      'https://token.botframework.com/.auth/web/redirect'
    ]
    implicitGrantSettings: {
      enableIdTokenIssuance: false
      enableAccessTokenIssuance: false
    }
  }

  api: {
    requestedAccessTokenVersion: 2
    oauth2PermissionScopes: [
      {
        id: guid(resourceGroup().id, ssoAppName, 'access_as_user')
        adminConsentDescription: 'Default scope for Agent SSO access'
        adminConsentDisplayName: 'Agent SSO'
        userConsentDescription: 'Default scope for Agent SSO access'
        userConsentDisplayName: 'Agent SSO'
        value: 'access_as_user'
        type: 'User'
        isEnabled: true
      }
    ]
    preAuthorizedApplications: [
      {
        // Teams web client
        appId: '1fec8e78-bce4-4aaf-ab1b-5451cc387264'
        delegatedPermissionIds: [
          guid(resourceGroup().id, ssoAppName, 'access_as_user')
        ]
      }
      {
        // Teams desktop client
        appId: '5e3ce6c0-2b1f-4285-8d4b-75ee78787346'
        delegatedPermissionIds: [
          guid(resourceGroup().id, ssoAppName, 'access_as_user')
        ]
      }
      {
        // Microsoft 365 web application
        appId: '4765445b-32c6-49b0-83e6-1d93765276ca'
        delegatedPermissionIds: [
          guid(resourceGroup().id, ssoAppName, 'access_as_user')
        ]
      }
      {
        // Microsoft 365 desktop application
        appId: '0ec893e0-5785-4de6-99da-4ed124e5296c'
        delegatedPermissionIds: [
          guid(resourceGroup().id, ssoAppName, 'access_as_user')
        ]
      }
      {
        // Microsoft 365 mobile application Outlook desktop application
        appId: 'd3590ed6-52b3-4102-aeff-aad2292ab01c'
        delegatedPermissionIds: [
          guid(resourceGroup().id, ssoAppName, 'access_as_user')
        ]
      }
      {
        // Outlook web application
        appId: 'bc59ab01-8403-45c6-8796-ac3ef710b3e3'
        delegatedPermissionIds: [
          guid(resourceGroup().id, ssoAppName, 'access_as_user')
        ]
      }
      {
        // Outlook mobile application
        appId: '27922004-5251-4030-b22d-91ecd9a37ea4'
        delegatedPermissionIds: [
          guid(resourceGroup().id, ssoAppName, 'access_as_user')
        ]
      }
    ]
  }

  requiredResourceAccess: [
    {
      // OpenID permissions & offline_access
      resourceAppId: '00000003-0000-0000-c000-000000000000'
      resourceAccess: [
        {
          // openid
          id: '37f7f235-527c-4136-accd-4a02d197296e'
          type: 'Scope'
        }
        {
          // profile
          id: '14dad69e-099b-42c9-810b-d002981feec1'
          type: 'Scope'
        }
        {
          // email
          id: '64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0'
          type: 'Scope'
        }
        {
          // offline_access
          id: '7427e0e9-2fba-42fe-b0c0-848c9e6a8182'
          type: 'Scope'
        }
      ]
    }
    {
      // Azure Machine Learning Services
      // Required for Azure AI foundry agent SSO
      resourceAppId: '18a66f5f-dbdf-4c17-9dd7-1634712a9cbe'
      resourceAccess: [
        {
          // user_impersonation
          id: '1a7925b5-f871-417a-9b8b-303f9f29fa10'
          type: 'Scope'
        }
      ]
    }
    {
      // Power Platform API
      // Required for Copilot Studio agents
      resourceAppId: '8578e004-a5c6-46e7-913e-12f58912df43'
      resourceAccess: [
        {
          // CopilotStudio.Copilots.Invoke
          id: '204440d3-c1d0-4826-b570-99eb6f5e2aeb'
          type: 'Scope'
        }
      ]
    }
    {
      // Azure Cognitive Search — for per-user document ACL filtering
      resourceAppId: '880da380-985e-4198-81b9-e05b1cc53158'
      resourceAccess: [
        {
          // user_impersonation
          id: 'a4165a31-5d9e-4120-bd1e-9d88c66fd3b8'
          type: 'Scope'
        }
      ]
    }
  ]
}

// Construct federated credential subject
// appId encode value is the Bot Service one. it is hardcoded on purpose.
// 9ExAW52n_ky4ZiS_jhpJIQ is a fixed value that represents the Microsoft service principal that performs token exchange using the federated credential
// https://learn.microsoft.com/en-us/azure/bot-service/bot-builder-authentication-federated-credential?view=azure-bot-service-4.0&tabs=csharp
var federatedCredentialSubject = '/eid1/c/pub/t/${tenantIdBase64Encoded}/a/9ExAW52n_ky4ZiS_jhpJIQ/${guid(resourceGroup().id, ssoAppName, 'BotServiceOauthConnection')}'

// Federated Identity Credential for Bot Framework token exchange
// This must be a separate resource as it's a child resource type
resource federatedCredential 'Microsoft.Graph/applications/federatedIdentityCredentials@v1.0' = {
  name: '${ssoApplication.uniqueName}/${guid(resourceGroup().id, ssoAppName, 'BotServiceOauthConnection')}'
  audiences: [
    'api://AzureADTokenExchange'
  ]
  issuer: '${environment().authentication.loginEndpoint}${tenantId}/v2.0'
  subject: federatedCredentialSubject
  description: 'Federated credential for Bot Framework token exchange'
}

// Service Principal for the application
resource ssoServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: ssoApplication.appId
  accountEnabled: true
  displayName: ssoAppName
  servicePrincipalType: 'Application'
  tags: [
    'WindowsAzureActiveDirectoryIntegratedApp'
  ]
}

// No tenant-wide admin consent is granted by design: each user consents individually on
// first access (this tenant permits user consent), which preserves the first-access
// sign-in/consent card. Re-add Microsoft.Graph/oauth2PermissionGrants (AllPrincipals) here
// to suppress the consent prompt instead.

// Outputs for other modules. appId is read from the service principal (created after the
// application) to avoid the Graph eventual-consistency race where application.appId is not
// yet readable when downstream modules consume it.
output ssoAppId string = ssoServicePrincipal.appId
output ssoAppObjectId string = ssoApplication.id
output ssoAppIdUri string = ssoAppIdUri
output servicePrincipalId string = ssoServicePrincipal.id
output federatedCredentialName string = federatedCredential.name
output federatedCredentialSubject string = federatedCredentialSubject
