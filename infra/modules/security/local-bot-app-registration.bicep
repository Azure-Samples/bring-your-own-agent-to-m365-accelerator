// Local bot app registration — the bot *channel* identity for the dev-tunnel loop.
//
// Two-app security model (mirrors the OfficeDev ProxyAgent-Python sample):
//   • This app  = the bot's channel identity. It is single-tenant and authenticates to
//                 Azure Bot Service with a CLIENT SECRET, because the agent runs on a
//                 laptop/dev container behind a dev tunnel and a managed identity is only
//                 available when running in Azure (that is what the prod bot uses).
//   • SSO app   = modules/security/app-registration.bicep handles *user* authentication
//                 via federated credentials (no secret) and is shared by prod + local.
//
// The client secret is NOT created here: Bicep cannot generate or output an Entra secret
// (secretText is returned only once by addPassword and is read-only), and
// Microsoft.Resources/deploymentScripts is disallowed on this subscription. The deployer
// is set as an owner below so the developer can mint the secret locally with
// `az ad app credential reset` (see scripts/gen_local_env.sh).

extension microsoftGraphV1

@description('Display/unique name for the local bot app registration.')
param appName string

@description('Object id of the principal (the deployer) made owner of this app so it can reset the client secret locally.')
param ownerPrincipalId string

@description('BotID this should match the Microsoft App ID in the Azure Bot Service Configuration')
param botId string

resource localBotApp 'Microsoft.Graph/applications@v1.0' = {
  displayName: appName
  uniqueName: appName
  signInAudience: 'AzureADMyOrg'
  web: {
    redirectUris: [
      'https://token.botframework.com/.auth/web/redirect'
    ]
    implicitGrantSettings: {
      enableIdTokenIssuance: false
      enableAccessTokenIssuance: false
    }
  }
  // Make the deployer an owner so the developer can reset this app's secret locally.
  owners: {
    relationships: [
      ownerPrincipalId
    ]
    relationshipSemantics: 'append'
  }
}

resource localBotServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: localBotApp.appId
  accountEnabled: true
  displayName: appName
  servicePrincipalType: 'Application'
  tags: [
    'WindowsAzureActiveDirectoryIntegratedApp'
  ]
}

output appId string = localBotApp.appId
output appObjectId string = localBotApp.id
output servicePrincipalId string = localBotServicePrincipal.id
output appIdUri string = 'api://botid-${botId}'
