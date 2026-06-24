# Démo Vidéo — Agent Foundry dans Microsoft 365 Copilot

## 1. Foundry Playground

- Ouvrir le portail Azure AI Foundry (`ai.azure.com`)
- Naviguer vers le projet `prj-sbx-cpl-hdw4xtaf`
- Aller dans **Agent Builder** → sélectionner `OrchestratorAgent`
- Dans le Playground, envoyer : *"Bonjour, qu'est-ce que tu sais faire ?"*
- Laisser l'agent répondre
- **Point** : l'agent existe et fonctionne dans Foundry

---

## 2. Portail Azure — Resource Group

- Ouvrir le portail Azure → Resource Group `rg-sbx-cpl-hdw4xtaf`
- Montrer la liste des ressources :
  - `ais-sbx-cpl-hdw4xtaf` — Foundry (AI Services)
  - `prj-sbx-cpl-hdw4xtaf` — Foundry Project
  - `bot-sbx-cpl-hdw4xtaf` — Bot Service
  - `app-teams-sbx-cpl-hdw4xtaf` — App Service (Host Service)
  - `apim-sbx-cpl-hdw4xtaf` — API Management
  - `bot-identity-sbx-cpl-hdw4xtaf` — Managed Identity
- **Point** : tous les composants sont dans un même RG, déployés par IaC (`azd up`)

---

## 3. Bot Service — Configuration

- Cliquer sur `bot-sbx-cpl-hdw4xtaf`
- **Configuration** : montrer le messaging endpoint
  - `https://app-teams-sbx-cpl-hdw4xtaf.azurewebsites.net/api/messages`
  - Le Bot Service pointe vers l'App Service
- **Channels** : montrer que Microsoft Teams est activé (icône verte)
- **Settings > OAuth Connection Settings** : cliquer sur `default_user_access_token`
  - Provider : AAD v2 with Federated Credentials
  - Client ID : `76bb59ab-...` (l'app registration SSO)
  - Token Exchange URL : `api://botid-074df9de-...`
  - Scopes : `api://botid-074df9de-.../access_as_user`
- **Point** : le Bot Service gère le SSO et récupère un token utilisateur via Teams

---

## 4. App Service — Le Host Service (ProxyBot)

- Cliquer sur `app-teams-sbx-cpl-hdw4xtaf`
- **Configuration > Application Settings** : montrer les settings clés
  - `Connections__BotServiceConnection__Settings__AuthType` = `UserManagedIdentity`
  - `Connections__BotServiceConnection__Settings__ClientId` = `074df9de-...` (la managed identity du bot)
  - `AgentApplication__UserAuthorization__Handlers__SSO__Settings__AzureBotOAuthConnectionName` = `default_user_access_token`
  - `Foundry__ProjectEndpoint` = `https://apim-sbx-cpl-hdw4xtaf.azure-api.net/foundry` — pointe vers **APIM**, pas directement vers Foundry
  - `Foundry__AgentName` = `OrchestratorAgent`
- **Point** : le Host Service utilise le SDK Azure AI Projects pour appeler l'agent Foundry à travers APIM. Il passe le JWT utilisateur obtenu par SSO, et APIM fait la validation + le swap de token

---

## 5. APIM — Validation JWT et token swap

- Cliquer sur `apim-sbx-cpl-hdw4xtaf`
- **APIs** → `Foundry Proxy API` → **Policies** (onglet Inbound)
- Montrer la policy :
  - `validate-jwt` : vérifie le JWT utilisateur (signature, audience, issuer)
  - `authentication-managed-identity` : obtient un token MI pour `https://ai.azure.com`
  - `set-header Authorization` : remplace le Bearer user JWT par le token MI
  - `set-backend-service` : redirige vers le vrai endpoint Foundry
  - `forward-request buffer-response="false"` : streaming SSE transparent
- **Named Values** : montrer les valeurs configurables (audiences, issuers, managed identity client ID, backend URL)
- **Point** : APIM valide l'identité de l'utilisateur, puis fait le swap de token vers la Managed Identity. Le backend Foundry ne voit jamais le token utilisateur — il reçoit un token de service. Le streaming passe en transparent

---

## 6. Microsoft 365 Copilot — L'appel live

- Ouvrir Microsoft 365 Copilot en tant qu'Adele Vance
- Dans le chat Copilot, taper : `@Alfred Bonjour, qu'est-ce que tu sais faire ?`
- Montrer :
  - Le SSO transparent (aucun pop-up d'auth)
  - L'indicateur "Thinking..." pendant le traitement
  - La réponse de l'agent qui arrive en streaming
- **Point** : le même agent Foundry qu'au step 1, accessible directement dans Copilot, avec SSO transparent, validation APIM, et streaming natif via le SDK Azure AI Projects
