from dataclasses import dataclass

from agent_framework import (
    AgentResponseUpdate,
    Content,
)


@dataclass
class OrchestratorResponse:
    """
    Structured response from the orchestrator agent.
    """
    agent_response: AgentResponseUpdate | None = None
    tool_calls: Content | None = None
    tool_answers: Content | None = None
