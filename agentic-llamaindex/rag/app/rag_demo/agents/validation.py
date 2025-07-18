from typing import List, Dict
from llama_index.llms.ollama import Ollama

class ValidationAgent:
    def __init__(self, llm: Ollama):
        self.llm = llm

    def validate(self, original_query: str, recommendations: List[Dict]) -> bool:
        titles = [
            (rec.get("title") or "<unknown>") 
            for rec in recommendations 
            if rec.get("title") is not None
        ]
        if not titles:
            return False

        prompt = (
            f"You are a validation assistant for a movie recommendation system.\n\n"
            f"The user query was: \"{original_query}\"\n"
            f"The system returned these movie titles: {', '.join(titles)}\n\n"
            "Do these recommendations accurately match the intent of the original query? "
            "Answer with YES or NO."
        )

        resp = self.llm.complete(prompt)
        answer = resp.text.strip().lower()
        return answer.startswith("yes")