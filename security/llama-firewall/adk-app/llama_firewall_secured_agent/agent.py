from google.adk.agents import LlmAgent
from google.adk.models.lite_llm import LiteLlm
from google.genai import types as genai_types 
import os

from google.adk.agents.callback_context import CallbackContext
from google.adk.models import LlmResponse, LlmRequest
from typing import Optional, Dict, List


from llamafirewall import LlamaFirewall, UserMessage, AssistantMessage, Role, ScannerType, Trace, ScanDecision

LLM_BASE_URL = os.getenv("LLM_BASE_URL", "http://localhost:11434")

MODEL_NAME = os.getenv("MODEL_NAME", "llama3.2:1b")


# Initialize LlamaFirewall with AlignmentCheckScanner
firewall = LlamaFirewall(
    scanners={
            Role.USER: [
                ScannerType.PROMPT_GUARD,
                ScannerType.CODE_SHIELD,
                ScannerType.HIDDEN_ASCII,
                ScannerType.REGEX,
            ],
            Role.ASSISTANT: [ScannerType.PROMPT_GUARD],
        }
)

def my_before_model_logic(
    callback_context: CallbackContext, llm_request: LlmRequest) -> Optional[LlmResponse]:
    
    messages = [
        {
            "content": callback_context.user_content.parts[0].text,
            "role": callback_context.user_content.role
        }
    ]

    return _verify_messages_with_llama_firewall(
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
    print("after")
    return _verify_messages_with_llama_firewall(
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


async def _verify_messages_with_llama_firewall(messages: List[Dict], role: str) -> Optional[LlmResponse]:

    conversation_trace = []
    for msg in messages: 
        role_cls = UserMessage if msg["role"] == "user" else AssistantMessage
        conversation_trace.append(
            role_cls(content=msg["content"])
        )

    print(conversation_trace)
    result = await firewall.scan_replay_async(conversation_trace)
    print(result)


    if result.decision == ScanDecision.BLOCK:
        return LlmResponse(
            content=genai_types.Content(
                role="model",
                parts=[genai_types.Part(text="The prompt can not be processed. Please adjust it and try again.")]
            )
        )
    return None

root_agent = secured_agent
