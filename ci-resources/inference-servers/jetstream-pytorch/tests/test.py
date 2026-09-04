import sys
import requests


def test_jetstream_pytorch_generate(base_url):
    url = f"{base_url}/generate"
    payload = {
        "prompt": "What are the top 5 programming languages",
        "max_tokens": 50,
    }
    # The README notes the first request can take several seconds due to
    # model warmup/compilation.
    response = requests.post(url, json=payload, timeout=180)
    response.raise_for_status()  # Raise an HTTPError for bad responses (4xx or 5xx)
    body = response.json()
    print("Status Code:", response.status_code)
    print("Response Body:", body)

    generated_text = body.get("response", "")
    assert generated_text.strip(), f"JetStream/PyTorch returned an empty completion. Full response: {body}"
    print(f"Generated text: {generated_text}")


base_url = sys.argv[1]
test_jetstream_pytorch_generate(base_url)
print("jetstream/pytorch test passed: Gemma-2b served a real generation on TPU.")
