from google.adk.agents import LlmAgent
from google.adk.models.lite_llm import LiteLlm
from google.genai import types as genai_types 
import os

from google.adk.agents.callback_context import CallbackContext
from google.adk.models import LlmResponse, LlmRequest
from typing import Optional, Dict, List, Tuple

from . import llama_guard

LLAMA_GUARD_BASE_URL=os.getenv("LLAMA_GUARD_BASE_URL")

LLAMA_GUARD_MODEL_NAME = os.getenv("LLAMA_GUARD_MODEL_NAME")

LLM_BASE_URL = os.getenv("LLM_BASE_URL")

MODEL_NAME = os.getenv("MODEL_NAME")

def my_before_model_logic(
    callback_context: CallbackContext, llm_request: LlmRequest) -> Optional[LlmResponse]:
    
    messages = [
        {
            "content": callback_context.user_content.parts[0].text,
            "role": callback_context.user_content.role
        }
    ]

    return _verify_messages_with_llama_guard(
        messages=messages,
        role = messages[-1]["role"],
    )

def my_after_model_logic(
    callback_context: CallbackContext, llm_response: LlmResponse) -> Optional[LlmResponse]:

    messages = [
        {
            "content": callback_context.user_content.parts[0].text,
            "role": callback_context.user_content.role
        },
        {
            "content": llm_response.content.parts[0].text,
            "role": llm_response.content.role
        },

    ]
    return _verify_messages_with_llama_guard(
        messages=messages,
        role = messages[-1]["role"],
    )

secured_agent = LlmAgent(
    name="secured_llm",
    model = LiteLlm(
      api_base = LLM_BASE_URL,
      model = f"hosted_vllm/{MODEL_NAME}",
    ),
    instruction="You are a helpful assistant. Please respond to the user's query.",
    before_model_callback=my_before_model_logic,
    after_model_callback=my_after_model_logic,
)


def _verify_messages_with_llama_guard(messages: List[Dict], role: str) -> Optional[LlmResponse]:
    safe, categories = llama_guard.verify_messages(
        messages=messages,
        role = role,
        base_url=LLAMA_GUARD_BASE_URL,
        model=LLAMA_GUARD_MODEL_NAME,
    )
    if not safe:
        return LlmResponse(
            content=genai_types.Content(
                role="model",
                parts=[genai_types.Part(text="The prompt can not be processed. Please adjust it and try again.")]
            )
        )
    return None

root_agent = llama_agent
