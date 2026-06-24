import os

from aiohttp.web import Application, Request, Response, run_app
from aiohttp.web_middlewares import middleware
from microsoft_agents.hosting.aiohttp import (
    CloudAdapter,
    jwt_authorization_middleware,
    start_agent_process,
)
from microsoft_agents.hosting.core import (
    AgentApplication,
    AgentAuthConfiguration,
)


def start_server(agent_app: AgentApplication, auth_configuration: AgentAuthConfiguration):
    @middleware
    async def jwt_with_health_bypass(request: Request, handler):
        if request.path == "/health":
            return await handler(request)
        return await jwt_authorization_middleware(request, handler)

    async def entry_point(req: Request) -> Response:
        agent: AgentApplication = req.app["agent_app"]
        adapter: CloudAdapter = req.app["adapter"]
        res = await start_agent_process(req, agent, adapter)
        assert res is not None
        return res

    async def health(req: Request) -> Response:
        return Response(text="OK", status=200)

    app = Application(middlewares=[jwt_with_health_bypass])
    app.router.add_get("/health", health)
    app.router.add_post("/api/messages", entry_point)
    app["agent_configuration"] = auth_configuration
    app["agent_app"] = agent_app
    app["adapter"] = agent_app.adapter

    port = int(os.getenv("PORT", "3978"))
    print(f"✅ Server running at http://localhost:{port}")
    run_app(app, host="0.0.0.0", port=port)
