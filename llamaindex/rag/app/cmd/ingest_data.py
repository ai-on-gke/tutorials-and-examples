import os
import sys
import pathlib
import pandas as pd
import logging

from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from llama_index.core.ingestion import (
    DocstoreStrategy,
    IngestionPipeline,
    IngestionCache,
)
from llama_index.storage.kvstore.redis import RedisKVStore as RedisCache
from llama_index.storage.docstore.redis import RedisDocumentStore
from llama_index.vector_stores.redis import RedisVectorStore
from llama_index.core import Document, VectorStoreIndex, SimpleDirectoryReader

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

sys.path.append(str(pathlib.Path(__file__).parent.parent.absolute()))
from rag_demo import custom_schema, getenv_or_exit

EMBEDDING_MODEL_NAME = os.getenv("EMBEDDING_MODEL_NAME", "BAAI/bge-small-en-v1.5")
REDIS_HOST = getenv_or_exit("REDIS_HOST")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
INPUT_DIR = getenv_or_exit("INPUT_DIR")

embed_model = HuggingFaceEmbedding(model_name=EMBEDDING_MODEL_NAME)

vector_store = RedisVectorStore(
    schema=custom_schema,
    redis_url=f"redis://{REDIS_HOST}:{REDIS_PORT}",
)

cache = IngestionCache(
    cache=RedisCache.from_host_and_port(REDIS_HOST, REDIS_PORT),
    collection="movie_cache",
)

pipeline = IngestionPipeline(
    transformations=[
        embed_model, 
    ],
    docstore=RedisDocumentStore.from_host_and_port(
        REDIS_HOST, REDIS_PORT, namespace="movie_doc_store"
    ),
    vector_store=vector_store,
    cache=cache,
    docstore_strategy=DocstoreStrategy.UPSERTS,
)

index = VectorStoreIndex.from_vector_store(
    vector_store,
    embed_model=embed_model
)

def load_data(reader: SimpleDirectoryReader):
    """Load CSV data from directory and convert to LlamaIndex Documents."""
    try:
        files = reader.load_data()
        documents = []
        
        for file in files:
            file_path = file.metadata["file_path"]
            logger.info(f"Processing file: {file_path}")
            df = pd.read_csv(file_path)
            
            for _, row in df.iterrows():
                text = (
                    f"Title: {row['Series_Title']}\n"
                    f"Year: {row['Released_Year']}\n"
                    f"Genre: {row['Genre']}\n"
                    f"IMDb Rating: {row['IMDB_Rating']}\n"
                    f"Overview: {row['Overview']}\n"
                    f"Director: {row['Director']}\n"
                    f"Stars: {row['Star1']}, {row['Star2']}, {row['Star3']}, {row['Star4']}"
                )
                doc = Document(
                    text=text,
                    metadata={
                        "series_title": row["Series_Title"],
                        "released_year": str(row["Released_Year"]),  
                        "genre": row["Genre"],
                        "imdb_rating": float(row["IMDB_Rating"]), 
                        "overview": row["Overview"],
                        "director": row["Director"],
                        "stars": f"{row['Star1']}, {row['Star2']}, {row['Star3']}, {row['Star4']}",
                        "doc_id": f"movie_{row['Series_Title'].replace(' ', '_')}",
                        "file_path": file_path
                    },
                    id_=f"movie_{row['Series_Title'].replace(' ', '_')}"
                )
                documents.append(doc)
        logger.info(f"Created {len(documents)} documents from CSV rows")
        return documents
    except Exception as e:
        logger.error(f"Error loading data from {INPUT_DIR}: {str(e)}")
        sys.exit(1)

# Load and ingest data
reader = SimpleDirectoryReader(input_dir=INPUT_DIR)
docs = load_data(reader)
logger.info(f"Loaded {len(docs)} documents")

nodes = pipeline.run(documents=docs, show_progress=True)
logger.info(f"Ingested {len(nodes)} nodes")