from flytekit import task, workflow


@task
def say_hello(name: str) -> str:
    return f"Hello, {name}!"


@workflow
def hello_world_wf(name: str = "GKE CI") -> str:
    return say_hello(name=name)
