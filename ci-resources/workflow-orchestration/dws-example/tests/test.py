# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Proves DWS actually provisioned real GPU capacity for this job (not just
# that the job eventually ran some other way): first asserts the Kueue
# ProvisioningRequest reaches Accepted+Provisioned, then that the job
# completes on a node carrying the requested nvidia-tesla-t4 accelerator.

import json
import subprocess
import sys
import time


def kubectl(*args):
    result = subprocess.run(["kubectl", *args], capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


def wait_for_provisioning_request(job_name, timeout=600):
    deadline = time.time() + timeout
    last_state = None
    while time.time() < deadline:
        code, out, err = kubectl(
            "get", "provisioningrequests", "-o", "json",
        )
        if code == 0:
            requests = json.loads(out).get("items", [])
            matches = [r for r in requests if job_name in r["metadata"]["name"]]
            if matches:
                conditions = {c["type"]: c["status"] for c in matches[0].get("status", {}).get("conditions", [])}
                last_state = conditions
                print(f"ProvisioningRequest conditions: {conditions}")
                if conditions.get("Provisioned") == "True":
                    return
                if conditions.get("Failed") == "True":
                    raise AssertionError(f"ProvisioningRequest failed: {conditions}")
        time.sleep(10)
    raise AssertionError(
        f"Timed out waiting for ProvisioningRequest to reach Provisioned=True for job {job_name!r}. "
        f"Last seen conditions: {last_state}"
    )


def wait_for_job_completion(job_name, timeout=600):
    deadline = time.time() + timeout
    last_status = None
    while time.time() < deadline:
        code, out, err = kubectl("get", "job", job_name, "-o", "json")
        if code == 0:
            status = json.loads(out).get("status", {})
            last_status = status
            if status.get("succeeded", 0) >= 1:
                return
            if status.get("failed", 0) >= 1:
                raise AssertionError(f"Job {job_name!r} failed: {status}")
        time.sleep(10)
    raise AssertionError(f"Timed out waiting for job {job_name!r} to complete. Last status: {last_status}")


def assert_pod_used_requested_gpu(job_name, expected_accelerator="nvidia-tesla-t4"):
    code, out, err = kubectl(
        "get", "pods", "-l", f"job-name={job_name}", "-o",
        "jsonpath={.items[0].spec.nodeName}",
    )
    assert code == 0 and out.strip(), f"Could not find the pod for job {job_name!r}: {err}"
    node_name = out.strip()

    code, out, err = kubectl(
        "get", "node", node_name, "-o",
        "jsonpath={.metadata.labels['cloud\\.google\\.com/gke-accelerator']}",
    )
    assert code == 0, f"Could not inspect node {node_name!r}: {err}"
    accelerator = out.strip()
    assert accelerator == expected_accelerator, (
        f"Expected job {job_name!r} to run on a node with accelerator "
        f"{expected_accelerator!r}, but node {node_name!r} has {accelerator!r} - "
        f"DWS may not have actually provisioned the requested GPU."
    )


job_name = sys.argv[1]
print(f"Waiting for DWS to provision capacity for job {job_name!r}...")
wait_for_provisioning_request(job_name)
print("ProvisioningRequest reached Provisioned=True. Waiting for job to complete...")
wait_for_job_completion(job_name)
assert_pod_used_requested_gpu(job_name)
print(f"dws-example test passed: DWS provisioned a real nvidia-tesla-t4 node and job {job_name!r} completed on it.")
