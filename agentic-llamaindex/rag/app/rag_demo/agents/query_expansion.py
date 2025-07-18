from llama_index.llms.ollama import Ollama

class QueryExpander:
    def __init__(self, llm: Ollama):
        self.llm = llm

    def expand(self, query: str) -> str:
        prompt = (
            "You are a helpful assistant that generates related search terms for "
            "a movie recommendation query.\n\n"
            f"Original query: \"{query}\"\n\n"
            "Give me a comma-separated list of 3–5 expanded queries or keywords."
        )
        # call the LLM and extract its .text
        resp = self.llm.complete(prompt)
        return resp.text.strip()