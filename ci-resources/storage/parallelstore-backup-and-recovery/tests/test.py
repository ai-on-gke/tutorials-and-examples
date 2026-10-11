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
# Proves the backup CronJob actually exported real data from Parallelstore
# to GCS - not just that the export command exited zero - by waiting for the
# one-off Job to complete, then checking the exact marker file (seeded
# directly into the Parallelstore volume by the pipeline) exists at the
# expected destination path in GCS.

import subprocess
import sys
import time

from google.cloud import storage


def kubectl(*args):
    result = subprocess.run(["kubectl", *args], capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


def wait_for_job_completion(job_name, timeout=1800):
    deadline = time.time() + timeout
    last_status = None
    while time.time() < deadline:
        code, out, err = kubectl("get", "job", job_name, "-o", "jsonpath={.status.succeeded} {.status.failed}")
        if code == 0:
            succeeded, _, failed = out.strip().partition(" ")
            last_status = out.strip()
            if succeeded == "1":
                return
            if failed and failed != "0":
                logs_code, logs_out, _ = kubectl("logs", f"job/{job_name}")
                raise AssertionError(f"Backup job {job_name!r} failed. Logs:\n{logs_out}")
        time.sleep(15)
    raise AssertionError(f"Timed out waiting for backup job {job_name!r} to complete. Last status: {last_status!r}")


def assert_marker_in_gcs(bucket_name, object_path, timeout=120):
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    deadline = time.time() + timeout
    while time.time() < deadline:
        blob = bucket.blob(object_path)
        if blob.exists():
            return
        time.sleep(10)
    raise AssertionError(
        f"Expected gs://{bucket_name}/{object_path} to exist after the backup ran - "
        f"the export did not actually copy the seeded data to GCS."
    )


job_name, bucket_name, object_path = sys.argv[1], sys.argv[2], sys.argv[3]
print(f"Waiting for backup job {job_name!r} to complete...")
wait_for_job_completion(job_name)
print(f"Backup job completed. Checking gs://{bucket_name}/{object_path}...")
assert_marker_in_gcs(bucket_name, object_path)
print("parallelstore-backup-and-recovery test passed: seeded data was actually exported from Parallelstore to GCS.")
