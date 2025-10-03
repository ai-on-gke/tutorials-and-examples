# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os

from google.adk.agents import Agent
from google.adk.tools import FunctionTool
from mem0 import Memory

VECTOR_DB_NAME = os.environ["VECTOR_DB_NAME"]
VECTOR_DB_HOST = os.environ["VECTOR_DB_HOST"]
VECTOR_DB_USER = os.environ["VECTOR_DB_USER"]
VECTOR_DB_PASSWORD = os.environ["VECTOR_DB_PASSWORD"]

config = {
    "vector_store": {
        "provider": "pgvector",
        "config": {
            "host": VECTOR_DB_HOST,
            "dbname": VECTOR_DB_NAME,
            "user": VECTOR_DB_USER,
            "password": VECTOR_DB_PASSWORD,
            "port": 5432,
            "embedding_model_dims": 768,
        }
    },
    "llm": {
        "provider": "gemini",
        "config": {
            "model": "gemini-2.0-flash-001",
        }
    },
    "embedder": {
        "provider": "gemini",
        "config": {
            "model": "models/text-embedding-004",
        }
    },
}
# Initialize Mem0 client
mem0 = Memory.from_config(config)

# Define memory function tools
def search_memory(query: str, user_id: str) -> dict:
    """Search through past conversations and memories"""
    memories = mem0.search(query, user_id="user")
    if memories.get('results', []):
        memory_list = memories['results']
        memory_context = "\n".join([f"- {mem['memory']}" for mem in memory_list])
        return {"status": "success", "memories": memory_context}
    return {"status": "no_memories", "message": "No relevant memories found"}

search_memory_tool = FunctionTool(func=search_memory)

def save_memory(content: str, user_id: str) -> dict:
    """Save important information to memory"""
    try:
        result = mem0.add([{"role": "user", "content": content}], user_id="user")
        return {"status": "success", "message": "Information saved to memory", "result": result}
    except Exception as e:
        return {"status": "error", "message": f"Failed to save memory: {str(e)}"}

save_memory_tool = FunctionTool(func=save_memory)

# Create agent with memory capabilities
agent_with_memory = Agent(
    name="agent_with_memory",
    model = "gemini-2.5-flash",
    instruction="""You are a helpful personal assistant with memory capabilities.
    Use the search_memory function to recall past conversations and user preferences.
    Use the save_memory function to store important information about the user.
    Always personalize your responses based on available memory.""",
    description="A personal assistant that remembers user preferences and past interactions",
    tools=[search_memory_tool, save_memory_tool],

)
root_agent = agent_with_memory
