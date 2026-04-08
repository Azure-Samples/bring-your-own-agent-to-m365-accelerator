"""
Secure Azure AI Search context provider with per-user document-level ACLs.

This module uses the native Agent Framework search provider (AzureAISearchContextProvider)
but subclasses it to inject the `x_ms_query_source_authorization` HTTP header — the
user's Entra-scoped search token — into each AI Search query. This enables AI Search's
native per-user ACL filtering (permissionFilterOption=ENABLED), where the service
automatically resolves the user's group memberships via Microsoft Graph.

The subclass is necessary because the SDK does not yet support passing
`x_ms_query_source_authorization` natively. Once resolved, this custom provider
can be replaced by the standard AzureAISearchContextProvider.
See: https://github.com/microsoft/agent-framework/issues/4878

Ref: https://learn.microsoft.com/azure/search/search-query-access-control-rbac-enforcement
"""

import contextvars
import logging
from typing import Any

from agent_framework import Message
from agent_framework_azure_ai_search import AzureAISearchContextProvider
from azure.search.documents.models import QueryCaptionType, QueryType, VectorizableTextQuery, VectorizedQuery

logger = logging.getLogger("secure_search")

# Per-request search token (async-safe via contextvars)
_current_search_token: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "_current_search_token", default=None
)


def set_current_search_token(token: str | None) -> None:
    _current_search_token.set(token)


class SecureSearchContextProvider(AzureAISearchContextProvider):
    """Context provider with native per-user ACL filtering via x_ms_query_source_authorization.

    Reads the per-request search token from contextvars (set by app.py via SDK OBO).
    """

    async def _semantic_search(self, query: str) -> list[Message]:
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

        search_token = _current_search_token.get()
        if search_token:
            search_params["x_ms_query_source_authorization"] = search_token
            logger.info("Querying AI Search with user token (native ACL filtering)")
        else:
            logger.warning("No search token — results limited to public documents")

        if not self._search_client:
            raise RuntimeError("Search client is not initialized.")

        results = await self._search_client.search(**search_params)

        result_messages: list[Message] = []
        async for doc in results:
            doc_id = doc.get("id") or doc.get("@search.id")
            doc_text: str = self._extract_document_text(doc, doc_id=doc_id)
            if doc_text:
                result_messages.append(Message(role="user", text=doc_text))

        logger.info("AI Search returned %d documents", len(result_messages))
        return result_messages
