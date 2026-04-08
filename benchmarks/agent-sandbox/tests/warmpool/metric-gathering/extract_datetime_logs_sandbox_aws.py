import sys
import json
from datetime import datetime


def extract_log_entity(row):
    entity = {
        "log": "",
        "kubernetes.pod_name": "",
        "@timestamp": ""
    }
    for cel in row:
        field, value = cel["field"], cel["value"]
        if field in entity:
            entity[field] = value
    dt_obj = datetime.strptime(entity["@timestamp"], "%Y-%m-%d %H:%M:%S.%f")
    entity["@timestamp"] = dt_obj.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    return entity

def parse_text_payload(entity):
    textPayload = entity["log"]
    timestamp = entity["@timestamp"]
    if "Threads started!" in textPayload:
        return "Startup time", timestamp
    elif "Total operations:" in textPayload:
        return "Sandbox up", timestamp
    elif "execution time (avg/stddev):" in textPayload:
        return "Time For Complete Execution", timestamp
    return "Error", textPayload


def extract_datetime(idx):
    target_structure = {}

    path = f"./test-results-{idx}"
    all_completed_logs_path = f"{path}/all_completed_logs.json"
    completed_records_path = f"{path}/completed_records.json"
    output_path = f"{path}/clean_logs.json"

    with open(all_completed_logs_path) as all_completed_logs_fi, open(completed_records_path) as completed_records_fi:
        all_completed_logs = json.load(all_completed_logs_fi)
        completed_records = [json.loads(row) for row in completed_records_fi.read().strip().split("\n")]

    for row in completed_records:
        if row["creation_timestamp"] is None:
            continue
        target_structure[row["pod_name"]] = {
            "accured_in_log_explorer": 0,
            "sandbox_name": row["sandbox_name"],
            "Sandbox requested": row["creation_timestamp"],
            "Startup time": "",
            "Sandbox up": "",
            "Time For Complete Execution": "",
        }

    for row in all_completed_logs:
        entity = extract_log_entity(row)
        key, value = parse_text_payload(entity)
        pod_name = entity["kubernetes.pod_name"]
        if key == "Error":
            continue
        if pod_name not in target_structure:
            print(pod_name)
            continue
        target_structure[pod_name][key] = value
        target_structure[pod_name]["accured_in_log_explorer"] += 1

    # for key, value in target_structure.items():
    #     assert value["accured_in_log_explorer"] == 3, f"pod_name={key} accured {value['accured_in_log_explorer']}"

    with open(output_path, "w") as fo:
        json.dump(target_structure, fo, indent=2)

if __name__ == "__main__":
    idx = sys.argv[1]
    extract_datetime(idx)
