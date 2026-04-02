# Architecture v2 — Unified Bot + Multi-Agent behind APIM

> Grounded in Microsoft Learn documentation. All references are linked.

## Table of Contents

- [Current vs Proposed Architecture](#current-vs-proposed-architecture)
- [M365 Agents SDK — What We Should Use vs What Was Bricolé](#m365-agents-sdk--what-we-should-use-vs-what-was-bricolé)
- [Deployed Architecture (Detailed)](#deployed-architecture-detailed)
- [SSO Sequence Diagram](#sso-sequence-diagram)
- [Local Development Architecture](#local-development-architecture)
- [APIM Policy Design](#apim-policy-design)
- [Network Security](#network-security)
- [MS Learn References](#ms-learn-references)

---

## Current vs Proposed Architecture

### Current (v1) — Proxy Bot before APIM

```mermaid
flowchart LR
    Teams["Teams / M365 Copilot"] --> BotService["Bot Service"]
    BotService -->|"Activity + BF JWT"| AppService1["App Service<br/><b>Proxy Bot</b><br/>(Python)"]
    AppService1 -->|"SSO → user JWT"| AppService1
    AppService1 -->|"Bearer: user JWT"| APIM["APIM<br/>validate-jwt<br/>(user JWT)"]
    APIM -->|"Bearer: MI token"| Foundry["Foundry<br/>Multi-Agent"]

    style AppService1 fill:#e74c3c,color:#fff
    style APIM fill:#f39c12,color:#fff
    style Foundry fill:#9b59b6,color:#fff
```

**Problems:**
- Proxy bot is a separate app, duplicates boilerplate
- User JWT is forwarded externally through APIM (token exposure)
- APIM does a token swap (user JWT → MI) — complex policy
- Code uses internal SDK patches and custom `UserTokenCredential` class
- Two deployment targets to manage

### Proposed (v2) — Everything behind APIM, single app

```mermaid
flowchart LR
    Teams["Teams / M365 Copilot"] --> BotService["Bot Service"]
    BotService -->|"Activity + BF JWT"| APIM["APIM<br/>validate-jwt<br/>(Bot Framework JWT)"]
    APIM -->|"Forwarded Activity"| AppService["App Service<br/><b>Bot + Multi-Agent</b><br/>(Python)"]
    AppService -->|"SSO → user JWT<br/>(in-process)"| AppService
    AppService -->|"user context<br/>(in-process)"| MultiAgent["Multi-Agent<br/>System"]
    AppService -.->|"replies (direct)"| BotConnector["Bot Connector<br/>Service"]

    style APIM fill:#f39c12,color:#fff
    style AppService fill:#27ae60,color:#fff
    style MultiAgent fill:#9b59b6,color:#fff
```

**Benefits:**
- Single deployment (bot + multi-agent)
- User JWT stays in-process, never leaves the app
- APIM validates caller identity (Bot Framework JWT), not user tokens
- No token swap needed — app has direct access to resources
- Clean SDK usage, no monkey-patches

---

## M365 Agents SDK — What We Should Use vs What Was Bricolé

> Ref: [M365 Agents SDK Overview](https://learn.microsoft.com/microsoft-365/agents-sdk/agents-sdk-overview) |
> [Python Quickstart](https://learn.microsoft.com/microsoft-365/agents-sdk/quickstart) |
> [Migration Guide](https://learn.microsoft.com/microsoft-365/agents-sdk/bf-migration-python)

### SDK Classes to Use

| SDK Class | Purpose | Import |
|-----------|---------|--------|
| `AgentApplication[TurnState]` | Main app class, handles routing & auth | `microsoft_agents.hosting.core` |
| `CloudAdapter` | Channel adapter, handles Bot Framework protocol | `microsoft_agents.hosting.aiohttp` |
| `MemoryStorage` | Turn state storage | `microsoft_agents.hosting.core` |
| `Authorization` | OAuth/SSO flow management | `microsoft_agents.hosting.core` |
| `MsalConnectionManager` | MSAL-based auth connections | `microsoft_agents.authentication.msal` |
| `start_agent_process` | Processes incoming Activities | `microsoft_agents.hosting.aiohttp` |
| `jwt_authorization_middleware` | Validates incoming Bot Framework JWTs | `microsoft_agents.hosting.aiohttp` |
| `load_configuration_from_env` | Loads config from env vars | `microsoft_agents.activity` |
| `TurnContext` | Per-turn context (activity, send, streaming) | `microsoft_agents.hosting.core` |

### What Was Bricolé (To Remove)

| Bricolage | What it does | SDK replacement |
|-----------|-------------|----------------|
| `_OAuthFlow` monkey-patch | Catches `ValueError` on signin/failure invokes | **Fixed in newer SDK versions** — update SDK and remove patch |
| `UserTokenCredential` class | Wraps user JWT as `TokenCredential` for Azure SDK | **Not needed** — in v2, the user token stays in-process; multi-agent system receives user identity directly, not via Bearer token through APIM |
| Manual `load_configuration_from_env` + `MsalConnectionManager` wiring | Auth bootstrap | Use SDK's **standard `start_server` pattern** from quickstart |
| `_proxy_mode` / direct mode branching | Two code paths | **Single path** — bot always does SSO, always calls multi-agent in-process |
| `extra_body` with `agent_reference` | Injects Foundry agent reference into Responses API | **Still needed if using Foundry** — but can be encapsulated in a clean service class |
| Custom `server.py` with middleware hacks | JWT bypass for health/playground | Use SDK's standard **`start_server`** with `AgentAuthConfiguration` |

### Proper SDK Setup (from [Quickstart](https://learn.microsoft.com/microsoft-365/agents-sdk/quickstart))

```python
# start_server.py — SDK standard pattern
from microsoft_agents.hosting.core import AgentApplication, AgentAuthConfiguration
from microsoft_agents.hosting.aiohttp import (
    start_agent_process,
    jwt_authorization_middleware,
    CloudAdapter,
)
from aiohttp.web import Request, Response, Application, run_app

def start_server(
    agent_application: AgentApplication,
    auth_configuration: AgentAuthConfiguration,
):
    async def entry_point(req: Request) -> Response:
        return await start_agent_process(
            req, req.app["agent_app"], req.app["adapter"],
        )

    APP = Application(middlewares=[jwt_authorization_middleware])
    APP.router.add_post("/api/messages", entry_point)
    APP["agent_configuration"] = auth_configuration
    APP["agent_app"] = agent_application
    APP["adapter"] = agent_application.adapter
    run_app(APP, host="0.0.0.0", port=int(environ.get("PORT", 3978)))
```

```python
# app.py — clean AgentApplication with SSO
from microsoft_agents.hosting.core import (
    AgentApplication, TurnState, TurnContext, MemoryStorage, Authorization,
)
from microsoft_agents.hosting.aiohttp import CloudAdapter
from microsoft_agents.authentication.msal import MsalConnectionManager
from microsoft_agents.activity import load_configuration_from_env

config = load_configuration_from_env(environ)
connection_manager = MsalConnectionManager(**config)
adapter = CloudAdapter(connection_manager=connection_manager)
authorization = Authorization(MemoryStorage(), connection_manager, **config)

AGENT_APP = AgentApplication[TurnState](
    storage=MemoryStorage(),
    adapter=adapter,
    authorization=authorization,
    **config,
)

@AGENT_APP.activity("message", auth_handlers=["SSO"])
async def on_message(context: TurnContext, state: TurnState):
    # SSO already completed — get user token
    token = await AGENT_APP.auth.get_token(context, "SSO")
    # Pass user identity to multi-agent system (in-process)
    await multi_agent_system.handle(context, state, user_token=token.token)
```

### Auth Configuration ([Env Vars](https://learn.microsoft.com/microsoft-365/agents-sdk/bf-migration-python#configuration))

```env
# Required — Bot identity
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTID=<bot-app-id>
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTSECRET=<client-secret>
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__TENANTID=<tenant-id>

# SSO handler
AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__SSO__SETTINGS__AZUREBOTOAUTHCONNECTIONNAME=default_user_access_token

# Connection map
CONNECTIONSMAP__0__SERVICEURL=*
CONNECTIONSMAP__0__CONNECTION=SERVICE_CONNECTION
```

---

## Deployed Architecture (Detailed)

```mermaid
flowchart TB
    subgraph CLIENT["👤 End User"]
        Teams["Microsoft Teams<br/>or M365 Copilot"]
    end

    subgraph ENTRA["🔐 Microsoft Entra ID"]
        BotAppReg["Bot App Registration<br/>api://botid-{id}<br/><i>audience for Bot Framework JWT</i>"]
        OAuthToken["Bot Framework<br/>Token Service<br/><i>token.botframework.com</i>"]
        EntraTokens["Entra ID Token Endpoint<br/><i>login.microsoftonline.com</i>"]
    end

    subgraph BOT_SERVICE["🤖 Azure Bot Service"]
        Bot["Bot Channel Registration<br/><i>Messaging endpoint =<br/>https://apim-xxx.azure-api.net<br/>/bot/api/messages</i>"]
        OAuthConn["OAuth Connection<br/><b>default_user_access_token</b><br/>AAD v2 + Federated Credentials<br/><i>scopes: api://api-app/access_as_user</i>"]
    end

    subgraph APIM_GW["🛡️ Azure API Management"]
        direction TB

        subgraph BOT_OP["Operation: POST /bot/api/messages"]
            BotJWT["<b>validate-jwt</b><br/>iss = api.botframework.com<br/>aud = {bot-app-id}<br/>openid-config =<br/>login.botframework.com/.well-known"]
        end

        subgraph API_OP["Operation: POST /api/*"]
            UserJWT["<b>validate-jwt</b><br/>iss = login.microsoftonline.com/{tid}/v2.0<br/>aud = {api-app-id}<br/>openid-config =<br/>login.microsoftonline.com/{tid}/v2.0"]
        end
    end

    subgraph APP["⚙️ App Service / ACA<br/><i>(Private endpoint — only APIM can reach)</i>"]
        direction TB
        BotHandler["/api/messages<br/><b>M365 Agents SDK</b><br/>AgentApplication + CloudAdapter<br/>jwt_authorization_middleware"]
        SSO["SSO Handler<br/><b>auth_handlers=['SSO']</b><br/>OAuth card exchange<br/>→ gets user JWT"]
        MultiAgent["Multi-Agent System<br/><b>Orchestrator Agent</b><br/>receives user identity in-process<br/>applies authZ per-user"]
        APIHandler["/api/agent/chat<br/><b>Direct API endpoint</b><br/>for non-bot clients<br/>user JWT already validated by APIM"]
    end

    subgraph DOWNSTREAM["🌐 Downstream Resources"]
        Graph["Microsoft Graph API<br/><i>on behalf of user</i>"]
        DB["Databases / APIs<br/><i>scoped to user</i>"]
        Foundry["Azure AI Foundry<br/><i>via Managed Identity</i>"]
    end

    %% ── Bot flow (Teams → APIM → App) ──
    Teams -->|"1️⃣ User sends message"| Bot
    Bot -->|"2️⃣ POST /bot/api/messages<br/>Authorization: Bearer BF_JWT"| BotJWT
    BotJWT -->|"3️⃣ JWT validated ✅<br/>Forward to backend"| BotHandler

    %% ── SSO flow (App ↔ Bot Connector ↔ Teams) ──
    BotHandler -->|"4️⃣ auth_handlers=['SSO']<br/>triggers OAuth flow"| SSO
    SSO -.->|"5️⃣ OAuth Card<br/>(outbound, direct)"| Bot
    Bot -.->|"6️⃣ Token exchange request"| Teams
    Teams -.->|"7️⃣ Consent + token"| Bot
    Bot -.->|"8️⃣ Token exchange"| OAuthToken
    OAuthToken -.->|"9️⃣ User JWT<br/>(oid, tid, scopes)"| SSO

    %% ── Multi-agent invocation ──
    SSO -->|"🔟 User token + message<br/>(in-process call)"| MultiAgent

    %% ── Downstream calls ──
    MultiAgent -->|"OBO token<br/>(on behalf of user)"| Graph
    MultiAgent -->|"User-scoped queries"| DB
    MultiAgent -->|"MI credential<br/>(app identity)"| Foundry

    %% ── API flow (non-bot clients) ──
    UserJWT -->|"JWT validated ✅"| APIHandler
    APIHandler --> MultiAgent

    %% ── Bot replies (outbound, direct — NOT through APIM) ──
    BotHandler -.->|"1️⃣1️⃣ Reply Activities<br/>(outbound, direct to<br/>Bot Connector serviceUrl)"| Bot

    %% Styling
    classDef entra fill:#0078d4,color:#fff,stroke:#005a9e
    classDef bot fill:#7b83eb,color:#fff,stroke:#5b5fc7
    classDef apim fill:#ff8c00,color:#fff,stroke:#cc7000
    classDef app fill:#27ae60,color:#fff,stroke:#1e8449
    classDef downstream fill:#2c3e50,color:#fff,stroke:#1a252f
    classDef user fill:#34495e,color:#fff,stroke:#2c3e50

    class BotAppReg,OAuthToken,EntraTokens entra
    class Bot,OAuthConn bot
    class BotJWT,UserJWT apim
    class BotHandler,SSO,MultiAgent,APIHandler app
    class Graph,DB,Foundry downstream
    class Teams user
```

---

## SSO Sequence Diagram

> Ref: [Bot SSO Overview](https://learn.microsoft.com/microsoftteams/platform/bots/how-to/authentication/bot-sso-overview) |
> [Bot Connector Authentication](https://learn.microsoft.com/azure/bot-service/rest-api/bot-framework-rest-connector-authentication)

```mermaid
sequenceDiagram
    actor User as 👤 User (Teams)
    participant BotSvc as 🤖 Bot Service
    participant APIM as 🛡️ APIM
    participant App as ⚙️ App (Bot + Multi-Agent)
    participant TokenSvc as 🔐 Bot Framework<br/>Token Service
    participant Entra as 🔐 Entra ID
    participant MAS as 🧠 Multi-Agent System

    Note over User,MAS: 1. Inbound: User message arrives via APIM

    User->>BotSvc: Send message
    BotSvc->>APIM: POST /bot/api/messages<br/>Authorization: Bearer BF_JWT<br/>Body: Activity {text, from, channelId}
    APIM->>APIM: validate-jwt<br/>iss=api.botframework.com<br/>aud={bot-app-id}
    APIM->>App: Forward Activity<br/>(JWT validated ✅)

    Note over App: AgentApplication receives Activity<br/>auth_handlers=["SSO"] triggers OAuth flow

    Note over App,Entra: 2. SSO: Token exchange (outbound, direct — bypasses APIM)

    App->>BotSvc: Send OAuth Card<br/>(invoke: signin/tokenExchange)
    BotSvc->>User: Display consent / SSO prompt
    User->>BotSvc: Consent granted
    BotSvc->>TokenSvc: Token exchange request
    TokenSvc->>Entra: Exchange for user token<br/>scope: api://{api-app}/access_as_user
    Entra-->>TokenSvc: User JWT (oid, tid, scp, name, email)
    TokenSvc-->>App: Token response<br/>(user JWT stored in Token Store)

    Note over App: SSO complete — user JWT obtained

    Note over App,MAS: 3. Multi-agent processing (in-process)

    App->>App: AGENT_APP.auth.get_token(ctx, "SSO")<br/>→ user JWT
    App->>MAS: handle(message, user_identity)<br/>(in-process, no HTTP)
    MAS->>MAS: Apply authZ based on user claims<br/>(oid, tid, scopes, groups)

    Note over MAS: Downstream calls scoped to user

    MAS-->>App: Agent response

    Note over App,User: 4. Reply (outbound, direct — bypasses APIM)

    App->>BotSvc: Reply Activity<br/>POST {serviceUrl}/v3/conversations/{id}/activities<br/>(direct to Bot Connector, NOT through APIM)
    BotSvc->>User: Display response
```

---

## Local Development Architecture

```mermaid
flowchart LR
    subgraph LOCAL["💻 Developer Machine"]
        Playground["Agents Playground<br/>teamsapptester<br/>(localhost:56150)"]
        DevTunnel["Dev Tunnel<br/>dh3h4sxp-3978.eun1<br/>.devtunnels.ms"]
        App["App Service<br/>localhost:3978<br/><b>ANONYMOUS mode</b><br/>No JWT validation"]
        MultiAgent["Multi-Agent<br/>(agent-framework<br/>OrchestratorAgent)"]
    end

    subgraph CLOUD["☁️ Azure"]
        BotSvc["Bot Service<br/>(messaging endpoint =<br/>dev tunnel URL)"]
        Foundry["Azure AI Foundry<br/>(direct, via<br/>AzureCliCredential)"]
    end

    Playground -->|"POST /api/messages<br/>(no JWT)"| App
    DevTunnel -->|"forward"| App
    BotSvc -->|"Activity"| DevTunnel
    App --> MultiAgent
    MultiAgent -->|"AzureCliCredential"| Foundry

    style App fill:#27ae60,color:#fff
    style MultiAgent fill:#9b59b6,color:#fff
```

**Local env:**
```env
# Anonymous mode (no auth needed for Playground)
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__ANONYMOUS_ALLOWED=True

# Or with client secret for Teams via dev tunnel
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTID=<bot-app-id>
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTSECRET=<client-secret>
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__TENANTID=<tenant-id>
```

---

## APIM Policy Design

### Operation 1: Bot Framework endpoint

```
Path: POST /bot/api/messages
Backend: https://{app-service}.azurewebsites.net/api/messages
```

```xml
<inbound>
    <!-- Validate Bot Framework JWT -->
    <validate-jwt header-name="Authorization" require-scheme="Bearer"
                  failed-validation-httpcode="401"
                  failed-validation-error-message="Unauthorized: Invalid Bot Framework token">
        <openid-config url="https://login.botframework.com/v1/.well-known/openidconfiguration" />
        <audiences>
            <audience>{{bot-app-id}}</audience>
        </audiences>
        <issuers>
            <issuer>https://api.botframework.com</issuer>
        </issuers>
    </validate-jwt>
    <set-header name="X-Forwarded-By" exists-action="override">
        <value>APIM-Bot</value>
    </set-header>
</inbound>
```

> Ref: [Bot Connector Auth — JWT structure](https://learn.microsoft.com/azure/bot-service/rest-api/bot-framework-rest-connector-authentication): `iss = https://api.botframework.com`, `aud = bot's Microsoft App ID`

### Operation 2: Direct API endpoint

```
Path: POST /api/agent/*
Backend: https://{app-service}.azurewebsites.net/api/agent/*
```

```xml
<inbound>
    <!-- Validate Entra ID user JWT -->
    <validate-jwt header-name="Authorization" require-scheme="Bearer">
        <openid-config url="https://login.microsoftonline.com/{{tenant-id}}/v2.0/.well-known/openid-configuration" />
        <audiences>
            <audience>{{api-app-id}}</audience>
            <audience>api://{{api-app-id}}</audience>
        </audiences>
    </validate-jwt>
</inbound>
```

> Ref: [APIM validate-jwt policy](https://learn.microsoft.com/azure/api-management/validate-jwt-policy)

---

## Network Security

```mermaid
flowchart TB
    subgraph INTERNET["🌐 Internet"]
        BotSvc["Bot Service"]
        OtherClients["API Clients"]
    end

    subgraph VNET["🔒 Virtual Network"]
        APIM["APIM<br/>(public IP, VNet integrated)"]
        subgraph PRIVATE_SUBNET["Private Subnet"]
            AppSvc["App Service<br/>(private endpoint only)<br/>❌ No public access"]
        end
    end

    BotSvc -->|"HTTPS"| APIM
    OtherClients -->|"HTTPS"| APIM
    APIM -->|"Private endpoint"| AppSvc

    style APIM fill:#f39c12,color:#fff
    style AppSvc fill:#27ae60,color:#fff
    style PRIVATE_SUBNET fill:#ecf0f1,stroke:#bdc3c7,stroke-dasharray:5 5
```

The App Service is **not publicly accessible**. Only APIM can reach it through private endpoint / VNet integration.

---

## MS Learn References

| Topic | URL |
|-------|-----|
| M365 Agents SDK Overview | https://learn.microsoft.com/microsoft-365/agents-sdk/agents-sdk-overview |
| Python Quickstart | https://learn.microsoft.com/microsoft-365/agents-sdk/quickstart |
| Python Migration Guide | https://learn.microsoft.com/microsoft-365/agents-sdk/bf-migration-python |
| Bot SSO Overview | https://learn.microsoft.com/microsoftteams/platform/bots/how-to/authentication/bot-sso-overview |
| Bot Connector Authentication | https://learn.microsoft.com/azure/bot-service/rest-api/bot-framework-rest-connector-authentication |
| Activity Protocol | https://learn.microsoft.com/microsoft-365/agents-sdk/activity-protocol |
| APIM validate-jwt Policy | https://learn.microsoft.com/azure/api-management/validate-jwt-policy |
| User Authentication (Python) | https://learn.microsoft.com/microsoftteams/platform/teams-sdk/in-depth-guides/user-authentication |
| AgentApplication Class (Python) | https://learn.microsoft.com/python/api/microsoft-agents-hosting-core/microsoft_agents.hosting.core.app.agentapplication |
| Publish Agent to Teams | https://learn.microsoft.com/azure/ai-foundry/agents/how-to/publish-copilot?view=foundry |
