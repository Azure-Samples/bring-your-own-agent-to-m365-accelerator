# Architecture

## Overview

This application exposes a multi-agent system as an M365 Copilot / Teams bot, secured behind Azure API Management with per-user document access control via Azure AI Search.

```mermaid
flowchart TB
    subgraph CLIENT["End User"]
        Teams["Microsoft Teams<br/>or M365 Copilot"]
    end

    subgraph ENTRA["Microsoft Entra ID"]
        BotAppReg["Bot App Registration<br/>api://botid-{id}"]
        OAuthToken["Bot Framework<br/>Token Service"]
        EntraTokens["Entra ID Token Endpoint"]
        GraphAPI["Microsoft Graph<br/>resolves user group memberships"]
    end

    subgraph BOT_SERVICE["Azure Bot Service"]
        Bot["Bot Channel Registration<br/>Messaging endpoint =<br/>APIM URL"]
        OAuthSSO["OAuth Connection<br/>default_user_access_token"]
        OAuthSearch["OAuth Connection<br/>search_access_token<br/>scope: search.azure.com/user_impersonation"]
    end

    subgraph APIM_GW["Azure API Management"]
        BotJWT["validate-jwt<br/>iss = api.botframework.com<br/>aud = bot-app-id"]
    end

    subgraph APP["App Service"]
        BotHandler["/api/messages<br/>M365 Agents SDK<br/>AgentApplication + CloudAdapter"]
        AuthHandler["auth_handlers=['SEARCH']<br/>Token exchange via Bot Framework<br/>Token Service"]
        AgentFW["Agent + FoundryChatClient<br/>SecureSearchContextProvider<br/>contextvars (async-safe)"]
    end

    subgraph SEARCH["Azure AI Search"]
        Index["Index: secure-docs<br/>permissionFilterOption=ENABLED"]
        ACL["x-ms-query-source-authorization<br/>Native permission filtering"]
        Docs_PM["PM Documents<br/>group: SG-ProjectManagers"]
        Docs_MK["Marketing Documents<br/>group: SG-Marketing"]
        Docs_Shared["Shared Documents<br/>group: all"]
    end

    subgraph FOUNDRY["Azure AI Foundry"]
        LLM["FoundryChatClient<br/>streaming response"]
    end

    Teams -->|"1. User sends message"| Bot
    Bot -->|"2. POST /bot/api/messages<br/>Authorization: Bearer BF_JWT"| BotJWT
    BotJWT -->|"3. JWT validated, forward"| BotHandler

    BotHandler -->|"4. auth_handlers=['SEARCH']"| AuthHandler
    AuthHandler -.->|"5. OAuth card (outbound)"| Bot
    Bot -.->|"6. Token exchange"| OAuthToken
    OAuthToken -.->|"7. Search token<br/>aud=search.azure.com"| AuthHandler

    AuthHandler -->|"8. x-ms-query-source-authorization"| ACL
    ACL -->|"9. Resolve user groups"| GraphAPI
    ACL --> Docs_PM
    ACL --> Docs_MK
    ACL --> Docs_Shared
    Index -->|"10. Filtered results"| AgentFW

    AgentFW -->|"11. User question + docs"| LLM
    LLM -->|"12. Streaming response"| BotHandler
    BotHandler -.->|"13. Reply (direct to Bot Connector)"| Bot
    Bot -.-> Teams

    classDef entra fill:#0078d4,color:#fff
    classDef bot fill:#7b83eb,color:#fff
    classDef apim fill:#ff8c00,color:#fff
    classDef app fill:#27ae60,color:#fff
    classDef search fill:#2c3e50,color:#fff
    classDef foundry fill:#9b59b6,color:#fff

    class BotAppReg,OAuthToken,EntraTokens,GraphAPI entra
    class Bot,OAuthSSO,OAuthSearch bot
    class BotJWT apim
    class BotHandler,AuthHandler,AgentFW app
    class Index,ACL,Docs_PM,Docs_MK,Docs_Shared search
    class LLM foundry
```

## Authentication Flow

```mermaid
sequenceDiagram
    actor User as User (Teams)
    participant Bot as Bot Service
    participant APIM as APIM
    participant App as App Service
    participant TokenSvc as Bot Framework<br/>Token Service
    participant Search as AI Search
    participant Graph as Microsoft Graph
    participant LLM as Foundry (LLM)

    User->>Bot: Send message
    Bot->>APIM: POST /bot/api/messages<br/>Authorization: Bearer BF_JWT
    APIM->>APIM: validate-jwt (iss=api.botframework.com)
    APIM->>App: Forward activity

    Note over App: auth_handlers=["SEARCH"] triggers token exchange

    App->>Bot: OAuth card
    Bot->>User: Consent (first time only)
    User->>Bot: Consent granted
    Bot->>TokenSvc: Token exchange
    TokenSvc-->>App: Search token (aud=search.azure.com)

    App->>Search: Query with x-ms-query-source-authorization
    Search->>Graph: Resolve user group memberships
    Graph-->>Search: Groups: [SG-ProjectManagers]
    Search-->>App: Filtered documents (user-scoped)

    App->>LLM: User question + filtered documents
    LLM-->>App: Streaming response
    App-->>Bot: Reply activity (direct)
    Bot-->>User: Display response
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

Outbound replies from the bot go directly to the Bot Connector Service (`serviceUrl`), bypassing APIM.

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| APIM in front of App Service | Network security — App Service can be private endpoint, only APIM reaches it |
| Bot Framework JWT validated by APIM | Ensures only legitimate Bot Service traffic reaches the app |
| Search token via Bot Framework Token Service | No client secrets needed — federated credentials handle the OBO exchange |
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
| Bot SSO Overview | https://learn.microsoft.com/microsoftteams/platform/bots/how-to/authentication/bot-sso-overview |
