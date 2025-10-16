import base64
import json
import functions_framework
from google.cloud.devtools import cloudbuild_v1
from google.cloud.devtools.cloudbuild_v1 import types
from google.api_core.exceptions import GoogleAPIError

PROJECT_ID = "ai-on-gke-qss"
REGION = "us-central1"

# Triggered from a message on a Cloud Pub/Sub topic.
@functions_framework.cloud_event
def main(cloud_event):
    # Print out the data from Pub/Sub, to prove that it worked
    print(base64.b64decode(cloud_event.data["message"]["data"]))
    pubsub_message = base64.b64decode(cloud_event.data["message"]["data"])
    payload = json.loads(pubsub_message)
    print(payload)
    trigger_name = payload["trigger_name"]
    iteration = int(payload["iteration"]) + 1
    if iteration > 1:
        print("Limit for the iterations.")
        return

    client = cloudbuild_v1.CloudBuildClient()

    # Initialize request argument(s)
    parent = f"projects/{PROJECT_ID}/locations/{REGION}"
    request = cloudbuild_v1.ListBuildTriggersRequest(
        parent=parent
    )
    # Make the request
    page_result = client.list_build_triggers(request=request)

    # Handle the response
    trigger_id = None
    for trigger in page_result:
        if trigger.name != trigger_name:
            continue
        trigger_id = trigger.id

    if trigger_id == None:
        print(f"There is no such trigger with this name: {trigger_name}")
        return

    try:
        name = f"projects/{PROJECT_ID}/locations/{REGION}/triggers/{trigger_name}"
        custom_substitutions = {
            "_ITERATION": str(iteration)
        }

        repo_source = types.RepoSource(
            substitutions=custom_substitutions
        )
        request = cloudbuild_v1.RunBuildTriggerRequest(
            name=name,
            trigger_id=trigger_id,
            source=repo_source
        )
        print(f"Attempting to run trigger: {trigger_id} in region: {REGION}...")
        client.run_build_trigger(request=request)
        print("Trigger submitted.")

    except GoogleAPIError as e:
        print(f"Error triggering Cloud Build: {e.message}")
        raise e
