import os
import logging

from google.adk.agents.llm_agent import LlmAgent
from google.adk.models.lite_llm import LiteLlm
from google.adk.tools.mcp_tool.mcp_toolset import MCPToolset
from google.adk.tools.mcp_tool.mcp_session_manager import SseServerParams

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO").upper())
logger = logging.getLogger(__name__)

# Ray Serve config
RAY_SERVICE_NAME = os.getenv("RAY_SERVICE_NAME", "llama-31-8b-serve-svc")
RAY_SERVE_PORT = int(os.getenv("RAY_SERVE_PORT", 8000))
api_base_url = f"http://{RAY_SERVICE_NAME}:{RAY_SERVE_PORT}/v1"
logger.debug(f"Connecting to LLM at: {api_base_url}")

# MCP Toolset Configuration
mcp_weather_host = os.getenv("WEATHER_MCP_SERVER_HOST", "weather-mcp-server")
mcp_weather_port = int(os.getenv("WEATHER_SERVER_PORT", 8080))
mcp_weather_path = os.getenv("WEATHER_MCP_PATH", "/sse")
full_mcp_sse_url = f"http://{mcp_weather_host}:{mcp_weather_port}{mcp_weather_path}"
logger.info(f"Configuring MCPToolset URL: {full_mcp_sse_url}")

connection_params = SseServerParams(
    url=full_mcp_sse_url,
    headers={'Accept': 'text/event-stream'}  # Standard for SSE
)

logger.info(f"Attempting to get tools using MCPToolset.from_server with URL: {full_mcp_sse_url}")
weather_toolset = MCPToolset(
    connection_params=connection_params
)
logger.info("Weather MCPToolset initialized. It will connect to the MCP server when required.")

# Agent configuration
root_agent = LlmAgent(
    name="weather_chat_agent",
    model=LiteLlm(
        model="hosted_vllm/meta-llama/Llama-3.1-8B-Instruct",
        api_base=api_base_url
    ),
    instruction="""You are a specialist AI assistant for weather.

Use your available tools to answer questions about weather.
Format your answers clearly using Markdown.
If you cannot find specific information, say so.""",
    tools=[weather_toolset],
)
logger.info(f"ADK Agent '{root_agent.name}' created and configured with Weather MCP Toolset. "
            f"The toolset will connect to {full_mcp_sse_url} to fetch tool schemas.")
