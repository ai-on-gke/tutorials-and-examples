import json
import sys
from datetime import datetime
import numpy as np
import os

def calculate_benchmarks(idx):
    path = f"./test-results-{idx}"
    json_file_path = f"./{path}/clean_logs.json"
    unschedulable_records_path = f"./{path}/unschedulable_records.json"
    all_pod_names_path = f"./{path}/all_pod_names.json"
    output_path = f"{path}/benchmarks.json"

    with open(json_file_path, 'r') as f:
        data = json.load(f)

    # print(len(data.keys()))
    # return
    def parse_ts(ts_str):
        # Handles the Z suffix for UTC
        return datetime.fromisoformat(ts_str.replace('Z', '+00:00'))

    # Lists to store deltas in seconds
    startup_latencies = []
    sandbox_up_latencies = []
    execution_latencies = []

    earliest_claim_ts = parse_ts(list(data.values())[0]["Sandbox requested"])
    latest_claim_ts = parse_ts(list(data.values())[0]["Sandbox requested"])
    latest_pod_exec_end = parse_ts(list(data.values())[0]["Time For Complete Execution"])
    for pod_id, metrics in data.items():
        try:
            # T0: Reference point
            if metrics["Sandbox requested"] is None or metrics["Sandbox requested"] == "" or metrics["Startup time"] == ""or metrics["Sandbox up"] == ""or metrics["Time For Complete Execution"] == "":
                continue
            t0 = parse_ts(metrics["Sandbox requested"])

            earliest_claim_ts = min(t0, earliest_claim_ts)
            latest_claim_ts = max(t0, latest_claim_ts)

            t_startup = parse_ts(metrics["Startup time"])
            t_up = parse_ts(metrics["Sandbox up"])
            t_exec = parse_ts(metrics["Time For Complete Execution"])
            latest_pod_exec_end = max(t_exec, latest_pod_exec_end)

            assert t0 <= t_exec, pod_id
            startup_latencies.append(max(0, (t_startup - t0).total_seconds() * 1000))
            sandbox_up_latencies.append((t_up - max(t_startup, t0)).total_seconds() * 1000)
            execution_latencies.append((t_exec - max(t_startup, t0)).total_seconds() * 1000)
        except KeyError as e:
            print(f"Skipping {pod_id}: missing key {e}")
            continue

    def create_stats(values):
        if not values:
            return ""
        return {
            "data":{
                "P50": f"{np.percentile(values, 50):.2f}",
                "P90": f"{np.percentile(values, 90):.2f}",
                "P95": f"{np.percentile(values, 95):.2f}",
                "P99": f"{np.percentile(values, 99):.2f}",
            },
            "unit": "ms"
        }

    output = {
        "Startup Latency (Req -> Startup)": create_stats(startup_latencies),
        "Sandbox Up Latency (Req -> Up)": create_stats(sandbox_up_latencies),
        "Total Execution Latency (Req -> Complete)": create_stats(execution_latencies),
    }

    # Failure rate
    if not os.path.exists(unschedulable_records_path):
        failure_rate = 0
    else:
        with open(unschedulable_records_path) as unschedulable_records_fi, open(all_pod_names_path) as all_pod_names_fi:
            all_pod_names = set(all_pod_names_fi.read().strip().split("\n"))
            unschedulable_records = set(json.loads(row)["pod_name"] for row in unschedulable_records_fi.read().strip().split("\n"))
            failure_rate = len(unschedulable_records) / len(all_pod_names)
    output["Failure Rate"] = {
        "data": failure_rate,
        "unit": "ratio"
    }
    # Total Time. Overall end-to-end test time
    output["Total Claim Time"] = {
        "data": f"{(latest_claim_ts - earliest_claim_ts).total_seconds() * 1000:.2f}",
        "unit": "ms"
    }

    output["Total Test Exection Time"] = {
        "data": f"{(latest_pod_exec_end - earliest_claim_ts).total_seconds() * 1000:.2f}",
        "unit": "ms"
    }

    output["Total Sandbox Created Count"] = {
        "data": len(data.keys()),
        "unit": "unit"
    }

    output["Throughput"] = {
        "data": len(data.keys()) / (latest_claim_ts - earliest_claim_ts).total_seconds(),
        "unit": "pod/sec."
    }



    print(output)
    with open(output_path, "w") as fo:
        json.dump(output, fo, indent=2)

    print(f"\nYou can find the benchmarks file here: {output_path}")

if __name__ == "__main__":
    calculate_benchmarks(sys.argv[1])
