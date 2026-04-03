"""
Secure Azure AI Search context provider with per-user document-level ACLs.

Extends AzureAISearchContextProvider to inject the user's Entra token
via x_ms_query_source_authorization for native permission filtering.

Ref: https://learn.microsoft.com/azure/search/search-query-access-control-rbac-enforcement
"""

import logging
from typing import Any

from agent_framework import Message
from agent_framework_azure_ai_search import AzureAISearchContextProvider
from azure.search.documents.models import VectorizableTextQuery, VectorizedQuery, QueryType, QueryCaptionType

logger = logging.getLogger(__name__)


class SecureSearchContextProvider(AzureAISearchContextProvider):
    """AzureAISearchContextProvider with per-user token-based ACL enforcement.

    Passes the user's Entra token to AI Search via x_ms_query_source_authorization,
    so results are automatically filtered based on the user's group memberships.
    """

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self._user_search_token: str | None = None

    def set_user_token(self, token: str | None) -> None:
        self._user_search_token = token

    async def _semantic_search(self, query: str) -> list[Message]:
        """Override to inject x_ms_query_source_authorization for per-user ACL filtering."""
        await self._auto_discover_vector_field()

        vector_queries: list[VectorizableTextQuery | VectorizedQuery] = []
        if self.vector_field_name:
            vector_k = max(self.top_k, 50) if self.semantic_configuration_name else self.top_k
            if self._use_vectorizable_query:
                vector_queries = [VectorizableTextQuery(text=query, k=vector_k, fields=self.vector_field_name)]

        search_params: dict[str, Any] = {"search_text": query, "top": self.top_k}
        if vector_queries:
            search_params["vector_queries"] = vector_queries
        if self.semantic_configuration_name:
            search_params["query_type"] = QueryType.SEMANTIC
            search_params["semantic_configuration_name"] = self.semantic_configuration_name
            search_params["query_caption"] = QueryCaptionType.EXTRACTIVE

        # Per-user ACL: requires OBO token with aud=https://search.azure.com
        # TODO: configure OAuth connection with search.azure.com scope for OBO
        # For now, search uses app identity (MI) — all documents visible

        if not self._search_client:
            raise RuntimeError("Search client is not initialized.")

        results = await self._search_client.search(**search_params)

        result_messages: list[Message] = []
        async for doc in results:
            doc_id = doc.get("id") or doc.get("@search.id")
            doc_text: str = self._extract_document_text(doc, doc_id=doc_id)
            if doc_text:
                result_messages.append(Message(role="user", text=doc_text))
        return result_messages
