import os
import logging
from typing import Dict
from fastapi import FastAPI, Depends, HTTPException
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from llama_index.core import VectorStoreIndex
from llama_index.vector_stores.redis import RedisVectorStore
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from llama_index.llms.ollama import Ollama
from llama_index.core.tools import QueryEngineTool
from llama_index.core.agent import ReActAgent
from llama_index.core import PromptTemplate

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

from rag_demo import custom_schema, getenv_or_exit

# Environment variables
MODEL_NAME = getenv_or_exit("MODEL_NAME")
EMBEDDING_MODEL_NAME = os.getenv("EMBEDDING_MODEL_NAME", "BAAI/bge-small-en-v1.5")
REDIS_HOST = getenv_or_exit("REDIS_HOST")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
OLLAMA_SERVER_URL = getenv_or_exit("OLLAMA_SERVER_URL")

# Initialize embedding model
embed_model = HuggingFaceEmbedding(model_name=EMBEDDING_MODEL_NAME)

# Connect to vector store
vector_store = RedisVectorStore(
    schema=custom_schema,
    redis_url=f"redis://{REDIS_HOST}:{REDIS_PORT}",
)

# Create index
index = VectorStoreIndex.from_vector_store(
    vector_store, embed_model=embed_model
)

# Connect to LLM
llm = Ollama(
    model=MODEL_NAME,
    base_url=OLLAMA_SERVER_URL,
    request_timeout=120.0
)

# Custom prompt for movie recommendations
RECOMMENDATION_PROMPT = PromptTemplate(
    """You are a movie recommendation expert. Based on the user's query, recommend up to 3 top movies from the provided dataset. For each movie, include:
- Title
- IMDb Rating
- Overview
- Genre
- Released Year
- Director
- Stars

Ensure the recommendations are relevant to the query. If no relevant movies are found, return an empty list and a message indicating no matches. The query is: {query_str}
"""
)

# Create query engine with verbose logging
query_engine = index.as_query_engine(
    llm=llm,
    similarity_top_k=3,
    text_qa_template=RECOMMENDATION_PROMPT,
    verbose=True
)

# Wrap query engine as a tool
rag_tool = QueryEngineTool.from_defaults(
    query_engine,
    name="movie_recommendation_tool",
    description="Use this tool only for queries related to movie recommendations, such as asking for movies by genre, director, or description."
)

# System prompt for the agent
AGENT_SYSTEM_PROMPT = (
    "You are a movie recommendation assistant. Your purpose is to assist users with movie recommendations based on their queries. "
    "You have access to a tool called 'movie_recommendation_tool' that provides movie recommendations when the user explicitly asks for them (e.g., by genre, director, or description). "
    "Only use this tool if the query is clearly related to movies or requesting movie recommendations. "
    "For any other type of query (e.g., weather, news, or general information), do not use the tool and instead respond directly with: "
    "'I can only assist with movie recommendations. Please ask about movies.'"
)

# Custom agent
class MovieRecommendationAgent(ReActAgent):
    def chat(self, message: str) -> Dict:
        try:
            logger.info(f"Processing query: {message}")
            # Letting the agent handle the query
            response = super().chat(message)
            logger.info(f"Agent response: {response.response}, sources: {response.sources}")
            
            # If no tools were used, return the agent's direct response
            if not response.sources:
                logger.info("No tools used; returning agent's direct response")
                return {
                    "message": response.response if response.response else "I can only assist with movie recommendations. Please ask about movies.",
                    "recommendations": []
                }
            
            # Extract recommendations from tool output
            recommendations = []
            for tool_output in response.sources:
                if tool_output.tool_name == "movie_recommendation_tool":
                    query_response = tool_output.raw_output  # QueryResponse from query engine
                    for node in query_response.source_nodes:
                        metadata = node.node.metadata
                        recommendations.append({
                            "title": metadata["series_title"],
                            "imdb_rating": metadata["imdb_rating"],
                            "overview": metadata["overview"],
                            "genre": metadata["genre"],
                            "released_year": metadata["released_year"],
                            "director": metadata["director"],
                            "stars": metadata["stars"]
                        })
            
            # Construct final response based on tool output
            if recommendations:
                result = {
                    "message": "Here are the top movie recommendations:",
                    "recommendations": recommendations[:3]
                }
            else:
                result = {
                    "message": "No relevant movies found for your query. Please try a more specific movie-related query.",
                    "recommendations": []
                }
            
            logger.info(f"Final response: {result}")
            return result
        except Exception as e:
            logger.error(f"Error processing query: {str(e)}")
            return {
                "message": f"Error processing your query: {str(e)}",
                "recommendations": []
            }

# Initialize agent with custom system prompt
agent = MovieRecommendationAgent.from_tools(
    tools=[rag_tool],
    llm=llm,
    verbose=True,
    max_iterations=25,
    system_prompt=AGENT_SYSTEM_PROMPT
)

def get_agent():
    return agent

# FastAPI app
app = FastAPI()

# Pydantic model for request
class QueryRequest(BaseModel):
    query: str

@app.post("/recommend")
async def recommend_movies(request: QueryRequest, agent=Depends(get_agent)):
    response = agent.chat(request.query)
    json_compatible_item_data = jsonable_encoder(response)
    return JSONResponse(content=json_compatible_item_data)

@app.get("/recommend")
async def recommend_movies_get(query: str, agent=Depends(get_agent)):
    if not query:
        raise HTTPException(status_code=400, detail="Query parameter is required")
    response = agent.chat(query)
    json_compatible_item_data = jsonable_encoder(response)
    return JSONResponse(content=json_compatible_item_data)