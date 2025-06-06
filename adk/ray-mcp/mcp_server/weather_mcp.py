import os
import logging
from typing import Any
import json

import httpx
from mcp.server.fastmcp import FastMCP

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

MCP_SERVER_HOST = os.getenv("MCP_SERVER_HOST", "0.0.0.0")  # For Uvicorn to bind to all interfaces in the container
MCP_SERVER_PORT = int(os.getenv("MCP_SERVER_PORT", 50051))

NWS_API_BASE = "https://api.weather.gov"
USER_AGENT = "weather-app/1.0"

# Initialize FastMCP server
mcp = FastMCP(
    instance_name="weather_mcp_server",
    instructions="This MCP server provides tools to query information about weather.",
    host=MCP_SERVER_HOST,
    port=MCP_SERVER_PORT,
    # sse_path="/sse", # Default, can be overridden if needed
    # message_path="/messages/", # Default, can be overridden if needed
)
logging.info(f"Weather MCP server starting on {MCP_SERVER_HOST}:{MCP_SERVER_PORT}")

# --- NWS API Interaction ---
async def make_nws_request(url: str) -> dict[str, Any] | None:
    """Make a request to the NWS API with proper error handling."""
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "application/geo+json"
    }
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(url, headers=headers, timeout=30.0)
            response.raise_for_status()
            return response.json()
        except httpx.TimeoutException:
            logger.error(f"Request timeout for URL: {url}")
            return None
        except httpx.HTTPStatusError as e:
            logger.error(f"HTTP error {e.response.status_code} for URL: {url}")
            return None
        except Exception as e:
            logger.error(f"An unexpected error occurred in make_nws_request: {e}", exc_info=True)
            return None


def format_alert(feature: dict) -> str:
    """Format an alert feature into a readable string."""
    props = feature["properties"]
    return f"""
Event: {props.get('event', 'Unknown')}
Area: {props.get('areaDesc', 'Unknown')}
Severity: {props.get('severity', 'Unknown')}
Description: {props.get('description', 'No description available')}
Instructions: {props.get('instruction', 'No specific instructions provided')}
"""

# --- MCP Tools ---
@mcp.tool()
async def get_alerts(state: str) -> str:
    """Get weather alerts for a US state.

    Args:
        state: Two-letter US state code (e.g. CA, NY)
    """
    points_url = f"{NWS_API_BASE}/alerts/active/area/{state}"
    points_data = await make_nws_request(points_url)

    if not points_data or "features" not in points_data:
        return "Unable to fetch alerts or no alerts found."

    if not points_data["features"]:
        return "No active alerts for this state."

    alerts = [format_alert(feature) for feature in points_data["features"]]
    return "\n---\n".join(alerts)


@mcp.tool()
async def get_forecast(latitude: float, longitude: float) -> str:
    """Get weather forecast for a location. Returns data as a JSON string.

    Args:
        latitude: Latitude of the location
        longitude: Longitude of the location
    """
    # First get the forecast grid endpoint
    points_url = f"{NWS_API_BASE}/points/{latitude},{longitude}"
    points_data = await make_nws_request(points_url)

    if not points_data:
        return json.dumps({"error": "Unable to fetch forecast grid data for this location."})

    # Get the forecast URL from the points response
    forecast_url = points_data.get("properties", {}).get("forecast")
    if not forecast_url:
        return json.dumps({"error": "Could not determine forecast URL from point data."}) 

    forecast_data = await make_nws_request(forecast_url)

    if not forecast_data or "properties" not in forecast_data:
        return json.dumps({"error": "Unable to fetch detailed forecast."})

    periods_from_api = forecast_data["properties"].get("periods")
    if not periods_from_api:
        return json.dumps({"error": "No forecast periods available."})

    # Format the periods into a list of dictionaries
    output_periods = []
    for period_data in periods_from_api[:5]:  # Take the first 5 periods
        output_periods.append({
            "name": period_data.get("name"),
            "temperature": period_data.get("temperature"),
            "temperatureUnit": period_data.get("temperatureUnit"),
            "windSpeed": period_data.get("windSpeed"),
            "windDirection": period_data.get("windDirection"),
            "icon": period_data.get("icon"),
            "shortForecast": period_data.get("shortForecast"),
            "detailedForecast": period_data.get("detailedForecast")
        })
    return json.dumps(output_periods)


if __name__ == "__main__":
    logger.info("Starting Weather MCP Server...")
    try:
        mcp.run(transport="sse")
    except Exception as e:
        logging.critical(f"MCP server failed to run: {e}", exc_info=True)
        exit(1)