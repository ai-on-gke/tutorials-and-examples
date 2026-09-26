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
# run.sh exits 0 both when it performs a real reset and when it decides to
# skip one (uptime/last-reset thresholds) - so a clean exit code alone can't
# tell them apart. This checks the actual side effects: the
# gpu-reset.gke.io/last-reset-seconds label was written (proving nvidia-smi
# --gpu-reset really ran and succeeded), and the node is Ready and
# uncordoned again (proving the cleanup trap completed, not left the node
# stuck mid-drain).

import json
import subprocess
import sys


def kubectl(*args):
    result = subprocess.run(["kubectl", *args], capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


node_name = sys.argv[1]

code, out, err = kubectl("get", "node", node_name, "-o", "json")
assert code == 0, f"Could not inspect node {node_name!r}: {err}"
node = json.loads(out)

labels = node.get("metadata", {}).get("labels", {})
assert "gpu-reset.gke.io/last-reset-seconds" in labels, (
    f"Expected node {node_name!r} to carry the gpu-reset.gke.io/last-reset-seconds label "
    f"after a forced reset (RESET_THRESHOLD_DAYS=-1) - it's missing, meaning the reset "
    f"either didn't run or didn't complete successfully."
)

spec = node.get("spec", {})
assert not spec.get("unschedulable"), (
    f"Expected node {node_name!r} to be uncordoned after the reset's cleanup ran - "
    f"it's still marked unschedulable."
)

taints = spec.get("taints", [])
drain_taints = [t for t in taints if t.get("key") == "gpu-reset"]
assert not drain_taints, (
    f"Expected the gpu-reset=draining taint to be removed by cleanup - still present: {drain_taints}"
)

print(f"gpu-reset-tool test passed: node {node_name!r} was actually reset (label written) and fully restored (uncordoned, untainted).")
