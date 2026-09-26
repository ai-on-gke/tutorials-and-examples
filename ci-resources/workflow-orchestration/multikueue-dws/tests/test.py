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
# Run against the manager cluster's context. Proves the job submitted to the
# manager was actually dispatched to and completed on one of the worker
# clusters via MultiKueue - not just that the manager-side Workload object
# looks fine - by reading which cluster admitted it out of the workload's own
# status, then re-checking job completion directly on that worker cluster.

import json
import subprocess
import sys
import time

WORKER_CONTEXTS = {
    "multikueue-dws-worker-asia": "worker-asia-southeast1",
    "multikueue-dws-worker-us": "worker-us-east4",
    "multikueue-dws-worker-eu": "worker-europe-west4",
}


def kubectl(*args, context=None):
    cmd = ["kubectl"]
    if context:
        cmd += ["--context", context]
    cmd += list(args)
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


def find_admitted_worker(job_name, timeout=600):
    deadline = time.time() + timeout
    last_status = None
    while time.time() < deadline:
        code, out, err = kubectl("get", "workloads.kueue.x-k8s.io", "-o", "json")
        if code == 0:
            items = json.loads(out).get("items", [])
            matches = [w for w in items if job_name in w["metadata"]["name"]]
            if matches:
                checks = matches[0].get("status", {}).get("admissionChecks", [])
                last_status = checks
                for check in checks:
                    state = check.get("state")
                    # MultiKueue reports the admitted cluster name in the
                    # admission check's message, e.g. "The workload got
                    # reservation on cluster multikueue-dws-worker-asia"
                    message = check.get("message", "")
                    for worker_cluster in WORKER_CONTEXTS:
                        if worker_cluster in message and state == "Ready":
                            return worker_cluster
        time.sleep(10)
    raise AssertionError(
        f"Timed out waiting for workload for job {job_name!r} to be admitted onto a worker "
        f"cluster via MultiKueue. Last admissionChecks status: {last_status}"
    )


def wait_for_job_completion(job_name, context, timeout=300):
    deadline = time.time() + timeout
    last_status = None
    while time.time() < deadline:
        code, out, err = kubectl("get", "job", "-o", "json", context=context)
        if code == 0:
            items = json.loads(out).get("items", [])
            matches = [j for j in items if j["metadata"]["generateName"] == "dws-job-" or job_name in j["metadata"]["name"]]
            for job in matches:
                status = job.get("status", {})
                last_status = status
                if status.get("succeeded", 0) >= 1:
                    return
                if status.get("failed", 0) >= 1:
                    raise AssertionError(f"Job on worker {context!r} failed: {status}")
        time.sleep(10)
    raise AssertionError(
        f"Timed out waiting for the dispatched job to complete on worker {context!r}. "
        f"Last status seen: {last_status}"
    )


job_name = sys.argv[1]
print(f"Waiting for MultiKueue to admit job {job_name!r} onto a worker cluster...")
admitted_cluster = find_admitted_worker(job_name)
worker_context = WORKER_CONTEXTS[admitted_cluster]
print(f"Job admitted onto {admitted_cluster!r} ({worker_context!r}). Waiting for completion...")
wait_for_job_completion(job_name, worker_context)
print(
    f"multikueue-dws test passed: job {job_name!r} submitted to the manager cluster was "
    f"dispatched to and completed on worker cluster {admitted_cluster!r} via MultiKueue."
)
