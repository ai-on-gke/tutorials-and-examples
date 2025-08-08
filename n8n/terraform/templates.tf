# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


resource "local_file" "ollama_manifest" {
  content = templatefile(
    "${path.module}/../templates/ollama/ollama.yaml.tftpl",
    {
      SERVICE_ACCOUNT_NAME = local.ollama_service_account_name,
      BUCKET_NAME          = local.ollama_bucket_name
    }
  )
  filename = "${path.module}/../gen/ollama.yaml"
}

resource "local_file" "n8n_common_values_file" {
  content = templatefile(
    "${path.module}/../templates/n8n/common-values.yaml.tftpl",
    {
      DB_HOST = module.cloudsql.private_ip_address
    }
  )
  filename = "${path.module}/../gen/n8n-common-values.yaml"
}

resource "local_file" "n8n_service_values_file" {
  for_each = toset(["ClusterIP", "NodePort"])
  content = templatefile(
    "${path.module}/../templates/n8n/service-type.yaml.tftpl",
    {
      SERVICE_TYPE = each.value
    }
  )
  filename = "${path.module}/../gen/n8n-service-type-${lower(each.value)}.yaml"
}
