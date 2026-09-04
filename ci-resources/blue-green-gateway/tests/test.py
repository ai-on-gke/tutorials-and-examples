import sys
import time
import requests

# The Gateway's HTTPRoute injects a distinctive X-Response-Service response
# header (see blue-route.yaml / green-route.yaml) - checking it is a more
# precise assertion than inspecting the chat completion text, since it proves
# the *routing* switched backends, not just that some vLLM instance answered.


def wait_for_expected_backend(gateway_ip, expected_service, timeout=180):
    url = f"http://{gateway_ip}/v1/chat/completions"
    payload = {
        "model": "google/gemma-3-1b-it",
        "messages": [{"role": "user", "content": "What is a blue-green deployment?"}],
        "max_tokens": 50,
    }
    deadline = time.time() + timeout
    last_seen = None
    while time.time() < deadline:
        try:
            response = requests.post(url, json=payload, timeout=30)
            response.raise_for_status()  # Raise an HTTPError for bad responses (4xx or 5xx)
            last_seen = response.headers.get("X-Response-Service")
            print(f"Got X-Response-Service={last_seen}, status={response.status_code}")
            if last_seen == expected_service:
                body = response.json()
                content = body.get("choices", [{}])[0].get("message", {}).get("content", "")
                assert content.strip(), "vLLM returned an empty completion."
                return
        except requests.exceptions.RequestException as e:
            print(f"Request failed ({e}), retrying...")
        time.sleep(5)
    raise AssertionError(
        f"Timed out waiting for X-Response-Service='{expected_service}' "
        f"(load balancer route propagation) - last saw '{last_seen}'."
    )


gateway_ip = sys.argv[1]
phase = sys.argv[2]  # "blue" or "green" - which switch to verify in this invocation
if phase == "blue":
    wait_for_expected_backend(gateway_ip, "blue-service")
    print("blue-green-gateway test passed: blue environment is live and serving.")
elif phase == "green":
    wait_for_expected_backend(gateway_ip, "green-service")
    print("blue-green-gateway test passed: traffic successfully switched to green.")
else:
    print(f"Unknown phase '{phase}', expected 'blue' or 'green'.")
    sys.exit(1)
