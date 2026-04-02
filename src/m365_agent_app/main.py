from agent_framework.observability import configure_otel_providers, get_tracer
from dotenv import load_dotenv
from opentelemetry.trace import SpanKind
from opentelemetry.trace.span import format_trace_id

from app import AGENT_APP, CONNECTION_MANAGER
from bootstrap.server import start_server

load_dotenv()


def main():
    try:
        print("🚀 Starting M365 Agent with Core Services Integration...")
        configure_otel_providers()
        # Test core services on startup
        print("-" * 60)
        with get_tracer().start_as_current_span("Scenario: Agent Chat", kind=SpanKind.CLIENT) as current_span:
            print(
                f"Trace ID: {format_trace_id(current_span.get_span_context().trace_id)}")
            start_server(AGENT_APP, CONNECTION_MANAGER.get_default_connection_configuration())
    except Exception as error:
        print(f"❌ Error starting server: {error}")
        raise error


# Start the server
if __name__ == "__main__":
    main()
