import sys
from google.cloud import storage


def test_converted_checkpoint_exists(bucket_name, output_prefix):
    """finetune.py-style Job-exit-code checks don't apply here (this isn't a
    K8s Job) - the real evidence the conversion actually worked is that the
    unscanned MaxText checkpoint files landed in GCS, not just that the
    container process exited 0 partway through downloading.
    """
    client = storage.Client()
    blobs = list(client.list_blobs(bucket_name, prefix=output_prefix))
    names = [b.name for b in blobs]
    print(f"Found {len(names)} objects under gs://{bucket_name}/{output_prefix}")
    for n in names[:20]:
        print(f"  {n}")

    assert names, f"No objects found under gs://{bucket_name}/{output_prefix} - conversion did not produce output."
    assert any("checkpoint" in n.lower() or "items" in n.lower() for n in names), (
        f"Objects exist under the output prefix, but none look like MaxText checkpoint "
        f"files. Found: {names}"
    )


bucket_name = sys.argv[1]
output_prefix = sys.argv[2]
test_converted_checkpoint_exists(bucket_name, output_prefix)
print("inference-servers/checkpoints test passed: converted MaxText checkpoint found in GCS.")
