"""Token acquisition helpers."""

import logging
from typing import Optional

import jwt
from microsoft_agents.hosting.core import AgentApplication, TurnContext

logger = logging.getLogger("utils.auth")

# Claims that are safe to log for diagnostics (no secrets, identifies the user/token).
_SAFE_CLAIMS = ("aud", "iss", "appid", "azp", "scp", "roles", "oid", "upn", "unique_name", "name", "tid", "exp")


def decode_token_claims(token: Optional[str]) -> dict:
    """Decode a JWT WITHOUT signature verification and return a subset of safe claims.

    Used for runtime diagnostics only. Never logs the raw token — only non-secret
    claims (audience, scopes, object id, upn, expiry) to identify which user the
    token belongs to and confirm the correct audience/scope.
    """
    if not token:
        return {}
    try:
        claims = jwt.decode(token, options={"verify_signature": False})
        return {k: claims[k] for k in _SAFE_CLAIMS if k in claims}
    except Exception as e:  # pragma: no cover - diagnostic best-effort
        logger.debug("Could not decode token claims: %s", e)
        return {}


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
