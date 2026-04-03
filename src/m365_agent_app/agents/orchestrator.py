import os
from typing import AsyncIterable

from agent_framework import Agent, AgentSession
from agent_framework.foundry import FoundryChatClient
from azure.identity import AzureCliCredential, DefaultAzureCredential
from models.orchestrator_response import OrchestratorResponse
from tools.secure_search import SecureSearchContextProvider


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
    search_provider: SecureSearchContextProvider | None = None
    session: AgentSession | None = None

    def __init__(self, agent: Agent, search_provider: SecureSearchContextProvider | None = None):
        self.agent = agent
        self.search_provider = search_provider
        self.session = AgentSession()

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

        agent = Agent(
            client=FoundryChatClient(
                project_endpoint=os.environ["MS_FOUNDRY_PROJECT_ENDPOINT"],
                model=os.environ["MS_FOUNDRY_ORCHESTRATOR_MODEL_DEPLOYMENT_NAME"],
                credential=credential,
            ),
            instructions=cls.instructions,
            context_providers=context_providers,
        )
        return cls(agent, search_provider)

    async def invoke(self, user_input: str, user_search_token: str | None = None) -> AsyncIterable[OrchestratorResponse]:
        # Set the user's token for per-user document filtering
        if self.search_provider:
            self.search_provider.set_user_token(user_search_token)

        async for chunk in self.agent.run(user_input, stream=True, session=self.session):
            print(chunk, end='', flush=True)
            if chunk.text:
                yield OrchestratorResponse(agent_response=chunk)
            if chunk.contents:
                for content in chunk.contents:
                    if content.type == "function_call":
                        print(f"\n[Tool Call] {content.call_id}{content.name}({content.arguments})")
                        yield OrchestratorResponse(tool_calls=content)
                    elif content.type == "function_result":
                        print(f"\n[Tool Result] {content.call_id}{content.result}{content.raw_representation})")
                        yield OrchestratorResponse(tool_answers=content)
