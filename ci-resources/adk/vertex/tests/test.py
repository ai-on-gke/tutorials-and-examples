import sys
import requests
import json

def test_model_interaction(base_url):
    url = f'{base_url}/apps/capital_agent/users/1/sessions'
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
        "appName": "capital_agent",
        "userId": "1",
        "sessionId": str(session_id),
        "newMessage": {
            "parts": [
                {
                    "text": "what is the capital of Japan?"
                }
            ],
            "role": "user"
        },
        "streaming": False
    }

    expected_country = "Japan"
    expected_city  = "Tokyo"

    response = requests.post(url, headers=headers, data=json.dumps(data))
    response.raise_for_status()  # Raise an HTTPError for bad responses (4xx or 5xx)
    print("Status Code:", response.status_code)
    output = response.text.split("data: ")[1:]
    messages = [json.loads(i) for i in output]
    actual_country = messages[0]["content"]["parts"][0]["functionCall"]["args"]["country"]
    actual_city = messages[1]["content"]["parts"][0]["functionResponse"]["response"]["result"]
    actual_text_response = messages[2]["content"]["parts"][0]["text"]
    assert actual_country == expected_country, f"Error. The actual country({actual_country}) != the expected ({expected_country}) one."
    assert actual_city == expected_city, f"Error. The actual city({actual_city}) != the expected ({expected_city}) one."
    print(f"The actual text response: {actual_text_response}")
    assert actual_city in actual_text_response, f"Error. The actual city ({actual_city}) is not in the actual text response: {actual_text_response}"


base_url = sys.argv[1]
test_model_interaction(base_url)
