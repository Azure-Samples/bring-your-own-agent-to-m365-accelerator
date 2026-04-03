"""
M365 Agent Application — Bot + Multi-Agent behind APIM (v2)

Architecture (deployed):
  Teams/Copilot → Bot Service → APIM (validates BF JWT) → App Service (this)
    → SSO → user JWT (in-process) → Multi-Agent System (in-process)
    → replies direct to Bot Connector (bypasses APIM)
"""

import asyncio
import base64
import json
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

from agents.constants import get_friendly_label
from agents.orchestrator import OrchestratorAgent

load_dotenv()

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
    managed_identity_client_id=environ.get(
        "CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTID"
    )
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


# ── SSO callbacks ──


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


# ── Message handler (SSO required) ──


@AGENT_APP.activity("message", auth_handlers=["SSO"])
async def on_message(context: TurnContext, state: TurnState):
    user_message = context.activity.text or ""
    if not user_message.strip():
        return

    # Extract user identity for authZ
    user_token = None
    if AGENT_APP.auth:
        try:
            token_response = await AGENT_APP.auth.get_token(context, "SSO")
            if token_response and token_response.token:
                user_token = token_response.token
                print(f"[SSO Token] {user_token}")
                try:
                    payload = user_token.split(".")[1]
                    padding = "=" * (-len(payload) % 4)
                    claims = json.loads(base64.urlsafe_b64decode(payload + padding))
                    print(f"[SSO Claims] sub={claims.get('sub')} oid={claims.get('oid')} "
                          f"upn={claims.get('upn', claims.get('preferred_username'))} "
                          f"scp={claims.get('scp')} aud={claims.get('aud')}")
                except Exception:
                    pass
        except Exception as e:
            print(f"Warning: Could not get user token: {e}")

    called_tool_ids_and_name: dict[str, str] = {}
    try:
        if context.streaming_response is not None:
            context.streaming_response.set_generated_by_ai_label(
                enable_generated_by_ai_label=True
            )
            context.streaming_response.queue_informative_update("...")

            agent = await get_agent()
            async for chunk in agent.invoke(user_input=user_message):
                if chunk.agent_response:
                    context.streaming_response.queue_text_chunk(
                        chunk.agent_response.text
                    )
                elif chunk.tool_calls:
                    friendly_label = get_friendly_label(chunk.tool_calls.name)
                    called_tool_ids_and_name[chunk.tool_calls.call_id] = friendly_label
                    context.streaming_response.queue_informative_update(
                        f"🔧 Calling the tool for... {friendly_label} with context: {chunk.tool_calls.arguments}"
                    )
                elif chunk.tool_answers:
                    friendly_label = called_tool_ids_and_name.get(
                        chunk.tool_answers.call_id, "Unknown tool"
                    )
                    context.streaming_response.queue_text_chunk(
                        f"\n\n✅ **{friendly_label}**\n\n"
                    )

            await context.streaming_response.end_stream()
            try:
                await context.streaming_response.wait_for_queue()
            except Exception as queue_error:
                print(f"Note: Streaming queue completed with warning: {queue_error}")

    except Exception as e:
        print(f"Error during agent processing: {e}")
        traceback.print_exc()
        try:
            if context.streaming_response is not None:
                await context.streaming_response.end_stream()
        except Exception:
            pass
        if "ActivityNotFoundInConversation" not in str(e):
            await context.send_activity(
                "Sorry, an error occurred. Could you please rephrase your request?"
            )

