"""Token acquisition helpers."""

import logging
from typing import Optional

from microsoft_agents.hosting.core import AgentApplication, TurnContext

logger = logging.getLogger("utils.auth")


async def acquire_token(
    agent_app: AgentApplication, context: TurnContext, handler_id: str, user_name: str
) -> Optional[str]:
    """Acquire a token from a configured auth handler.

    Uses the Bot Framework Token Service via the M365 Agents SDK.
    The handler_id maps to an OAuth connection on the Bot Service
    configured via AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__{handler_id}__SETTINGS__.

    Returns the token string or None.
    """
    if not agent_app.auth:
        return None
    try:
        response = await agent_app.auth.get_token(context, handler_id)
        if response and response.token:
            logger.info("%s token acquired for %s", handler_id, user_name)
            return response.token
    except Exception as e:
        logger.warning("%s token acquisition failed: %s", handler_id, e)
    return None
