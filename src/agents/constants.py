"""Constants for agent tool names and their friendly labels."""

# Tool name constants
TOOL_CATERING = "consult_catering_agent"
TOOL_LOGISTIC = "consult_logistic_agent"
TOOL_WEATHER = "consult_weather_agent"
TOOL_EVENT_MEDIA = "consult_event_media_agent"

# Friendly labels for UI display
FRIENDLY_TOOL_LABELS = {
    TOOL_CATERING: "🍽️ Catering options",
    TOOL_LOGISTIC: "📍 Event logistics",
    TOOL_WEATHER: "🌤️ Weather forecasts",
    TOOL_EVENT_MEDIA: "📸 Media content creation",
}


def get_friendly_label(tool_name: str) -> str:
    """Get the friendly label for a tool name, or return the tool name if not found."""
    return FRIENDLY_TOOL_LABELS.get(tool_name, tool_name)
