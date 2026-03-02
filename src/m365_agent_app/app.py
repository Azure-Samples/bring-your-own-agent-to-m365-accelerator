import asyncio
import traceback
from os import environ

from azure.identity import AzureCliCredential, DefaultAzureCredential
from dotenv import load_dotenv
from microsoft_agents.activity import load_configuration_from_env
from microsoft_agents.authentication.msal import MsalConnectionManager
from microsoft_agents.hosting.aiohttp import (
    CloudAdapter,
)
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

auth_type = environ.get(
    'CONNECTIONS__SERVICE_CONNECTION__SETTINGS__AUTHTYPE')
storage = MemoryStorage()
CONNECTION_MANAGER = None

if auth_type is not None and auth_type == "UserManagedIdentity":
    agents_sdk_config = load_configuration_from_env(
        environ)  # type: ignore
    CONNECTION_MANAGER = MsalConnectionManager(**agents_sdk_config)
    adapter = CloudAdapter(connection_manager=CONNECTION_MANAGER)
    authorization = Authorization(
        storage, CONNECTION_MANAGER, **agents_sdk_config)
    # Create the Agent Application
    AGENT_APP = AgentApplication[TurnState](
        storage=storage, adapter=adapter, auth_configuration=authorization, **agents_sdk_config
    )
    credential = DefaultAzureCredential(managed_identity_client_id=environ.get(
        'CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTID'))
else:
    AGENT_APP = AgentApplication[TurnState](
        storage=storage, adapter=CloudAdapter()
    )
    credential = AzureCliCredential()
    print("Using AzureCliCredential for authentication.")

# Lazy initialization: agent will be created on first use (thread-safe)
_AGENT: OrchestratorAgent | None = None
_AGENT_LOCK = asyncio.Lock()


async def get_agent() -> OrchestratorAgent:
    """Get or create the OrchestratorAgent instance (lazy initialization, thread-safe)."""
    global _AGENT
    if _AGENT is None:
        async with _AGENT_LOCK:
            # Double-check after acquiring lock to avoid race condition
            if _AGENT is None:
                _AGENT = await OrchestratorAgent.create(credential=credential)
    return _AGENT


@AGENT_APP.conversation_update("membersAdded")  # type: ignore
async def on_members_added(context: TurnContext, state: TurnState):
    """Default message when bot is added to a conversation."""
    return


@AGENT_APP.activity("typing")
async def on_typing(context: TurnContext, state: TurnState):
    """No-op handler to safely ignore Teams typing events.
    Prevents routing errors for activity type "typing" which carries no text.
    """
    return


@AGENT_APP.activity("installationUpdate")
async def on_installation_update(context: TurnContext, state: TurnState):
    """No-op handler for Teams app installation updates.
    These events indicate install/uninstall and carry no message text.
    """
    return


@AGENT_APP.activity("message")
async def on_message(context: TurnContext, state: TurnState):
    """
    Handle incoming messages from the user and orchestrate multi-agent workflow with streaming responses.
    This async handler processes user messages by:
    1. Validating the incoming message is non-empty
    2. Setting up streaming response with AI-generated label
    3. Running the coordinator agent in streaming mode
    4. Displaying ephemeral status updates showing progress through multiple specialized agents
    5. Tracking and displaying tool calls (catering, logistics, weather, media agents)
    6. Buffering final response text while showing intermediate progress
    7. Clearing ephemeral updates and sending the complete final response
    The function provides visual feedback using emojis to indicate:
    - ⏳ Agent initialization
    - 🔧 Tool being called
    - ✅ Completed steps
    - ⬜ Pending steps
    Args:
        context (TurnContext): The turn context containing the incoming activity and methods to respond
        state (TurnState): The current conversation state
    Returns:
        None
    Raises:
        Exception: Catches all exceptions during processing, logs them, and sends a user-friendly error message
    """
    user_message = context.activity.text or ""
    # Ignore empty/whitespace-only inputs to avoid unnecessary processing
    if not user_message.strip():
        return

    called_tool_ids_and_name: dict[str, str] = {}
    print(f"Conversation ID: {context.activity.conversation.id}")
    try:
        # Proceed only if streaming is available; otherwise do nothing
        if context.streaming_response is not None:
            context.streaming_response.set_generated_by_ai_label(
                enable_generated_by_ai_label=True)

            context.streaming_response.queue_informative_update(
                "⏳ Thinking..."
            )

            agent = await get_agent()
            async for chunk in agent.invoke(user_input=user_message):
                if chunk.agent_response:
                    # Stream the agent's response text (accumulates permanently)
                    context.streaming_response.queue_text_chunk(
                        chunk.agent_response.text)
                elif chunk.tool_calls:
                    # Show tool call as ephemeral informative update (will disappear)
                    friendly_label = get_friendly_label(chunk.tool_calls.name)
                    called_tool_ids_and_name[chunk.tool_calls.call_id] = friendly_label
                    context.streaming_response.queue_informative_update(
                        f"🔧 Calling the tool for... {friendly_label} with context: {chunk.tool_calls.arguments}")
                elif chunk.tool_answers:
                    # Add tool result to the permanent message
                    friendly_label = called_tool_ids_and_name.get(
                        chunk.tool_answers.call_id, "Unknown tool")
                    context.streaming_response.queue_text_chunk(
                        f"\n\n✅ **{friendly_label}**\n\n")

            # Close and drain the stream to ensure all updates are delivered
            await context.streaming_response.end_stream()
            try:
                await context.streaming_response.wait_for_queue()
            except Exception as queue_error:
                # Streaming queue errors are expected with Teams App Test Tool
                # The response was likely already delivered despite the error
                print(
                    f"Note: Streaming queue completed with warning: {queue_error}")

    except Exception as e:
        print(f"Error during agent processing: {e}")
        traceback.print_exc()
        try:
            if context.streaming_response is not None:
                # Best-effort cleanup: end the stream if it's still open
                await context.streaming_response.end_stream()
        except Exception:
            pass
        # Only send error message if not a streaming-related error
        if "ActivityNotFoundInConversation" not in str(e):
            await context.send_activity("Sorry, an error occurred. Could you please rephrase your request?")
