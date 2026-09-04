import sys

from flytekit.configuration import Config
from flytekit.models.core.execution import WorkflowExecutionPhase
from flytekit.remote import FlyteRemote

from hello_world import hello_world_wf

PROJECT = "flytesnacks"  # seeded automatically by terraform (admin.seedProjects)
DOMAIN = "development"


def test_hello_world_workflow(grpc_endpoint):
    remote = FlyteRemote(
        config=Config.for_endpoint(endpoint=grpc_endpoint, insecure=True),
        default_project=PROJECT,
        default_domain=DOMAIN,
    )

    print(f"Registering and launching hello_world_wf against {grpc_endpoint} ...")
    execution = remote.execute(
        hello_world_wf,
        inputs={"name": "GKE CI"},
        project=PROJECT,
        domain=DOMAIN,
        wait=False,
    )
    print(f"Launched execution: {execution.id.name} - "
          f"console: {remote.generate_console_url(execution)}")

    execution = remote.wait(execution, timeout=600, poll_interval=10)

    assert execution.closure.phase == WorkflowExecutionPhase.SUCCEEDED, (
        f"Expected execution to succeed, but phase was "
        f"{WorkflowExecutionPhase.enum_to_string(execution.closure.phase)}. "
        f"Error: {execution.closure.error}"
    )

    result = execution.outputs.get("o0", str)
    print(f"Workflow output: {result}")
    assert result == "Hello, GKE CI!", f"Unexpected workflow output: {result}"


grpc_endpoint = sys.argv[1]
test_hello_world_workflow(grpc_endpoint)
print("flyte test passed: hello_world_wf registered, executed, and succeeded end-to-end.")
