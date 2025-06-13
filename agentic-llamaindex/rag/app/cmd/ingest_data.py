import os
import sys
import pathlib
import pandas as pd
import logging

from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from llama_index.core.ingestion import IngestionPipeline
from llama_index.vector_stores.redis import RedisVectorStore
from llama_index.core import Document, VectorStoreIndex, SimpleDirectoryReader

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add package to PYTHONPATH
sys.path.append(str(pathlib.Path(__file__).parent.parent.absolute()))
from rag_demo import custom_schema, getenv_or_exit

# Environment variables
EMBEDDING_MODEL_NAME = os.getenv("EMBEDDING_MODEL_NAME", "BAAI/bge-small-en-v1.5")
REDIS_HOST = getenv_or_exit("REDIS_HOST")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
INPUT_DIR = getenv_or_exit("INPUT_DIR")

# Initialize embedding model
embed_model = HuggingFaceEmbedding(model_name=EMBEDDING_MODEL_NAME)

# Initialize vector store
vector_store = RedisVectorStore(
    schema=custom_schema,
    redis_url=f"redis://{REDIS_HOST}:{REDIS_PORT}",
)

# Set up minimal ingestion pipeline
pipeline = IngestionPipeline(
    transformations=[embed_model],
    vector_store=vector_store,
)

# Initialize index
index = VectorStoreIndex.from_vector_store(
    vector_store,
    embed_model=embed_model
)

def load_data(reader: SimpleDirectoryReader):
    """Load CSV data from directory and convert to LlamaIndex Documents."""
    try:
        # Load all files in INPUT_DIR (expecting CSV files)
        files = reader.load_data()
        documents = []
        
        for file in files:
            file_path = file.metadata["file_path"]
            logger.info(f"Processing file: {file_path}")
            df = pd.read_csv(file_path)
            
            # Convert each row to a Document
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

# Process documents individually
nodes = []
for doc in docs:
    logger.info(f"Ingesting document: {doc.id_}")
    try:
        # Generate embedding manually to debug
        embedding = embed_model.get_text_embedding(doc.text)
        logger.info(f"Embedding generated for {doc.id_}: {len(embedding)} dimensions")
        # Run pipeline
        node_list = pipeline.run(documents=[doc], show_progress=True)
        nodes.extend(node_list)
        logger.info(f"Nodes created for {doc.id_}: {len(node_list)}")
    except Exception as e:
        logger.error(f"Error ingesting document {doc.id_}: {str(e)}")

logger.info(f"Ingested {len(nodes)} nodes")