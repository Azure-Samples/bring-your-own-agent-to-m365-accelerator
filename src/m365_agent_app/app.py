"""
M365 Agent Application — Bot + Multi-Agent behind APIM

Architecture:
  Teams/Copilot → Bot Service → APIM (validates BF JWT) → App Service (this)
    → SSO + Search token → AI Search (per-user ACLs) → Agent → Foundry
    → Streaming response → Bot Connector (direct) → Teams
"""

import asyncio
import logging
import traceback
from os import environ

from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv
from microsoft_agents.activity import load_configuration_from_env
from microsoft_agents.authentication.msal import MsalConnectionManager
from microsoft_agents.hosting.aiohttp import CloudAdapter
from microsoft_agents.hosting.core import (
    AgentApplication,
    Authorization,
    MemoryStorage,
    TurnContext,
    TurnState,
)

from agents.orchestrator import OrchestratorAgent
from utils import acquire_token, stream_agent_response

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(levelname)s: %(message)s")
logger = logging.getLogger("app")

# ── SDK configuration ──

agents_sdk_config = load_configuration_from_env(environ)
STORAGE = MemoryStorage()
CONNECTION_MANAGER = MsalConnectionManager(**agents_sdk_config)
ADAPTER = CloudAdapter(connection_manager=CONNECTION_MANAGER)
AUTHORIZATION = Authorization(STORAGE, CONNECTION_MANAGER, **agents_sdk_config)

AGENT_APP = AgentApplication[TurnState](
    storage=STORAGE, adapter=ADAPTER, authorization=AUTHORIZATION, **agents_sdk_config
)

credential = DefaultAzureCredential(
    managed_identity_client_id=environ.get("AZURE_CLIENT_ID")
)

# ── Lazy agent initialization ──

_AGENT: OrchestratorAgent | None = None
_AGENT_LOCK = asyncio.Lock()


async def get_agent() -> OrchestratorAgent:
    global _AGENT
    if _AGENT is None:
        async with _AGENT_LOCK:
            if _AGENT is None:
                _AGENT = await OrchestratorAgent.create(credential=credential)
    return _AGENT


# ── Auth callbacks ──


@AGENT_APP.on_sign_in_success
async def on_sign_in_success(context: TurnContext, state: TurnState, handler_id: str = None):
    pass


@AGENT_APP.on_sign_in_failure
async def on_sign_in_failure(context: TurnContext, state: TurnState, handler_id: str = None):
    await context.send_activity("Sign-in failed. Please try again after granting consent.")


# ── Lifecycle handlers ──


@AGENT_APP.conversation_update("membersAdded")  # type: ignore
async def on_members_added(context: TurnContext, state: TurnState):
    return


@AGENT_APP.activity("typing")
async def on_typing(context: TurnContext, state: TurnState):
    return


@AGENT_APP.activity("installationUpdate")
async def on_install(context: TurnContext, state: TurnState):
    return


# ── Message handler ──


@AGENT_APP.activity("message", auth_handlers=["SEARCH"])
async def on_message(context: TurnContext, state: TurnState):
    user_message = context.activity.text or ""
    if not user_message.strip():
        return

    user_name = context.activity.from_property.name or "unknown"
    logger.info("Message from %s: %s", user_name, user_message[:100])

    search_token = await acquire_token(AGENT_APP, context, "SEARCH", user_name)

    try:
        if context.streaming_response is not None:
            agent = await get_agent()
            await stream_agent_response(
                agent, context, user_message, context.activity.conversation.id, search_token
            )
    except Exception as e:
        logger.error("Agent processing error: %s", e)
        traceback.print_exc()
        try:
            if context.streaming_response is not None:
                await context.streaming_response.end_stream()
        except Exception:
            pass
        if "ActivityNotFoundInConversation" not in str(e):
            await context.send_activity("Sorry, an error occurred. Could you please rephrase your request?")
