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

import uvicorn
from fastapi import FastAPI
from google.adk.cli.fast_api import get_fast_api_app
import psycopg2

# Get the directory where main.py is located
AGENT_DIR = os.path.dirname(os.path.abspath(__file__))
# Example allowed origins for CORS
ALLOWED_ORIGINS = ["http://localhost", "http://localhost:8080", "*"]
# Set web=True if you intend to serve a web interface, False otherwise
SERVE_WEB_INTERFACE = True

SESSION_DB_NAME = os.environ["SESSION_DB_NAME"]
SESSION_DB_HOST = os.environ["SESSION_DB_HOST"]
SESSION_DB_USER = os.environ["SESSION_DB_USER"]
SESSION_DB_PASSWORD = os.environ["SESSION_DB_PASSWORD"]

VECTOR_DB_NAME = os.environ["VECTOR_DB_NAME"]
VECTOR_DB_HOST = os.environ["VECTOR_DB_HOST"]
VECTOR_DB_USER = os.environ["VECTOR_DB_USER"]
VECTOR_DB_PASSWORD = os.environ["VECTOR_DB_PASSWORD"]

SESSION_DB_URL = f"postgresql://{SESSION_DB_USER}:{SESSION_DB_PASSWORD}@{SESSION_DB_HOST}:5432/{SESSION_DB_NAME}"
VECTOR_DB_URL = f"postgresql://{VECTOR_DB_USER}:{VECTOR_DB_PASSWORD}@{VECTOR_DB_HOST}:5432/{VECTOR_DB_NAME}"


# Create vector extension in the memory database
conn = psycopg2.connect(VECTOR_DB_URL)
cur = conn.cursor()
try:
    cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
    conn.commit()  # Commit the transaction
    print(f"Extension 'vector' created successfully.")
except psycopg2.Error as e:
    conn.rollback()  # Rollback in case of error
    print(f"Error creating extension: {e}")

# Call the function to get the FastAPI app instance
# Ensure the agent directory name ('capital_agent') matches your agent folder
app: FastAPI = get_fast_api_app(
    agents_dir=AGENT_DIR,
    session_service_uri=SESSION_DB_URL,
    allow_origins=ALLOWED_ORIGINS,
    web=SERVE_WEB_INTERFACE,
)

# You can add more FastAPI routes or configurations below if needed
# Example:
# @app.get("/hello")
# async def read_root():
#     return {"Hello": "World"}

if __name__ == "__main__":
    # Use the PORT environment variable provided by Cloud Run, defaulting to 8080
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
