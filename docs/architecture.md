# Architecture

## Overview

This application exposes a multi-agent system as an M365 Copilot / Teams bot, secured behind Azure API Management with per-user document access control via Azure AI Search and Entra security groups.

## Deployed Architecture (Detailed)

```mermaid
flowchart TB
    subgraph CLIENT["👤 End User"]
        Teams["Microsoft Teams<br/>or M365 Copilot"]
    end

    subgraph ENTRA["🔐 Microsoft Entra ID"]
        BotAppReg["Bot App Registration<br/>api://botid-{id}<br/><i>audience for Bot Framework JWT</i>"]
        OAuthToken["Bot Framework<br/>Token Service<br/><i>token.botframework.com</i>"]
        GraphAPI["Microsoft Graph API<br/><i>resolves user group memberships</i>"]
    end

    subgraph BOT_SERVICE["🤖 Azure Bot Service"]
        Bot["Bot Channel Registration<br/><i>Messaging endpoint =<br/>https://apim-xxx.azure-api.net<br/>/bot/api/messages</i>"]
        OAuthSearch["OAuth Connection<br/><b>search_access_token</b><br/>AAD v2 + Federated Credentials<br/><i>scopes: search.azure.com/user_impersonation</i>"]
    end

    subgraph APIM_GW["🛡️ Azure API Management"]
        direction TB

        subgraph BOT_OP["Operation: POST /bot/api/messages"]
            BotJWT["<b>validate-jwt</b><br/>iss = api.botframework.com<br/>aud = {bot-app-id}<br/>openid-config =<br/>login.botframework.com/.well-known"]
        end

        subgraph API_OP["Operation: POST /api/*"]
            UserJWT["<b>validate-jwt</b><br/>iss = login.microsoftonline.com/{tid}/v2.0<br/>aud = {api-app-id}"]
        end
    end

    subgraph APP["⚙️ App Service<br/><i>(Private endpoint — only APIM can reach)</i>"]
        direction TB
        BotHandler["/api/messages<br/><b>M365 Agents SDK</b><br/>AgentApplication + CloudAdapter<br/>jwt_authorization_middleware"]
        SearchAuth["Token Exchange<br/><b>auth_handlers=['SEARCH']</b><br/>Bot Framework Token Service<br/>→ search token (aud=search.azure.com)"]
        AgentFW["Agent + FoundryChatClient<br/><b>SecureSearchContextProvider</b><br/>contextvars (async-safe)<br/>per-conversation AgentSession"]
    end

    subgraph SEARCH["🔍 Azure AI Search"]
        direction TB
        Index["Index: secure-docs<br/><b>permissionFilterOption=ENABLED</b>"]
        ACL["Permission Filter<br/>group_ids (GROUP_IDS)<br/><i>x-ms-query-source-authorization</i>"]
        Docs_PM["PM Documents<br/>group: SG-ProjectManagers"]
        Docs_MK["Marketing Documents<br/>group: SG-Marketing"]
        Docs_Shared["Shared Documents<br/>group: [PM, Marketing]"]
        Docs_All["Public Documents<br/>group: all"]
    end

    subgraph FOUNDRY["🧠 Microsoft Foundry"]
        LLM["FoundryChatClient<br/>streaming response"]
    end

    %% ── Inbound: Teams → APIM → App ──
    Teams -->|"1️⃣ User sends message"| Bot
    Bot -->|"2️⃣ POST /bot/api/messages<br/>Authorization: Bearer BF_JWT"| BotJWT
    BotJWT -->|"3️⃣ JWT validated ✅<br/>Forward to backend"| BotHandler

    %% ── Token exchange ──
    BotHandler -->|"4️⃣ auth_handlers=['SEARCH']<br/>triggers token exchange"| SearchAuth
    SearchAuth -.->|"5️⃣ OAuth card (outbound, direct)"| Bot
    Bot -.->|"6️⃣ Token exchange"| OAuthToken
    OAuthToken -.->|"7️⃣ Search token<br/>(aud=search.azure.com<br/>scp=user_impersonation)"| SearchAuth

    %% ── AI Search with ACL ──
    SearchAuth -->|"8️⃣ x-ms-query-source-authorization"| ACL
    ACL -->|"9️⃣ Resolve user groups"| GraphAPI
    ACL --> Docs_PM
    ACL --> Docs_MK
    ACL --> Docs_Shared
    ACL --> Docs_All
    Index -->|"🔟 Filtered results<br/>(user-scoped)"| AgentFW

    %% ── Agent → LLM ──
    AgentFW -->|"1️⃣1️⃣ User question +<br/>filtered docs as context"| LLM
    LLM -->|"1️⃣2️⃣ Streaming response"| BotHandler

    %% ── Reply (outbound, direct) ──
    BotHandler -.->|"1️⃣3️⃣ Reply Activity<br/>(direct to Bot Connector<br/>serviceUrl)"| Bot
    Bot -.-> Teams

    %% ── Non-bot API clients ──
    UserJWT -->|"JWT validated ✅"| AgentFW

    %% Styling
    classDef entra fill:#0078d4,color:#fff,stroke:#005a9e
    classDef bot fill:#7b83eb,color:#fff,stroke:#5b5fc7
    classDef apim fill:#ff8c00,color:#fff,stroke:#cc7000
    classDef app fill:#27ae60,color:#fff,stroke:#1e8449
    classDef search fill:#2c3e50,color:#fff,stroke:#1a252f
    classDef foundry fill:#9b59b6,color:#fff,stroke:#7d3c98
    classDef user fill:#34495e,color:#fff,stroke:#2c3e50

    class BotAppReg,OAuthToken,GraphAPI entra
    class Bot,OAuthSearch bot
    class BotJWT,UserJWT apim
    class BotHandler,SearchAuth,AgentFW app
    class Index,ACL,Docs_PM,Docs_MK,Docs_Shared,Docs_All search
    class LLM foundry
    class Teams user
```

