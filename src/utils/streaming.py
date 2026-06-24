"""Streaming response helpers for agent output."""

import logging

from microsoft_agents.hosting.core import TurnContext

from agents.constants import get_friendly_label
from agents.orchestrator import OrchestratorAgent

logger = logging.getLogger("utils.streaming")


async def stream_agent_response(
    agent: OrchestratorAgent,
    context: TurnContext,
    user_message: str,
    conversation_id: str,
    search_token: str | None,
):
    """Run the agent and stream the response chunks to the user.

    Handles text responses, tool call status updates, and tool results.
    """
    context.streaming_response.set_generated_by_ai_label(enable_generated_by_ai_label=True)
    context.streaming_response.queue_informative_update("...")

    called_tools: dict[str, str] = {}

    async for chunk in agent.invoke(
        user_input=user_message,
        conversation_id=conversation_id,
        user_search_token=search_token,
    ):
        if chunk.agent_response:
            context.streaming_response.queue_text_chunk(chunk.agent_response.text)
        elif chunk.tool_calls:
            label = get_friendly_label(chunk.tool_calls.name)
            called_tools[chunk.tool_calls.call_id] = label
            context.streaming_response.queue_informative_update(f"Calling {label}...")
        elif chunk.tool_answers:
            label = called_tools.get(chunk.tool_answers.call_id, "Unknown tool")
            context.streaming_response.queue_text_chunk(f"\n\n**{label}**\n\n")

    await context.streaming_response.end_stream()
    try:
        await context.streaming_response.wait_for_queue()
    except Exception as e:
        logger.debug("Streaming queue completed: %s", e)


async def send_agent_response(
    agent: OrchestratorAgent,
    context: TurnContext,
    user_message: str,
    conversation_id: str,
    search_token: str | None,
):
    """Run the agent and send the full response as a single activity.

    Fallback for channels that do not support streaming (e.g. the Teams App Test
    Tool / Microsoft 365 Agents Playground used for the anonymous smoke test).
    Accumulates the agent's text and sends one message instead of incremental chunks.
    """
    parts: list[str] = []
    async for chunk in agent.invoke(
        user_input=user_message,
        conversation_id=conversation_id,
        user_search_token=search_token,
    ):
        if chunk.agent_response and chunk.agent_response.text:
            parts.append(chunk.agent_response.text)

    reply = "".join(parts).strip() or "(no response)"
    await context.send_activity(reply)
