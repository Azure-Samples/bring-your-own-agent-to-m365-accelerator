import logging
import os
from typing import AsyncIterable

from agent_framework import Agent, AgentSession
from agent_framework.foundry import FoundryChatClient
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import PromptAgentDefinition
from azure.identity import AzureCliCredential, DefaultAzureCredential

from models.orchestrator_response import OrchestratorResponse
from tools.secure_search import SecureSearchContextProvider, set_current_search_token

logger = logging.getLogger("orchestrator")


class OrchestratorAgent:
    name = "OrchestratorAgent"
    instructions = """You are an event coordinator assistant. You help users with event planning by searching internal documents and answering questions.

You have access to a document knowledge base. Use it to find relevant information when the user asks about:
- Event details, briefs, or planning
- Budgets, costs, or financial information
- Vendor contracts or SLAs
- Marketing campaigns, brand guidelines, or social media
- Catering policies or dietary requirements
- Risk registers or operational concerns

Only use information from the documents returned — never invent data.

If no documents are found, tell the user you don't have access to relevant information.

Be concise and professional. Cite the document title when referencing information.
"""
    agent: Agent
    _sessions: dict[str, AgentSession]

    def __init__(self, agent: Agent):
        self.agent = agent
        self._sessions = {}

    def _get_session(self, conversation_id: str) -> AgentSession:
        if conversation_id not in self._sessions:
            self._sessions[conversation_id] = AgentSession()
        return self._sessions[conversation_id]

    @classmethod
    async def create(cls, credential: AzureCliCredential | DefaultAzureCredential) -> "OrchestratorAgent":
        search_endpoint = os.environ.get("AZURE_SEARCH_ENDPOINT", "")
        search_index = os.environ.get("AZURE_SEARCH_INDEX", "secure-docs")

        search_provider = None
        context_providers = []
        if search_endpoint:
            search_provider = SecureSearchContextProvider(
                endpoint=search_endpoint,
                index_name=search_index,
                credential=credential,
                mode="semantic",
                top_k=5,
            )
            context_providers.append(search_provider)

        project = AIProjectClient(
            endpoint=os.environ["MS_FOUNDRY_PROJECT_ENDPOINT"],
            credential=credential,
        )

        foundry_client = FoundryChatClient(
            project_endpoint=os.environ["MS_FOUNDRY_PROJECT_ENDPOINT"],
            model=os.environ["MS_FOUNDRY_ORCHESTRATOR_MODEL_DEPLOYMENT_NAME"],
            credential=credential,
        )

        await foundry_client.configure_azure_monitor(
            enable_sensitive_data=True,
            enable_live_metrics=True,
        )

        logger.info("Observability is set up. Starting Orchestrator Agent...")

        agent_detail = project.agents.create_version(
            agent_name="Orchestrator",
            definition=PromptAgentDefinition(
                model=foundry_client.model,
                instructions=cls.instructions,
            ),
        )
        agent = Agent(
            name=agent_detail.name,
            client=foundry_client,
            context_providers=context_providers,
        )
        return cls(agent)

    async def invoke(self, user_input: str, conversation_id: str = "", user_search_token: str | None = None) -> AsyncIterable[OrchestratorResponse]:
        set_current_search_token(user_search_token)
        session = self._get_session(conversation_id)

        async for chunk in self.agent.run(user_input, stream=True, session=session):
            if chunk.text:
                yield OrchestratorResponse(agent_response=chunk)
            if chunk.contents:
                for content in chunk.contents:
                    if content.type == "function_call":
                        logger.info("Tool call: %s(%s)",
                                    content.name, content.arguments)
                        yield OrchestratorResponse(tool_calls=content)
                    elif content.type == "function_result":
                        logger.info("Tool result: %s", content.call_id)
                        yield OrchestratorResponse(tool_answers=content)
