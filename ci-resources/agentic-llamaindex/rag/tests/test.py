import sys
import requests

# This movie exists only in ci-resources/agentic-llamaindex/rag/tests/sample-movies.csv,
# the tiny fixture dataset ingested for this test run. It's a fictional title with a
# distinctive, specific plot, so a correct response can only come from the RAG pipeline
# actually retrieving it from the vector store - not from the model's own pretraining
# knowledge (which has never heard of "The Cosmic Voyager"). That makes this a genuine
# end-to-end check of ingestion -> embedding -> Redis retrieval -> recommendation.
EXPECTED_TITLE = "The Cosmic Voyager"
QUERY = (
    "Recommend a science fiction movie about an astronaut who pilots a starship "
    "through a wormhole to find a new habitable planet for humanity."
)


def test_recommendation_uses_ingested_data(base_url):
    response = requests.get(f"{base_url}/recommend", params={"query": QUERY}, timeout=120)
    response.raise_for_status()  # Raise an HTTPError for bad responses (4xx or 5xx)
    body = response.json()
    print("Status Code:", response.status_code)
    print("Response Body:", body)

    recommendations = body.get("recommendations", [])
    assert recommendations, (
        f"Expected at least one recommendation, got none. Full response: {body}"
    )

    titles = [rec.get("title") for rec in recommendations]
    assert EXPECTED_TITLE in titles, (
        f"Expected '{EXPECTED_TITLE}' (from the ingested test fixture) among the "
        f"recommendations, but got: {titles}"
    )


base_url = sys.argv[1]
test_recommendation_uses_ingested_data(base_url)
print("agentic-llamaindex/rag test passed: recommendation correctly grounded in ingested data.")
