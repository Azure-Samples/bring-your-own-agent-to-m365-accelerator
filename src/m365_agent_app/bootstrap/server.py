import os

from aiohttp.web import Application, Request, Response, middleware, run_app
from microsoft_agents.hosting.aiohttp import (
    CloudAdapter,
    jwt_authorization_middleware,
    start_agent_process,
)
from microsoft_agents.hosting.core import (
    AgentApplication,
)


def start_server(agent_app: AgentApplication, connection_manager):
    @middleware
    async def health_bypass_middleware(request: Request, handler):
        if request.path == "/health":
            return await handler(request)
        return await jwt_authorization_middleware(request, handler)

    async def entry_point(req: Request) -> Response:
        agent: AgentApplication = req.app["agent_app"]
        adapter: CloudAdapter = req.app["adapter"]
        res = await start_agent_process(
            req,
            agent,
            adapter,
        )
        assert res is not None
        return res

    async def health(req: Request) -> Response:
        return Response(text="OK", status=200)

    # Use health_bypass_middleware instead of jwt directly so /health is public
    app = Application(
        middlewares=[health_bypass_middleware])
    app.router.add_get("/health", health)
    app.router.add_post("/api/messages", entry_point)
    app["agent_configuration"] = (
        connection_manager.get_default_connection_configuration()
        if connection_manager is not None
        else None
    )
    app["agent_app"] = agent_app
    app["adapter"] = agent_app.adapter

    try:
        port_str = os.getenv("PORT", "3978")
        try:
            port = int(port_str)
        except ValueError:
            port = 3978
        print(f"✅ Server running at http://localhost:{port}")
        run_app(app, host="0.0.0.0", port=port)
    except Exception as error:
        raise error
