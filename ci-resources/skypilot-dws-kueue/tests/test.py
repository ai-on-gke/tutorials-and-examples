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
# `sky launch` itself already exits non-zero if the job's run script fails,
# so this focuses on the harder question it can't answer on its own: did
# real training actually happen (train_dws.yaml completing a bert-base-cased
# fine-tune), not just a `run:` block that silently no-op'd. HuggingFace's
# Trainer always prints a final metrics dict on success, so grep the job's
# own logs for 'train_runtime' - a genuine training-completion marker rather
# than a liveness check.

import subprocess
import sys


def sky_logs(cluster_name, job_id=1):
    result = subprocess.run(
        ["sky", "logs", cluster_name, str(job_id)],
        capture_output=True, text=True,
    )
    return result.returncode, result.stdout + result.stderr


cluster_name = sys.argv[1]
code, logs = sky_logs(cluster_name)
print(logs[-4000:])

assert code == 0, f"`sky logs {cluster_name} 1` exited {code}."
assert "train_runtime" in logs, (
    "Expected the HuggingFace Trainer's final metrics (containing "
    "'train_runtime') in the job logs, proving training actually completed - "
    "not found. The run may have failed silently before reaching that point."
)
print("skypilot-dws-kueue test passed: SkyPilot ran train_dws.yaml through Kueue/DWS and training completed for real.")
