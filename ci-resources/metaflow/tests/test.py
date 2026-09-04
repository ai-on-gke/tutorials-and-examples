import sys
from huggingface_hub import HfApi


def test_finetuned_model_pushed_to_hub(new_model_name, hf_token):
    """FinetuneFlow's start step ends with finetune_and_upload_to_hf(), whose
    last two lines are model.push_to_hub(...) / tokenizer.push_to_hub(...) -
    same shape as finetuning-gemma-3-1b-it-on-l4's test, reused here.
    """
    api = HfApi(token=hf_token)
    username = api.whoami()["name"]
    repo_id = f"{username}/{new_model_name}"

    print(f"Checking that {repo_id} exists on the Hugging Face Hub...")
    info = api.model_info(repo_id)
    print(f"Found model repo: {info.id}, last modified: {info.lastModified}")

    siblings = [f.rfilename for f in info.siblings]
    print(f"Repo files: {siblings}")
    assert any(f.endswith(".safetensors") or f == "adapter_model.bin" for f in siblings), (
        f"Expected at least one model weights file in {repo_id}, found: {siblings}"
    )


new_model_name = sys.argv[1]
hf_token = sys.argv[2]
test_finetuned_model_pushed_to_hub(new_model_name, hf_token)
print("metaflow test passed: FinetuneFlow ran on the cluster and pushed a real model to the Hugging Face Hub.")
