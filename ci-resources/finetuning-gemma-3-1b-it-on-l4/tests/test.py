import sys
from huggingface_hub import HfApi


def test_finetuned_model_pushed_to_hub(new_model_name, hf_token):
    api = HfApi(token=hf_token)
    whoami = api.whoami()
    username = whoami["name"]
    repo_id = f"{username}/{new_model_name}"

    print(f"Checking that {repo_id} exists on the Hugging Face Hub...")
    # Raises if the repo doesn't exist (or isn't visible with this token) -
    # this is the whole point: finetune.py's last two lines are
    # model.push_to_hub(...) / tokenizer.push_to_hub(...), so a real, fetchable
    # repo is the only evidence the fine-tuning job actually finished and
    # produced a usable model, as opposed to just exiting 0 partway through.
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
print("finetuning-gemma-3-1b-it-on-l4 test passed: fine-tuned model verified on the Hugging Face Hub.")
