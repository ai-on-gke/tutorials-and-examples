import re
import logging
from typing import List, Dict
from .query_expansion import QueryExpander
from .validation import ValidationAgent
from .correction import CorrectionAgent

logger = logging.getLogger(__name__)

# compile this once at module load
_PAT = re.compile(
    r"Title:\s*(?P<title>.+)\n"
    r"Year:\s*(?P<year>\d+)\n"
    r"Genre:\s*(?P<genre>.+)\n"
    r"IMDb Rating:\s*(?P<rating>[\d\.]+)\n"
    r"Overview:\s*(?P<overview>.+)\n"
    r"Director:\s*(?P<director>.+)\n"
    r"Stars:\s*(?P<stars>.+)",
    re.DOTALL
)

class MultiStepCoordinator:
    def __init__(
        self,
        expander: QueryExpander, 
        query_engine,
        validator: ValidationAgent,
        corrector: CorrectionAgent,
        max_steps: int = 3,
    ):
        self.expander = expander
        self.query_engine = query_engine
        self.validator = validator
        self.corrector = corrector
        self.max_steps = max_steps

    async def run(self, user_query: str) -> Dict:
        current_query = user_query
        recommendations: List[Dict] = []

        for step in range(1, self.max_steps + 1):
            logger.info(f"[Step {step}] Expanding query: {current_query}")
            expanded = self.expander.expand(current_query)

            # call LlamaIndex query engine
            resp = self.query_engine.query(expanded)

            # metadata‐parsing:
            recs: List[Dict] = []
            for node_with_score in resp.source_nodes:
                text_blob = node_with_score.node.get_content()
                m = _PAT.search(text_blob)
                if not m:
                    continue
                recs.append({
                    "title": m.group("title").strip(),
                    "imdb_rating": float(m.group("rating").strip()),
                    "overview": m.group("overview").strip(),
                    "genre": m.group("genre").strip(),
                    "released_year": int(m.group("year").strip()),
                    "director": m.group("director").strip(),
                    "stars": [s.strip() for s in m.group("stars").split(",")]
                })

            logger.info(f"Got {len(recs)} recs; validating…")
            if self.validator.validate(user_query, recs):
                recommendations = recs
                break

            logger.info("Validation failed; correcting…")
            current_query = f"{user_query} | corrected"
            recommendations = self.corrector.correct(user_query, recs)

        return {
            "message": "Here are the movie recommendations after refinement:",
            "recommendations": recommendations
        }