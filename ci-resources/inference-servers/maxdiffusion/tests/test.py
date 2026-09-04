import sys
import time
import requests

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def test_sdxl_generate(base_url, timeout=1200):
    """The server compiles the SDXL pipeline at startup (before Uvicorn even
    starts listening), which can take several minutes on a single TPU chip -
    so this polls with retries rather than assuming the server is ready the
    moment the pod is Running.
    """
    url = f"{base_url}/generate"
    payload = {"prompt": "a small red bicycle leaning against a brick wall"}

    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.post(url, json=payload, timeout=120)
            if response.status_code == 200:
                break
            last_error = f"HTTP {response.status_code}: {response.text[:200]}"
        except requests.exceptions.RequestException as e:
            last_error = str(e)
        print(f"Not ready yet ({last_error}), retrying...")
        time.sleep(20)
    else:
        raise AssertionError(f"Server never returned a successful response. Last error: {last_error}")

    content = response.content
    print(f"Response status: {response.status_code}, content-type: {response.headers.get('content-type')}, bytes: {len(content)}")
    assert content.startswith(PNG_MAGIC), (
        f"Expected a PNG image (magic bytes {PNG_MAGIC!r}), got {content[:16]!r} "
        f"({len(content)} bytes total)"
    )
    assert len(content) > 10_000, f"PNG response suspiciously small ({len(content)} bytes) - likely not a real image."


base_url = sys.argv[1]
test_sdxl_generate(base_url)
print("inference-servers/maxdiffusion test passed: SDXL served a real PNG image from a TPU chip.")
