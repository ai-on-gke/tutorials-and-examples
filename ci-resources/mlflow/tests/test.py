import sys
import time
import requests


def test_finetuned_model_serves(base_url, timeout=600):
    url = f"{base_url}/predict"
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(url, params={"message": "Question: How many users are there?\nContext: CREATE TABLE users (id INT, name TEXT)\nAnswer:"}, timeout=60)
            if response.status_code == 200:
                break
            last_error = f"HTTP {response.status_code}: {response.text[:200]}"
        except requests.exceptions.RequestException as e:
            last_error = str(e)
        print(f"Not ready yet ({last_error}), retrying...")
        time.sleep(15)
    else:
        raise AssertionError(f"Server never returned a successful response. Last error: {last_error}")

    body = response.json()
    print("Response body:", body)
    # mlflow.transformers' pyfunc wrapper for a text-generation pipeline
    # returns a list of {"generated_text": "..."} dicts.
    assert body, "Expected a non-empty response from the fine-tuned model."
    assert isinstance(body, list) and "generated_text" in body[0], (
        f"Expected a list of {{'generated_text': ...}} dicts, got: {body}"
    )
    generated_text = body[0]["generated_text"]
    assert generated_text and generated_text.strip(), (
        f"Expected non-empty generated text, got: {body}"
    )


base_url = sys.argv[1]
test_finetuned_model_serves(base_url)
print("mlflow test passed: fine-tuned model logged to MLflow was deployed and served a real completion.")
