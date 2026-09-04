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
# CAVEAT: this is the most speculative pipeline built this session. n8n has
# no documented public API for owner bootstrap/credential creation/workflow
# activation from a fresh instance, so this drives n8n's internal `/rest/*`
# API (the same one the n8n editor UI itself calls) end to end: owner setup,
# credential creation, workflow import, activation, and finally the Chat
# Trigger node's production webhook contract. None of these request/response
# shapes have been verified against a live n8n instance from this
# environment - they're inferred from n8n's known internal API conventions.

import json
import sys
import time

import requests


def _request_with_retry(session, method, url, timeout=60, retry_timeout=60, **kwargs):
    # n8n's REST API does DB writes on first boot; right after the
    # port-forward comes up it may not be accepting connections yet.
    deadline = time.time() + retry_timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = session.request(method, url, timeout=timeout, **kwargs)
            response.raise_for_status()
            return response
        except requests.exceptions.RequestException as e:
            last_error = str(e)
            print(f"Request to {url} failed ({last_error}), retrying...")
            time.sleep(5)
    raise AssertionError(f"Request to {url} never succeeded. Last error: {last_error}")


def setup_owner(session, base_url):
    url = f"{base_url}/rest/owner/setup"
    payload = {
        "email": "ci-test@example.com",
        "firstName": "CI",
        "lastName": "Test",
        "password": "CiTestPassword123!",
    }
    response = _request_with_retry(session, "POST", url, json=payload)
    return response.json()


def create_credential(session, base_url, name, cred_type, data):
    url = f"{base_url}/rest/credentials"
    payload = {"name": name, "type": cred_type, "data": data}
    response = _request_with_retry(session, "POST", url, json=payload)
    return response.json()["data"]["id"]


def import_and_activate_workflow(session, base_url, workflow):
    create_response = _request_with_retry(session, "POST", f"{base_url}/rest/workflows", json=workflow)
    created = create_response.json()["data"]
    workflow_id = created["id"]

    created["active"] = True
    _request_with_retry(session, "PATCH", f"{base_url}/rest/workflows/{workflow_id}", json=created)

    return workflow_id


def find_chat_trigger_webhook_id(workflow):
    for node in workflow["nodes"]:
        if node["type"] == "@n8n/n8n-nodes-langchain.chatTrigger":
            return node["webhookId"]
    raise AssertionError("No chat trigger node found in the workflow.")


def ask_chat(base_url, webhook_id, message, timeout=180):
    url = f"{base_url}/webhook/{webhook_id}/chat"
    payload = {"chatInput": message, "sessionId": "ci-test-session", "action": "sendMessage"}
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.post(url, json=payload, timeout=60)
            if response.status_code == 200:
                return response.json()
            last_error = f"HTTP {response.status_code}: {response.text[:300]}"
        except requests.exceptions.RequestException as e:
            last_error = str(e)
        print(f"Chat webhook not ready yet ({last_error}), retrying...")
        time.sleep(10)
    raise AssertionError(f"Chat webhook never returned a usable response. Last error: {last_error}")


def test_n8n_agent(base_url, db_host, db_port, db_name, db_user, db_password, table_name, workflow_path):
    session = requests.Session()

    setup_owner(session, base_url)

    postgres_cred_id = create_credential(
        session, base_url, "Postgres account", "postgres",
        {
            "host": db_host,
            "port": int(db_port),
            "database": db_name,
            "user": db_user,
            "password": db_password,
            "ssl": "disable",
        },
    )
    ollama_cred_id = create_credential(
        session, base_url, "Ollama account", "ollamaApi",
        {"baseUrl": "http://ollama:11434"},
    )

    with open(workflow_path) as f:
        workflow = json.load(f)

    for node in workflow["nodes"]:
        if node["type"] == "n8n-nodes-base.postgresTool":
            node["credentials"]["postgres"]["id"] = postgres_cred_id
        elif node["type"] == "@n8n/n8n-nodes-langchain.lmChatOllama":
            node["credentials"]["ollamaApi"]["id"] = ollama_cred_id

    webhook_id = find_chat_trigger_webhook_id(workflow)
    import_and_activate_workflow(session, base_url, workflow)

    # The seeded table name is a fictional, made-up identifier (see
    # ci-resources/n8n/cloudbuild.yaml's "n8n: seed database" step) so a
    # correct answer can only come from the AI Agent actually calling the
    # Postgres tool against the real database, not from the model's
    # pretraining knowledge - same grounding technique used by the
    # agentic-llamaindex/rag and llamaindex/rag tests.
    reply = ask_chat(base_url, webhook_id, "Which tables are available?")
    print("Chat reply:", reply)
    output = reply.get("output") or reply.get("text") or str(reply)
    assert table_name.lower() in output.lower(), (
        f"Expected the AI Agent's reply to mention the real table '{table_name}' "
        f"(proving it actually queried Postgres), got: {output}"
    )


base_url, db_host, db_port, db_name, db_user, db_password, table_name, workflow_path = sys.argv[1:9]
test_n8n_agent(base_url, db_host, db_port, db_name, db_user, db_password, table_name, workflow_path)
print("n8n test passed: the imported chat workflow used the Ollama Chat Model + Postgres tool combination to correctly enumerate a real table in the database.")
