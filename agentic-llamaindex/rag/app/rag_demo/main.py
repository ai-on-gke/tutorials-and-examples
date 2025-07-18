import os
import logging
import json
from typing import Dict
from fastapi import FastAPI, Depends, HTTPException
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from llama_index.core import VectorStoreIndex
from llama_index.vector_stores.redis import RedisVectorStore
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from llama_index.llms.ollama import Ollama
from llama_index.core import PromptTemplate

from rag_demo.agents.query_expansion import QueryExpander
from rag_demo.agents.validation import ValidationAgent
from rag_demo.agents.correction import CorrectionAgent
from rag_demo.agents.coordinator import MultiStepCoordinator
from rag_demo import custom_schema, getenv_or_exit

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

MODEL_NAME = getenv_or_exit("MODEL_NAME")
EMBEDDING_MODEL_NAME = os.getenv("EMBEDDING_MODEL_NAME", "BAAI/bge-small-en-v1.5")
REDIS_HOST = getenv_or_exit("REDIS_HOST")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
OLLAMA_SERVER_URL = getenv_or_exit("OLLAMA_SERVER_URL")

embed_model = HuggingFaceEmbedding(model_name=EMBEDDING_MODEL_NAME)
vector_store = RedisVectorStore(
    schema=custom_schema,
    redis_url=f"redis://{REDIS_HOST}:{REDIS_PORT}"
)
index = VectorStoreIndex.from_vector_store(
    vector_store,
    embed_model=embed_model
)

llm = Ollama(
    model=MODEL_NAME,
    base_url=OLLAMA_SERVER_URL,
    request_timeout=120.0
)

RECOMMENDATION_PROMPT = PromptTemplate(
    template="""
You are a movie recommendation expert. Based on the user's query, recommend up to 3 top movies from the provided dataset. For each movie, include:
- title
- imdb_rating
- overview
- genre
- released_year
- director
- stars
If no relevant movies are found, return an empty list.
Query: {query_str}
""",
    input_variables="query_str"
)
query_engine = index.as_query_engine(
    llm=llm,
    similarity_top_k=3,
    text_qa_template=RECOMMENDATION_PROMPT,
    verbose=True
)

expander = QueryExpander(llm=llm)
validator = ValidationAgent(llm=llm)
corrector = CorrectionAgent(llm=llm)
coordinator = MultiStepCoordinator(
    expander=expander,
    query_engine=query_engine,
    validator=validator,
    corrector=corrector,
    max_steps=3
)

app = FastAPI()

class QueryRequest(BaseModel):
    query: str

@app.post("/recommend")
async def recommend_movies(request: QueryRequest):
    result = await coordinator.run(request.query)
    return JSONResponse(content=jsonable_encoder(result))

@app.get("/recommend")
async def recommend_movies_get(query: str):
    if not query:
        raise HTTPException(status_code=400, detail="Query parameter is required")
    result = await coordinator.run(query)
    return JSONResponse(content=jsonable_encoder(result))