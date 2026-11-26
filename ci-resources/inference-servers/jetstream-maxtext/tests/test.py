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

import sys
import time
import requests


def wait_for_generation(base_url, timeout=300):
    url = f"{base_url}/generate"
    payload = {
        "prompt": "What are the top 5 programming languages",
        "max_tokens": 200,
    }
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.post(url, json=payload, timeout=60)
            if response.status_code == 200:
                return response.json()
            last_error = f"HTTP {response.status_code}: {response.text[:200]}"
        except requests.exceptions.RequestException as e:
            last_error = str(e)
        print(f"Not ready yet ({last_error}), retrying...")
        time.sleep(10)
    raise AssertionError(f"Server never returned a successful response. Last error: {last_error}")


base_url = sys.argv[1]
body = wait_for_generation(base_url)
print("Response body:", body)
response_text = body.get("response", "")
assert response_text.strip(), f"Expected non-empty generated text in 'response', got: {body}"
print("jetstream-maxtext test passed: maxengine server served a real completion for a real prompt.")
