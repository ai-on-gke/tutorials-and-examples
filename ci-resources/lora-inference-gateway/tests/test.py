import re
import sys
import time
import requests

# Requires an actual SELECT ... FROM statement shape, not just both words
# appearing anywhere - a plain-English reply can easily contain "select" and
# "from" independently (e.g. "you could select any of these cities, away
# from the coast, ...") without ever being SQL.
SQL_PATTERN = re.compile(r"select\b.{0,200}?\bfrom\b", re.IGNORECASE | re.DOTALL)


def wait_for_response(gateway_ip, model, message, timeout=180):
    url = f"http://{gateway_ip}/v1/chat/completions"
    payload = {"model": model, "messages": [{"role": "user", "content": message}]}
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.post(url, json=payload, timeout=30)
            if response.status_code == 200:
                body = response.json()
                content = body.get("choices", [{}])[0].get("message", {}).get("content", "")
                if content.strip():
                    return content
            last_error = f"HTTP {response.status_code}: {response.text[:200]}"
        except requests.exceptions.RequestException as e:
            last_error = str(e)
        print(f"Not ready yet ({last_error}), retrying...")
        time.sleep(10)
    raise AssertionError(f"Never got a usable response for model={model!r}. Last error: {last_error}")


def test_base_and_lora_routing(gateway_ip):
    print("=== Querying the base Gemma model ===")
    base_reply = wait_for_response(
        gateway_ip, "google/gemma-3-1b-it", "What is the meaning of life?"
    )
    print(f"Base model reply: {base_reply}")

    print("=== Querying the sql-chat LoRA adapter ===")
    lora_reply = wait_for_response(
        gateway_ip, "sql-chat", "List the three largest cities in Texas by population."
    )
    print(f"sql-chat reply: {lora_reply}")

    assert SQL_PATTERN.search(lora_reply), (
        f"Expected the sql-chat LoRA adapter to respond with a SELECT ... FROM "
        f"statement, but got: {lora_reply}"
    )
    # If the base model's plain-English reply also looks like SQL, that's a
    # sign both requests landed on the same backend rather than routing
    # separately through the adapter.
    assert not SQL_PATTERN.search(base_reply), (
        "Expected the base model's reply to NOT look like SQL - if it does, "
        f"the LoRA adapter may not be routing separately from the base model. "
        f"Base reply: {base_reply}"
    )


gateway_ip = sys.argv[1]
test_base_and_lora_routing(gateway_ip)
print("lora-inference-gateway test passed: base model and sql-chat LoRA adapter both routed and responded correctly.")
