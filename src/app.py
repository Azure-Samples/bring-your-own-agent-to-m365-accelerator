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
from utils import acquire_token, decode_token_claims, stream_agent_response

load_dotenv()

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s")
logger = logging.getLogger("app")

# Runtime diagnostic logging — set ENABLE_DIAG_LOGS=false to silence.
DIAG = environ.get("ENABLE_DIAG_LOGS", "true").lower() == "true"
diag_logger = logging.getLogger("diag")

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
    managed_identity_client_id=environ.get("BOT_CLIENT_ID") or None
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
    # No user-visible message here: this fires on every turn the SEARCH handler re-acquires
    # the token (silent SSO), not only on the first sign-in. The answer to the original
    # message is delivered by the SDK's continuation replay instead.
    return


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


# ── Diagnostic commands (mirror the M365 Agents ProxyAgent sample) ──

SIGN_OUT_COMMAND = "--signout"
CLEAR_CACHE_COMMAND = "--clearcache"


# Type "--signout" to clear the cached SSO/Search tokens so the next message
# triggers a fresh sign-in. Needed to pick up Entra group membership changes,
# since AI Search resolves document ACLs from the user's group claims.
@AGENT_APP.message(SIGN_OUT_COMMAND)
async def on_sign_out(context: TurnContext, state: TurnState):
    for handler_id in ("SSO", "SEARCH"):
        try:
            await AUTHORIZATION.sign_out(context, auth_handler_id=handler_id)
        except Exception as e:
            logger.warning("Sign-out failed for handler %s: %s", handler_id, e)
    await context.send_activity("You have signed out")


# Type "--clearcache" to drop the cached orchestrator agent so it is rebuilt on
# the next message (e.g. to pick up new Foundry agent or tool configuration).
@AGENT_APP.message(CLEAR_CACHE_COMMAND)
async def on_clear_cache(context: TurnContext, state: TurnState):
    global _AGENT
    async with _AGENT_LOCK:
        _AGENT = None
    await context.send_activity("The agent model cache has been cleared.")


# ── Message handler ──

# The SEARCH OAuth handler runs the on-behalf-of flow to obtain the per-user
# search token before the message handler executes.
@AGENT_APP.activity("message", auth_handlers=["SEARCH"])
async def on_message(context: TurnContext, state: TurnState):
    user_message = context.activity.text or ""
    if not user_message.strip():
        return

    user_name = context.activity.from_property.name or "unknown"
    logger.info("Message from %s: %s", user_name, user_message[:100])

    if DIAG:
        act = context.activity
        channel_raw = getattr(act.channel_id, "channel_id", act.channel_id)
        channel_norm = getattr(act.channel_id, "channel", act.channel_id)
        diag_logger.info(
            "DIAG inbound | user=%s | aadObjectId=%s | channel_raw=%s | channel_norm=%s | conversation=%s",
            user_name,
            getattr(act.from_property, "aad_object_id", None),
            channel_raw,
            channel_norm,
            act.conversation.id if act.conversation else None,
        )

    search_token = await acquire_token(AGENT_APP, context, "SEARCH", user_name)

    if DIAG:
        if search_token:
            claims = decode_token_claims(search_token)
            diag_logger.info(
                "DIAG search_token OK | user=%s | aud=%s | scp=%s | oid=%s | upn=%s | exp=%s",
                user_name,
                claims.get("aud"),
                claims.get("scp"),
                claims.get("oid"),
                claims.get("upn") or claims.get("unique_name"),
                claims.get("exp"),
            )
        else:
            diag_logger.warning(
                "DIAG search_token MISSING | user=%s (consent not completed?)", user_name)

    try:
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
