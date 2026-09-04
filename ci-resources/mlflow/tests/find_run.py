import sys
import requests

# Looks up the finished run via the MLflow REST API and prints its run_id to
# stdout (nothing else), so the calling shell script can capture it directly
# and use it to render deploy.yaml's MODEL_PATH.


def find_finished_run(mlflow_url, experiment_name):
    exp_resp = requests.get(
        f"{mlflow_url}/api/2.0/mlflow/experiments/get-by-name",
        params={"experiment_name": experiment_name},
        timeout=30,
    )
    exp_resp.raise_for_status()  # Raise an HTTPError for bad responses (4xx or 5xx)
    experiment_id = exp_resp.json()["experiment"]["experiment_id"]

    search_resp = requests.post(
        f"{mlflow_url}/api/2.0/mlflow/runs/search",
        json={"experiment_ids": [experiment_id], "max_results": 5,
              "order_by": ["attribute.start_time DESC"]},
        timeout=30,
    )
    search_resp.raise_for_status()  # Raise an HTTPError for bad responses (4xx or 5xx)
    runs = search_resp.json().get("runs", [])
    assert runs, f"No runs found for experiment '{experiment_name}' (id={experiment_id})"

    run = runs[0]
    status = run["info"]["status"]
    run_id = run["info"]["run_id"]
    print(f"Most recent run: {run_id}, status={status}", file=sys.stderr)
    assert status == "FINISHED", f"Expected run {run_id} to be FINISHED, got status={status}"

    return run_id


mlflow_url = sys.argv[1]
experiment_name = sys.argv[2]
print(find_finished_run(mlflow_url, experiment_name))
