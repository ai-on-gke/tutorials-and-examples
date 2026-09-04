import sys
import requests


def test_vllm_chat_completion(base_url, model_id):
    url = f"{base_url}/v1/chat/completions"
    payload = {
        "model": model_id,
        "messages": [
            {"role": "user", "content": "In one short sentence, what is Kubernetes?"}
        ],
        "max_tokens": 100,
    }
    response = requests.post(url, json=payload, timeout=120)
    response.raise_for_status()  # Raise an HTTPError for bad responses (4xx or 5xx)
    body = response.json()
    print("Status Code:", response.status_code)
    print("Response Body:", body)

    choices = body.get("choices", [])
    assert choices, f"Expected at least one choice in the response, got: {body}"
    content = choices[0].get("message", {}).get("content", "")
    assert content.strip(), "vLLM returned an empty completion."
    print(f"Completion: {content}")


base_url = sys.argv[1]
model_id = sys.argv[2]
test_vllm_chat_completion(base_url, model_id)
print("autoscale test passed: vLLM served a real chat completion.")
