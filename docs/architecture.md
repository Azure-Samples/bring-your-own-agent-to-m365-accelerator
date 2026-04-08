# Architecture

## Overview

This application exposes a multi-agent system as an M365 Copilot / Teams bot, secured behind Azure API Management with per-user document access control via Azure AI Search and Entra security groups.

## Deployed Architecture

```mermaid
flowchart TB
    subgraph CLIENT["👤 End User"]
        Teams["Microsoft Teams<br/>or M365 Copilot"]
    end

    subgraph ENTRA["🔐 Microsoft Entra ID"]
        BotAppReg["Bot App Registration<br/>api://botid-{id}"]
        OAuthToken["Bot Framework<br/>Token Service<br/><i>token.botframework.com</i>"]
        GraphAPI["Microsoft Graph API<br/><i>resolves user group memberships</i>"]
    end

    subgraph BOT_SERVICE["🤖 Azure Bot Service"]
        Bot["Bot Channel Registration<br/><i>Messaging endpoint =<br/>https://apim-xxx.azure-api.net<br/>/bot/api/messages</i>"]
        OAuthSearch["OAuth Connection<br/><b>search_access_token</b><br/>AAD v2 + Federated Credentials<br/><i>scopes: search.azure.com/user_impersonation</i>"]
    end

    subgraph APIM_GW["🛡️ Azure API Management"]
        BotJWT["<b>validate-jwt</b><br/>iss = api.botframework.com<br/>aud = {bot-app-id}"]
    end

    subgraph APP["⚙️ App Service<br/><i>(Private endpoint — only APIM can reach)</i>"]
        direction TB
        BotHandler["/api/messages<br/><b>Proxy Bot</b><br/>M365 Agents SDK"]
        SearchAuth["Token Exchange<br/><b>auth_handlers=['SEARCH']</b><br/>→ search token (aud=search.azure.com)"]
        AgentFW["Agent + FoundryChatClient<br/><b>SecureSearchContextProvider</b><br/>per-conversation AgentSession"]
    end

    subgraph SEARCH["🔍 Azure AI Search"]
        direction TB
        Index["Index: secure-docs<br/><b>permissionFilterOption=ENABLED</b>"]
        ACL["Permission Filter<br/>group_ids (GROUP_IDS)<br/><i>x-ms-query-source-authorization</i>"]
        Docs_PM["PM Documents<br/>group: SG-ProjectManagers"]
        Docs_MK["Marketing Documents<br/>group: SG-Marketing"]
        Docs_Shared["Shared Documents"]
        Docs_All["Public Documents"]
    end

    subgraph FOUNDRY["🧠 Microsoft Foundry"]
        LLM["FoundryChatClient<br/>streaming response"]
    end

    %% ── Inbound: Teams → APIM → App ──
    Teams -->|"1️⃣ User sends message"| Bot
    Bot -->|"2️⃣ POST /bot/api/messages<br/>Authorization: Bearer BF_JWT"| BotJWT
    BotJWT -->|"3️⃣ JWT validated ✅"| BotHandler

    %% ── Token exchange ──
    BotHandler -->|"4️⃣ auth_handlers=['SEARCH']"| SearchAuth
    SearchAuth -.->|"5️⃣ Token exchange"| OAuthToken
    OAuthToken -.->|"6️⃣ Search token<br/>(aud=search.azure.com)"| SearchAuth

    %% ── AI Search with ACL ──
    SearchAuth -->|"7️⃣ x-ms-query-source-authorization"| ACL
    ACL -->|"8️⃣ Resolve user groups"| GraphAPI
    ACL --> Docs_PM
    ACL --> Docs_MK
    ACL --> Docs_Shared
    ACL --> Docs_All
    Index -->|"9️⃣ Filtered results"| AgentFW

    %% ── Agent → LLM ──
    AgentFW -->|"🔟 User question + docs"| LLM
    LLM -->|"1️⃣1️⃣ Response"| AgentFW

    %% ── Reply (outbound, direct) ──
    BotHandler -.->|"1️⃣2️⃣ Reply (direct to<br/>Bot Connector)"| Bot
    Bot -.-> Teams

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
    class BotJWT apim
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

    Note over User,LLM: 1. Inbound message via APIM

    User->>Bot: Send message
    Bot->>APIM: POST /bot/api/messages<br/>Authorization: Bearer BF_JWT
    APIM->>APIM: validate-jwt<br/>iss=api.botframework.com
    APIM->>App: Forward Activity

    Note over App,TokenSvc: 2. Token exchange (auth_handlers=["SEARCH"])

    App->>Bot: OAuth card (outbound, direct)
    Bot->>User: Consent prompt (first time only)
    User->>Bot: Consent granted
    Bot->>TokenSvc: Token exchange<br/>connection: search_access_token
    TokenSvc-->>App: Search token (aud=search.azure.com)

    Note over App,Search: 3. AI Search with per-user ACL filtering

    App->>Search: Query with x-ms-query-source-authorization
    Search->>Graph: Resolve user group memberships
    Graph-->>Search: Groups: [SG-ProjectManagers]
    Search-->>App: Filtered results

    Note over App,LLM: 4. Agent processes with filtered context

    App->>LLM: User question + filtered documents
    LLM-->>App: Streaming response

    Note over App,User: 5. Reply (direct to Bot Connector)

    App->>Bot: Reply Activity
    Bot->>User: Display response
```

