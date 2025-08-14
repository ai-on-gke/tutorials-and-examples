from typing import Dict, List

import requests


PROMPT_FMT_STRING="""<|begin_of_text|><|header_start|>user<|header_end|>

Task: Check if there is unsafe content in '{role}' messages in conversations according to our safety policy with the below categories.

<BEGIN UNSAFE CONTENT CATEGORIES>
S1: Violent Crimes. 
S2: Non-Violent Crimes. 
S3: Sex Crimes. 
S4: Child Exploitation. 
S5: Defamation. 
S6: Specialized Advice. 
S7: Privacy. 
S8: Intellectual Property. 
S9: Indiscriminate Weapons. 
S10: Hate. 
S11: Self-Harm. 
S12: Sexual Content. 
S13: Elections.
<END UNSAFE CONTENT CATEGORIES>

<BEGIN CONVERSATION>

{conversation}
<END CONVERSATION>

Provide your safety assessment for ONLY THE LAST '{role}' message in the above conversation:
- First line must read 'safe' or 'unsafe'.
- If unsafe, a second line must include a comma-separated list of violated categories.<|eot|><|header_start|>assistant<|header_end|>
"""


def verify_messages(
        messages: List[Dict], 
        role: str,
        base_url: str,
        model: str,
    ):


    llama_guard_prompt = _create_prompt(messages=messages, role=role)
    
    llama_guard_response = _post_request(
        url=f"{base_url}/chat/completions",
        model=model,
        prompt = llama_guard_prompt,
    )

    result_str = llama_guard_response["choices"][0]["message"]["content"].strip()

    result_lines = result_str.splitlines()

    safe = result_lines[0] == "safe"
    if safe:
        categories = None
    else:
        categories = result_lines[1].split(",")

    return safe, categories



def _create_prompt(messages: List[Dict], role: str):
    conversation_string = ""

    for message in messages:
        conversation_string = f"{conversation_string}{message['role']}: {message['content']}\n"

    prompt = PROMPT_FMT_STRING.format(
        conversation=conversation_string,
        role = role,
    )
    return prompt


def _post_request(
        url: str,
        model: str,
        prompt: str
    ):
    with requests.Session() as session:
        resp = session.post(
            url=url,
            json={
                "model": model,
                "messages": [
                    {
                        "role": "user",
                        "content": prompt,
                    }
                ]
            }
        )
    resp.raise_for_status()
    return resp.json()