## Token Exchange Sequence

```mermaid
sequenceDiagram
    actor User as 👤 User (Teams)
    participant Bot as 🤖 Bot Service
    participant APIM as 🛡️ APIM
    participant App as ⚙️ App Service
    participant TokenSvc as 🔐 Bot Framework<br/>Token Service
    participant Search as 🔍 AI Search
    participant Graph as 🔐 Microsoft Graph
    participant LLM as 🧠 Microsoft Foundry

    Note over User,LLM: 1. Inbound: user message arrives via APIM

    User->>Bot: Send message
    Bot->>APIM: POST /bot/api/messages<br/>Authorization: Bearer BF_JWT
    APIM->>APIM: validate-jwt<br/>iss=api.botframework.com<br/>aud={bot-app-id}
    APIM->>App: Forward Activity (JWT validated ✅)

    Note over App,TokenSvc: 2. Token exchange (auth_handlers=["SEARCH"])

    App->>Bot: OAuth card (outbound, direct)
    Bot->>User: Consent prompt (first time only)
    User->>Bot: Consent granted
    Bot->>TokenSvc: Token exchange request<br/>connection: search_access_token
    TokenSvc-->>App: Search token<br/>(aud=search.azure.com<br/>scp=user_impersonation)

    Note over App: Token stored in Bot Framework Token Store
    Note over App: Subsequent requests: silent exchange (no consent)

    Note over App,Search: 3. AI Search query with per-user ACL filtering

    App->>Search: POST /indexes/secure-docs/docs/search<br/>Authorization: Bearer {MI token}<br/>x-ms-query-source-authorization: Bearer {search token}
    Search->>Graph: Resolve user group memberships
    Graph-->>Search: Groups: [SG-ProjectManagers]
    Search->>Search: Filter documents by group_ids
    Search-->>App: Filtered results (user-scoped)

    Note over App,LLM: 4. Agent processes with filtered context

    App->>LLM: User question + filtered documents
    LLM-->>App: Streaming response

    Note over App,User: 5. Reply (outbound, direct — bypasses APIM)

    App->>Bot: Reply Activity<br/>POST {serviceUrl}/v3/conversations/{id}/activities
    Bot->>User: Display response
```

## Per-User Document Filtering

Documents in AI Search have a `group_ids` field with `permissionFilter=GROUP_IDS`. When a user queries:

1. The App Service acquires a search token via the `SEARCH` auth handler (Bot Framework Token Service)
2. The search token (`aud=search.azure.com`) is passed to AI Search via `x-ms-query-source-authorization`
3. AI Search calls Microsoft Graph to resolve the user's Entra security group memberships
4. Only documents where `group_ids` matches one of the user's groups (or `"all"`) are returned
5. The agent uses only these filtered documents as context for the LLM