## Per-User Document Filtering

Documents in AI Search have a `group_ids` field with `permissionFilter=GROUP_IDS`. When a user queries:

1. The proxy bot acquires a search token via the `SEARCH` auth handler (Bot Framework Token Service)
2. The search token (`aud=search.azure.com`) is passed to AI Search via `x-ms-query-source-authorization`
3. AI Search calls Microsoft Graph to resolve the user's Entra security group memberships
4. Only documents where `group_ids` matches one of the user's groups (or `"all"`) are returned

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
        APIM["API Management<br/>(public IP)"]
        subgraph PRIVATE_SUBNET["🔒 Private Subnet"]
            AppSvc["App Service<br/>(private endpoint only)"]
        end
        Search["AI Search"]
        Foundry["Microsoft Foundry"]
    end

    BotSvc -->|"Inbound: BF JWT"| APIM
    APIM -->|"Validated traffic"| AppSvc
    AppSvc -->|"MI credential"| Search
    AppSvc -->|"MI credential"| Foundry
    AppSvc -.->|"Reply (outbound)"| BotConnector

    style APIM fill:#f39c12,color:#fff
    style AppSvc fill:#27ae60,color:#fff
    style PRIVATE_SUBNET fill:#ecf0f1,stroke:#bdc3c7,stroke-dasharray:5 5
    style Search fill:#2c3e50,color:#fff
    style Foundry fill:#9b59b6,color:#fff
```

## APIM Policy

APIM validates the Bot Framework JWT before forwarding to the App Service:

```xml
<policies>
  <inbound>
    <base />
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401"
                  failed-validation-error-message="Unauthorized: invalid Bot Framework token."
                  require-expiration-time="true" require-signed-tokens="true">
      <openid-config url="https://login.botframework.com/v1/.well-known/openidconfiguration" />
      <audiences>
        <audience>{{bot-app-id}}</audience>
      </audiences>
      <issuers>
        <issuer>https://api.botframework.com</issuer>
      </issuers>
    </validate-jwt>
    <set-header name="X-Forwarded-By-APIM" exists-action="override">
      <value>true</value>
    </set-header>
  </inbound>
  <backend>
    <forward-request buffer-response="false" />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
```

Outbound replies go directly to the Bot Connector Service (`serviceUrl`), bypassing APIM. This is standard Bot Framework behavior.

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| APIM in front of App Service | Network security — App Service can be private endpoint, only APIM reaches it |
| Bot Framework JWT validated by APIM | Ensures only legitimate Bot Service traffic reaches the app |
| Search token via Bot Framework Token Service | No client secrets needed — federated credentials handle the token exchange |
| `AzureAISearchContextProvider` subclass | The SDK doesn't yet support `x-ms-query-source-authorization` ([Issue #4878](https://github.com/microsoft/agent-framework/issues/4878)) |
| `contextvars` for search token | Async-safe per-request state — prevents cross-user token leaking |
| Per-conversation `AgentSession` | Preserves LLM conversation history without cross-user context leaking |

## References

| Topic | URL |
|-------|-----|
| M365 Agents SDK | https://learn.microsoft.com/microsoft-365/agents-sdk/agents-sdk-overview |
| Agent Framework (Python) | https://github.com/microsoft/agent-framework |
| AI Search Document-Level ACLs | https://learn.microsoft.com/azure/search/search-document-level-access-overview |
| Query-Time ACL Enforcement | https://learn.microsoft.com/azure/search/search-query-access-control-rbac-enforcement |
| Bot Connector Authentication | https://learn.microsoft.com/azure/bot-service/rest-api/bot-framework-rest-connector-authentication |
| APIM validate-jwt Policy | https://learn.microsoft.com/azure/api-management/validate-jwt-policy |
| ProxyAgent C# Sample | https://github.com/OfficeDev/microsoft-365-agents-toolkit-samples/tree/main/ProxyAgent-CSharp |
