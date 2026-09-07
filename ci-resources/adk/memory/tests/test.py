# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Proves memory actually round-trips through Mem0 + pgvector, not just that
# the pod answers requests: turn 1 (session A) tells the agent a fact and
# asserts save_memory was actually invoked; turn 2 happens in a brand-new
# ADK session (session B) with no shared conversation history, so recalling
# the fact is only possible if search_memory hits the CloudSQL-backed
# vector store - a fixed message index can't be assumed since the model is
# free to reason before/after calling either tool, so both turns scan every
# SSE event rather than indexing into it.

import json
import sys

import requests

FACT = "my favorite ice cream flavor is pistachio"
ANSWER = "pistachio"


def create_session(base_url, user_id):
    url = f"{base_url}/apps/agent_with_memory/users/{user_id}/sessions"
    response = requests.post(url, headers={"accept": "application/json"})
    response.raise_for_status()
    session_id = response.json()["id"]
    assert session_id is not None, "The session ID is None."
    return session_id


def send_message(base_url, user_id, session_id, text):
    url = f"{base_url}/run_sse"
    data = {
        "appName": "agent_with_memory",
        "userId": user_id,
        "sessionId": str(session_id),
        "newMessage": {"parts": [{"text": text}], "role": "user"},
        "streaming": False,
    }
    response = requests.post(
        url,
        headers={"accept": "application/json", "Content-Type": "application/json"},
        data=json.dumps(data),
    )
    response.raise_for_status()
    output = response.text.split("data: ")[1:]
    return [json.loads(i) for i in output]


def function_calls(messages, name):
    calls = []
    for message in messages:
        for part in message.get("content", {}).get("parts", []):
            call = part.get("functionCall")
            if call and call.get("name") == name:
                calls.append(call)
    return calls


def final_text(messages):
    texts = []
    for message in messages:
        for part in message.get("content", {}).get("parts", []):
            text = part.get("text")
            if text:
                texts.append(text)
    return "\n".join(texts)


base_url = sys.argv[1]
user_id = "1"

session_a = create_session(base_url, user_id)
messages_a = send_message(
    base_url, user_id, session_a, f"Please remember this about me: {FACT}."
)
save_calls = function_calls(messages_a, "save_memory")
assert save_calls, (
    f"Expected the agent to call save_memory while being told '{FACT}', "
    f"but no save_memory functionCall was seen. Events: {messages_a}"
)
print(f"save_memory was called with: {save_calls}")

session_b = create_session(base_url, user_id)
assert session_b != session_a, "Expected a fresh session, got the same session ID back."
messages_b = send_message(
    base_url, user_id, session_b, "What is my favorite ice cream flavor?"
)
search_calls = function_calls(messages_b, "search_memory")
assert search_calls, (
    "Expected the agent to call search_memory to answer a question about a fact "
    f"told in a different session, but no search_memory functionCall was seen. Events: {messages_b}"
)
print(f"search_memory was called with: {search_calls}")

answer = final_text(messages_b)
assert ANSWER in answer.lower(), (
    f"Expected the recalled fact ('{ANSWER}') to appear in the agent's response, "
    f"got: {answer!r}"
)
print(f"adk-memory test passed: fact saved in one session was recalled in a brand-new session via search_memory. Final answer: {answer!r}")
