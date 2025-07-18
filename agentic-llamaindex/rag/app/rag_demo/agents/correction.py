import json
import logging
from typing import List, Dict
from llama_index.llms.ollama import Ollama

logger = logging.getLogger(__name__)

class CorrectionAgent:
    def __init__(self, llm: Ollama):
        self.llm = llm

    def correct(self, original_query: str, recommendations: List[Dict]) -> List[Dict]:
        # Prepare existing recommendations for context
        recs_list = []
        for rec in recommendations:
            title = rec.get("title") or "<unknown>"
            overview = rec.get("overview", "")
            recs_list.append(f"{title}: {overview}")
        recs_str = "\n".join(recs_list) if recs_list else "<no recommendations>"

        prompt = (
            "You are a correction assistant for a movie recommendation system.\n\n"
            f"The user query was: \"{original_query}\"\n"
            f"The system's previous recommendations were:\n{recs_str}\n\n"
            "They did not fully match the user's intent. "
            "Please generate a NEW list of up to 3 relevant movies. "
            "For each, provide a JSON object with keys: "
            "title, imdb_rating, overview, genre, released_year, director, stars. "
            "Return the complete JSON array."
        )

        # Call Ollama properly via .complete() and extract the text
        resp = self.llm.complete(prompt)
        text = resp.text.strip()

        # parse the JSON output
        try:
            corrected = json.loads(text)
            if isinstance(corrected, list):
                return corrected
        except json.JSONDecodeError as e:
            logger.error(f"CorrectionAgent JSON parse error: {e}")

        # Fallback: return the original recommendations unmodified
        return recommendations