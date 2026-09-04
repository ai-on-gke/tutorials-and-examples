import sys
import requests


def test_tgi_generate(base_url):
    url = f"{base_url}/generate"
    payload = {
        "inputs": "[INST]What is Kubernetes? Answer in one sentence.[/INST]",
        "parameters": {"max_new_tokens": 100},
    }
    response = requests.post(url, json=payload, timeout=120)
    response.raise_for_status()  # Raise an HTTPError for bad responses (4xx or 5xx)
    body = response.json()
    print("Status Code:", response.status_code)
    print("Response Body:", body)

    generated_text = body.get("generated_text", "")
    assert generated_text.strip(), f"TGI returned an empty completion. Full response: {body}"
    print(f"Generated text: {generated_text}")


base_url = sys.argv[1]
test_tgi_generate(base_url)
print("hugging-face-tgi test passed: Mistral-7B-Instruct served a real generation.")