| Document | SG-ProjectManagers | SG-Marketing |
|----------|:------------------:|:------------:|
| Q3 Budget Tracker | ✅ | ❌ |
| Vendor Contracts & SLAs | ✅ | ❌ |
| Risk Register | ✅ | ❌ |
| Marketing Campaign Plan | ❌ | ✅ |
| Brand Guidelines | ❌ | ✅ |
| Social Media Calendar | ❌ | ✅ |
| Event Brief (shared) | ✅ | ✅ |
| Catering Policy (public) | ✅ | ✅ |

## Network Security

```mermaid
flowchart TB
    subgraph INTERNET["🌐 Internet"]
        BotSvc["Bot Service"]
        BotConnector["Bot Connector Service<br/>smba.trafficmanager.net"]
    end

    subgraph AZURE["☁️ Azure"]
        APIM["API Management<br/>(public IP, VNet integrated)"]
        subgraph PRIVATE_SUBNET["🔒 Private Subnet"]
            AppSvc["App Service<br/>(private endpoint only)<br/>❌ No public access"]
        end
        Search["AI Search"]
        Foundry["Microsoft Foundry"]
    end

    BotSvc -->|"Inbound: HTTPS<br/>BF JWT validated"| APIM
    APIM -->|"Private endpoint"| AppSvc
    AppSvc -->|"MI credential"| Search
    AppSvc -->|"MI credential"| Foundry
    AppSvc -.->|"Reply (outbound,<br/>direct to Microsoft)"| BotConnector

    style APIM fill:#f39c12,color:#fff
    style AppSvc fill:#27ae60,color:#fff
    style PRIVATE_SUBNET fill:#ecf0f1,stroke:#bdc3c7,stroke-dasharray:5 5
    style Search fill:#2c3e50,color:#fff
    style Foundry fill:#9b59b6,color:#fff
```

The App Service is **not publicly accessible** when configured with a private endpoint. Only APIM can reach it through VNet integration. Outbound traffic (replies to Bot Connector, calls to AI Search and Microsoft Foundry) goes through the App Service's managed outbound IPs.

## APIM Policy

The Bot Framework JWT is validated by APIM before reaching the App Service:

```xml
<validate-jwt header-name="Authorization" require-scheme="Bearer">
    <openid-config url="https://login.botframework.com/v1/.well-known/openidconfiguration" />
    <audiences>
        <audience>{{bot-app-id}}</audience>
    </audiences>
    <issuers>
        <issuer>https://api.botframework.com</issuer>
    </issuers>
</validate-jwt>
```

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| APIM in front of App Service | Network security — App Service can be private endpoint, only APIM reaches it |
| Bot Framework JWT validated by APIM | Ensures only legitimate Bot Service traffic reaches the app |
| Search token via Bot Framework Token Service | No client secrets needed — federated credentials handle the token exchange |
| `AzureAISearchContextProvider` subclass | The SDK doesn't yet support `x-ms-query-source-authorization` ([Issue #4878](https://github.com/microsoft/agent-framework/issues/4878)) |
| `contextvars` for search token | Async-safe per-request state — prevents cross-user token leaking |
| Per-conversation `AgentSession` | Preserves LLM conversation history without cross-user context leaking |
| Outbound replies bypass APIM | Standard Bot Framework behavior — replies go directly to Bot Connector Service (`serviceUrl`) |

## References

| Topic | URL |
|-------|-----|
| M365 Agents SDK | https://learn.microsoft.com/microsoft-365/agents-sdk/agents-sdk-overview |
| Agent Framework (Python) | https://github.com/microsoft/agent-framework |
| AI Search Document-Level ACLs | https://learn.microsoft.com/azure/search/search-document-level-access-overview |
| Query-Time ACL Enforcement | https://learn.microsoft.com/azure/search/search-query-access-control-rbac-enforcement |
| Bot Connector Authentication | https://learn.microsoft.com/azure/bot-service/rest-api/bot-framework-rest-connector-authentication |
| APIM validate-jwt Policy | https://learn.microsoft.com/azure/api-management/validate-jwt-policy |
| Bot SSO Overview | https://learn.microsoft.com/microsoftteams/platform/bots/how-to/authentication/bot-sso-overview |
