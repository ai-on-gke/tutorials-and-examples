import os
import logging
import sys
import argparse
import traceback

from typing import Dict, Optional, Any

from fastapi import FastAPI
from starlette.requests import Request
from starlette.responses import StreamingResponse, JSONResponse

from ray import serve

from vllm.engine.arg_utils import AsyncEngineArgs
from vllm.engine.async_llm_engine import AsyncLLMEngine
from vllm.entrypoints.chat_utils import load_chat_template
from vllm.entrypoints.openai.cli_args import make_arg_parser
from vllm.entrypoints.openai.protocol import (
    ChatCompletionRequest,
    ChatCompletionResponse,
    ErrorResponse,
)
from vllm.entrypoints.openai.serving_chat import OpenAIServingChat
from vllm.entrypoints.openai.serving_models import OpenAIServingModels, BaseModelPath

logger = logging.getLogger("ray.serve")
handler = logging.StreamHandler(sys.stdout)
handler.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler.setFormatter(formatter)
if not logger.handlers:
    logger.addHandler(handler)
logger.setLevel(logging.INFO)

app = FastAPI()

@app.get("/-/healthz")
async def global_health_check():
    """Basic liveness check for the FastAPI application server."""
    return {"status": "success"}

@serve.deployment(name="VLLMDeployment")
@serve.ingress(app)
class VLLMDeployment:
    def __init__(
        self,
        engine_args: AsyncEngineArgs,
        chat_template: Optional[str] = None,
        enable_auto_tools: bool = True,
        tool_parser_name: str = "llama3_json",
    ):
        logger.info(f"Starting VLLMDeployment with engine args: {engine_args}")

        self.engine_args = engine_args
        self.chat_template = chat_template
        self.enable_auto_tools = enable_auto_tools
        self.tool_parser_name = tool_parser_name

        logger.info("Initializing AsyncLLMEngine...")
        self.engine = AsyncLLMEngine.from_engine_args(engine_args)
        logger.info("AsyncLLMEngine initialized successfully")

        self.openai_serving_chat: Optional[OpenAIServingChat] = None
        self.models: Optional[OpenAIServingModels] = None


    @app.post("/v1/chat/completions")
    async def create_chat_completion(
        self, request: ChatCompletionRequest, raw_request: Request
    ):
        """Handle chat requests with OpenAI-compatible response format."""

        if not self.openai_serving_chat:
            try:
                model_config = await self.engine.get_model_config()
                model = self.engine_args.model

                logger.info("Initializing OpenAIServingModels...")
                self.models = OpenAIServingModels(
                    engine_client=self.engine,
                    model_config=model_config,
                    base_model_paths=[BaseModelPath(name=model, model_path=model)],
                )
                logger.info("OpenAIServingModels initialized successfully.")

                logger.info("Initializing OpenAIServingChat...")
                self.openai_serving_chat = OpenAIServingChat(
                    engine_client=self.engine,
                    model_config=model_config,
                    models=self.models,
                    request_logger=None,
                    chat_template=self.chat_template,
                    chat_template_content_format="jinja",
                    enable_auto_tools=self.enable_auto_tools,
                    tool_parser=self.tool_parser_name,
                    response_role="assistant"
                )
                logger.info("OpenAIServingChat initialized successfully.")

            except Exception as e:
                logger.error(f"Error during initialization: {str(e)}\n{traceback.format_exc()}")
                return JSONResponse(
                    content=ErrorResponse(message=f"Server initialization error: {str(e)}", type="InternalServerError", code=500).model_dump(),
                    status_code=500
                )
        
        generator = await self.openai_serving_chat.create_chat_completion(request, raw_request)

        if isinstance(generator, ErrorResponse):
            logger.error(f"Error response from chat completion: {generator.model_dump()}")
            return JSONResponse(
                content=generator.model_dump(), status_code=generator.code
            )

        if request.stream:
            logger.info("Returning streaming response")
            return StreamingResponse(content=generator, media_type="text/event-stream")
        else:
            logger.info("Returning non-streaming response")
            if isinstance(generator, ChatCompletionResponse) and hasattr(generator, "model_dump"):
                return JSONResponse(content=generator.model_dump())
            else:
                logger.error(f"Unexpected non-streaming response type: {type(generator)}")
                error_response_content = ErrorResponse(
                    message="Invalid response type from model processing.",
                    type="InternalServerError",
                    code=500
                ).model_dump()
                return JSONResponse(content=error_response_content, status_code=500)


def parse_vllm_args(cli_args: Dict[str, Any]):
    """Parses vLLM AsyncEngineArgs args based on CLI inputs."""
    parser = argparse.ArgumentParser()
    make_arg_parser(parser)

    arg_strings = []
    for key, value in cli_args.items():
        arg_strings.extend([f"--{key}", str(value)])
    parsed_args = parser.parse_args(args=arg_strings)
    return parsed_args


def build_app() -> serve.Application:
    """
    Build the Ray Serve application for vLLM model serving.

    Returns:
        serve.Application: Configured Ray Serve application
    """
    # Read configuration from environment variables
    config = {
        "model": os.environ.get('MODEL_ID', "meta-llama/Llama-3.1-8B-Instruct"),
        "tensor-parallel-size": os.environ.get('TENSOR_PARALLELISM', "2"),
        "max-model-len": os.environ.get("MAX_MODEL_LEN", "4096"),
    }
    parsed_args = parse_vllm_args(config)
    engine_args = AsyncEngineArgs.from_cli_args(parsed_args)

    engine_args.worker_use_ray = True
    engine_args.trust_remote_code = True
    engine_args.enable_chunked_prefill = True

    enable_auto_tools_env = os.environ.get('VLLM_ENABLE_AUTO_TOOL_CHOICE', 'true')
    tool_parser_name_env = os.environ.get('TOOL_PARSER_NAME', 'llama3_json')
    chat_template_path = os.environ.get('CHAT_TEMPLATE_PATH')

    # Load chat template if path exists
    chat_template = None
    if chat_template_path:
        try:
            logger.info(f"Loading chat template from: {chat_template_path}")
            chat_template = load_chat_template(chat_template_path, is_literal=False)
            logger.info("Chat template loaded successfully")
        except Exception as e:
            error_msg = f"Failed to load chat template from {chat_template_path}: {str(e)}"
            logger.error(f"{error_msg}\n{traceback.format_exc()}")
            raise RuntimeError(error_msg) from e
    else:
        logger.info("No chat template path provided, using default template")

    return VLLMDeployment.bind(
        engine_args,
        chat_template,
        enable_auto_tools=enable_auto_tools_env,
        tool_parser_name=tool_parser_name_env
    )

logger.info("Setting up vLLM Ray Serve application...")
model = build_app()
logger.info("Ray Serve application 'model' has been built successfully.")