import sys
import requests
import json

def test_model_interaction(base_url):
    app_name = "weather_agent"
    user_id = "user1"
    url = f'{base_url}/apps/{app_name}/users/{user_id}/sessions'
    headers = {
        'accept': 'application/json',
        'Content-Type': 'application/json'
    }

    session_id = None
    response = requests.post(url, headers=headers)
    response.raise_for_status()  # Raise an HTTPError for bad responses (4xx or 5xx)
    session_id = response.json()["id"]
    print("Status Code:", response.status_code)
    print("Response Body:", response.json())


    assert session_id is not None, "The Session ID is None."

    url = f'{base_url}/run_sse'
    headers = {
        'accept': 'application/json',
        'Content-Type': 'application/json'
    }

    data = {
        "app_name": app_name,
        "user_id": user_id,
        "session_id": str(session_id),
        "new_message": {
            "parts": [
                {
                    "text": f"What is the weather like in San Francisco?"
                }
            ],
            "role": "user"
        },
        "streaming": False
    }

    response = requests.post(url, headers=headers, data=json.dumps(data))
    response.raise_for_status()  # Raise an HTTPError for bad responses (4xx or 5xx)
    print("Status Code:", response.status_code, "\n\n")
    print("Status Text:", response.text, "\n\n")
    print("PASS")


base_url = sys.argv[1]
test_model_interaction(base_url)
