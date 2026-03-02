import os
from typing import AsyncIterable

from agent_framework import (
    Agent,
    AgentSession,
    ToolMode,
)
from agent_framework_azure_ai import AzureAIClient
from azure.identity import AzureCliCredential, DefaultAzureCredential
from models.orchestrator_response import OrchestratorResponse


class OrchestratorAgent:
    name = "OrchestratorAgent"
    instructions = """You are an event coordinator and the orchestrator of a multi‑tool system. Your role is to collect the brief, validate that it is complete, then query in parallel the logistics, catering, weather, and media specialists (creation + validation of content). You never invent information.

                        ## Required brief (mandatory)
                        - Type of event
                        - Date
                        - Number of people
                        - Budget (EUR)
                        - City
                        - Style / ambiance
                        - Type of catering

                        If any information is missing or ambiguous, ask for it in ONE concise question listing the missing elements. Do not call any tool until all the above information is confirmed.

                        ## Tool calls (in parallel)
                        When the brief is complete, call AT THE SAME TIME:
                        - consult_logistic_agent
                        - consult_catering_agent
                        - consult_weather_agent
                        - consult_event_media_agent
                        Pass the same context to each. WAIT for all responses before continuing. Do not rephrase or re-invoke the tools.

                        ## Merging rules
                        - DO NOT INVENT: use only the received responses.
                        - If there is an inconsistency between responses, flag the discrepancy and ask for clarification.
                        - If any tool returns a need for missing information, surface these questions to the user and do not attempt to fill them yourself.

                        ## Response format to the user
                        Provide a clear and concise summary:
                        📍 VENUE: [received info]
                        🌤️ WEATHER: [received info]
                        🍽️ MENU: [received info]
                        🧾 MEDIA: [name, description, validated LinkedIn post]
                        Add a short operational recommendation if useful.

                        ## Prohibitions
                        - Never mention "agent", "tool", or "specialist".
                        - Never invent information.
                        - Do not provide legal or medical advice.

                        Tone: professional, neutral, inclusive, action‑oriented.
                    """
    chat_agent: Agent
    session: AgentSession | None = None

    def __init__(self, chat_agent: Agent):
        """Private constructor - use create() factory method instead."""
        self.chat_agent = chat_agent
        self.session = AgentSession()

    @classmethod
    async def create(cls, credential: AzureCliCredential | DefaultAzureCredential) -> "OrchestratorAgent":
        """Factory method for async initialization."""

        settings = {
            "project_endpoint": os.environ["MS_FOUNDRY_PROJECT_ENDPOINT"],
            "model_deployment_name": os.environ["MS_FOUNDRY_ORCHESTRATOR_MODEL_DEPLOYMENT_NAME"],
            "credential": credential,
        }

        # tools = await create_agent_as_tools(credential)

        chat_agent = AzureAIClient(**settings).as_agent(
            name=cls.name,
            instructions=cls.instructions,
            description="Event coordinator.",
            tool_choice=ToolMode(mode="auto"),
            allow_multiple_tool_calls=True,
        )
        return cls(chat_agent)

    async def invoke(self, user_input: str) -> AsyncIterable[OrchestratorResponse]:
        async for chunk in self.chat_agent.run(user_input, stream=True, session=self.session):
            print(chunk, end='', flush=True)
            if chunk.text:
                yield OrchestratorResponse(agent_response=chunk)
            if chunk.contents:
                # Handle tool call and result payloads emitted alongside text
                for content in chunk.contents:
                    if content.type == "function_call":
                        print(
                            f"\n[Tool Call] {content.call_id}{content.name}({content.arguments})")
                        yield OrchestratorResponse(tool_calls=content)
                    elif content.type == "function_result":
                        print(
                            f"\n[Tool Result] {content.call_id}{content.result}{content.raw_representation})")
                        yield OrchestratorResponse(tool_answers=content)
