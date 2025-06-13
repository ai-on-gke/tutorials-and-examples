import os
import logging
from typing import List, Dict
from fastapi import FastAPI, Depends, HTTPException
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import re

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
    description="Use this tool to recommend movies based on user queries, providing title, IMDb rating, overview, genre, year, director, and stars."
)

# Custom agent
class MovieRecommendationAgent(ReActAgent):
    def chat(self, message: str) -> Dict:
        try:
            logger.info(f"Processing query: {message}")
            response = query_engine.query(message)
            logger.info(f"Raw LLM response: {response.response}")
            
            if not response.source_nodes:
                logger.warning("No source nodes found for query")
                return {
                    "message": "No relevant movies found for your query. Please try a more specific movie-related query.",
                    "recommendations": []
                }
            
            # Parse LLM response with flexible regex
            recommendations = []
            movie_blocks = re.finditer(
                r"\*\*(?:\d+\.\s*)?(.+?)\s*\((\d{4})\)\s*\**\n"  # Title and year
                r"(?:.*?\n)*?"  # Optional lines
                r"\*\s+\*\*IMDb Rating:\*\*\s*([\d.]+)(?:/10)?\n"  # Rating (with or without /10)
                r"\*\s+\*\*Overview:\*\*\s*(.+?)\n"  # Overview
                r"\*\s+\*\*Genre:\*\*\s*(.+?)\n"  # Genre
                r"(?:.*?\n)*?"  # Optional lines
                r"\*\s+\*\*Director:\*\*\s*(.+?)\n"  # Director
                r"\*\s+\*\*Stars:\*\*\s*(.+?)(?=\n(?:\n|\Z|\*))",  # Stars until double newline or end
                str(response.response),
                re.DOTALL
            )
            for block in movie_blocks:
                recommendations.append({
                    "title": block.group(1).strip(),
                    "imdb_rating": float(block.group(3)),
                    "overview": block.group(4).strip(),
                    "genre": block.group(5).strip(),
                    "released_year": block.group(2),
                    "director": block.group(6).strip(),
                    "stars": block.group(7).strip()
                })
            
            if not recommendations:
                logger.warning("No recommendations parsed from LLM response")
                for node in response.source_nodes:
                    metadata = node.node.metadata
                    logger.info(f"Node metadata: {metadata}")
                    recommendations.append({
                        "title": metadata["series_title"],
                        "imdb_rating": metadata["imdb_rating"],
                        "overview": metadata["overview"],
                        "genre": metadata["genre"],
                        "released_year": metadata["released_year"],
                        "director": metadata["director"],
                        "stars": metadata["stars"]
                    })
            
            result = {
                "message": "Here are the top movie recommendations:",
                "recommendations": recommendations[:3]
            }
            logger.info(f"Final response: {result}")
            return result
        except Exception as e:
            logger.error(f"Error processing query: {str(e)}")
            return {
                "message": f"Error processing your query: {str(e)}",
                "recommendations": []
            }

# Initialize agent
agent = MovieRecommendationAgent.from_tools(
    tools=[rag_tool],
    llm=llm,
    verbose=True,
    max_iterations=1
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