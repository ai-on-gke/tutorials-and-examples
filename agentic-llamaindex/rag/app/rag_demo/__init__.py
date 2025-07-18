import os
import logging
from redisvl.schema import IndexSchema

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

custom_schema = IndexSchema.from_dict(
    {
        "index": {"name": "movies", "prefix": "movie"},
        "fields": [
            {"type": "tag", "name": "id"},
            {"type": "tag", "name": "doc_id"},
            {"type": "text", "name": "text"},
            {
                "type": "vector",
                "name": "vector",
                "attrs": {
                    "dims": 384,
                    "algorithm": "hnsw",
                    "distance_metric": "cosine",
                },
            },
        ],
    }
)

def getenv_or_exit(name: str) -> str:
    value = os.getenv(name)
    if value is None:
        logger.critical(f"The environment variable '{name}' is not specified")
        exit(1)
    return value