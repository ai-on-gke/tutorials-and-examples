import sys
import requests

# This fact exists only in ci-resources/llamaindex/rag/tests/sample-doc.md,
# the fixture document ingested for this test run - a fictional system with a
# specific fictional number, so a correct answer can only come from the RAG
# pipeline actually retrieving it, not from the model's own pretraining
# knowledge (which has never heard of "Zephyrion").
EXPECTED_SUBSTRING = "47"
QUERY = "What is the maximum retention period, in days, for archived snapshots in the Zephyrion Cloud Storage system?"


def test_rag_answer_uses_ingested_data(base_url):
    response = requests.get(f"{base_url}/invoke", params={"message": QUERY}, timeout=120)
    response.raise_for_status()  # Raise an HTTPError for bad responses (4xx or 5xx)
    body = response.json()
    print("Status Code:", response.status_code)
    print("Response Body:", body)

    answer = body.get("message", "")
    assert answer.strip(), f"Expected a non-empty answer, got: {body}"
    assert EXPECTED_SUBSTRING in answer, (
        f"Expected the answer to mention '{EXPECTED_SUBSTRING}' (from the ingested "
        f"test fixture), but got: {answer}"
    )


base_url = sys.argv[1]
test_rag_answer_uses_ingested_data(base_url)
print("llamaindex/rag test passed: answer correctly grounded in ingested document.")
