import os
import torch
from datasets import load_dataset
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    BitsAndBytesConfig,
    TrainingArguments,
    pipeline,
)
from peft import LoraConfig, PeftModel
from trl import SFTTrainer
import mlflow

mlflow_uri = os.getenv("MLFLOW_URI", "http://mlflow:5000")
mlflow_artifact_uri = os.getenv("MLFLOW_ARTIFACT_URI", "")
mlflow_exp_name = os.getenv("MLFLOW_EXPERIMENT_NAME", "gemma2-9b-finetuning")

mlflow.set_tracking_uri(uri=mlflow_uri)
if sum(exp.name == mlflow_exp_name for exp in mlflow.search_experiments()) == 0:
    mlflow.create_experiment(mlflow_exp_name, artifact_location=mlflow_artifact_uri)
mlflow.set_experiment(mlflow_exp_name)

with mlflow.start_run() as run:

    # The model that you want to train from the Hugging Face hub
    model_name = os.getenv("MODEL_NAME", "google/gemma-2-9b")

    # The instruction dataset to use
    dataset_name = "b-mc2/sql-create-context"

    # Fine-tuned model name
    new_model = os.getenv("NEW_MODEL", "gemma-2-9b-sql")

    print(f"""---------------------
    model_name: {model_name}
    dataset_name: {dataset_name}
    new_model: {new_model}
    mlflow_uri: {mlflow_uri}
    mlflow_artifact_uri: {mlflow_artifact_uri}
    mlflow_exp_name: {mlflow_exp_name}
    ---------------------""")

    ################################################################################
    # QLoRA parameters
    ################################################################################

    # LoRA attention dimension
    lora_r = int(os.getenv("LORA_R", "4"))

    # Alpha parameter for LoRA scaling
    lora_alpha = int(os.getenv("LORA_ALPHA", "8"))

    # Dropout probability for LoRA layers
    lora_dropout = 0.1

    ################################################################################
    # bitsandbytes parameters
    ################################################################################

    # Activate 4-bit precision base model loading
    use_4bit = True

    # Compute dtype for 4-bit base models
    bnb_4bit_compute_dtype = "float16"

    # Quantization type (fp4 or nf4)
    bnb_4bit_quant_type = "nf4"

    # Activate nested quantization for 4-bit base models (double quantization)
    use_nested_quant = False

    ################################################################################
    # TrainingArguments parameters
    ################################################################################

    # Output directory where the model predictions and checkpoints will be stored
    output_dir = "./results"

    # Number of training epochs
    num_train_epochs = int(os.getenv("NUM_TRAIN_EPOCHS", "1"))

    # Enable fp16/bf16 training (set bf16 to True with an A100)
    fp16 = True
    bf16 = False

    # Batch size per GPU for training
    per_device_train_batch_size = int(os.getenv("TRAIN_BATCH_SIZE", "1"))

    # Batch size per GPU for evaluation
    per_device_eval_batch_size = int(os.getenv("EVAL_BATCH_SIZE", "2"))

    # Number of update steps to accumulate the gradients for
    gradient_accumulation_steps = int(os.getenv("GRADIENT_ACCUMULATION_STEPS", "1"))

    # Enable gradient checkpointing
    gradient_checkpointing = True

    # Maximum gradient normal (gradient clipping)
    max_grad_norm = float(os.getenv("MAX_GRAD_NORM", "0.3"))

    # Initial learning rate (AdamW optimizer)
    learning_rate = float(os.getenv("LEARNING_RATE", "2e-4"))

    # Weight decay to apply to all layers except bias/LayerNorm weights
    weight_decay = float(os.getenv("WEIGHT_DECAY", "0.001"))

    # Optimizer to use
    optim = "paged_adamw_32bit"

    # Learning rate schedule
    lr_scheduler_type = "cosine"

    # Number of training steps (overrides num_train_epochs)
    max_steps = int(os.getenv("max_steps", -1))

    # Ratio of steps for a linear warmup (from 0 to learning rate)
    warmup_ratio = float(os.getenv("WARMUP_RATIO", "0.03"))

    # Group sequences into batches with same length
    # Saves memory and speeds up training considerably
    group_by_length = True

    # Save checkpoint every X updates steps
    save_steps = 0

    # Log every X updates steps
    logging_steps = int(os.getenv("LOGGING_STEPS", "50"))

    ################################################################################
    # SFT parameters
    ################################################################################

    # Maximum sequence length to use
    max_seq_length = int(os.getenv("MAX_SEQ_LENGTH", "512"))

    # Pack multiple short examples in the same input sequence to increase efficiency
    packing = False

    # Load the entire model on the GPU 0
    device_map = {'':torch.cuda.current_device()}

    # Set limit to a positive number
    limit = int(os.getenv("DATASET_LIMIT", "5000"))

    dataset = load_dataset(dataset_name, split="train")
    if limit != -1:
        dataset = dataset.shuffle(seed=42).select(range(limit))


    def transform(data):
        question = data['question']
        context = data['context']
        answer = data['answer']
        template = "Question: {question}\nContext: {context}\nAnswer: {answer}"
        return {'text': template.format(question=question, context=context, answer=answer)}


    transformed = dataset.map(transform)

    # Load tokenizer and model with QLoRA configuration
    compute_dtype = getattr(torch, bnb_4bit_compute_dtype)

    bnb_config = BitsAndBytesConfig(
        load_in_4bit=use_4bit,
        bnb_4bit_quant_type=bnb_4bit_quant_type,
        bnb_4bit_compute_dtype=compute_dtype,
        bnb_4bit_use_double_quant=use_nested_quant,
    )

    # Check GPU compatibility with bfloat16
    if compute_dtype == torch.float16 and use_4bit:
        major, _ = torch.cuda.get_device_capability()
        if major >= 8:
            print("=" * 80)
            print("Your GPU supports bfloat16")
            print("=" * 80)

    # Load base model
    # model = AutoModelForCausalLM.from_pretrained("google/gemma-7b")
    model = AutoModelForCausalLM.from_pretrained(
        model_name,
        quantization_config=bnb_config,
        device_map=device_map,
        torch_dtype=torch.float16,
    )
    model.config.use_cache = False
    model.config.pretraining_tp = 1

    # Load LLaMA tokenizer
    tokenizer = AutoTokenizer.from_pretrained(model_name, trust_remote_code=True)
    tokenizer.pad_token = tokenizer.eos_token
    tokenizer.padding_side = "right" # Fix weird overflow issue with fp16 training

    # Load LoRA configuration
    peft_config = LoraConfig(
        lora_alpha=lora_alpha,
        lora_dropout=lora_dropout,
        r=lora_r,
        bias="none",
        task_type="CAUSAL_LM",
        target_modules=["q_proj", "v_proj"]
    )

    # Set training parameters
    training_arguments = TrainingArguments(
        output_dir=output_dir,
        num_train_epochs=num_train_epochs,
        per_device_train_batch_size=per_device_train_batch_size,
        gradient_accumulation_steps=gradient_accumulation_steps,
        optim=optim,
        save_steps=save_steps,
        logging_steps=logging_steps,
        learning_rate=learning_rate,
        weight_decay=weight_decay,
        fp16=fp16,
        bf16=bf16,
        max_grad_norm=max_grad_norm,
        max_steps=max_steps,
        warmup_ratio=warmup_ratio,
        group_by_length=group_by_length,
        lr_scheduler_type=lr_scheduler_type,
    )

    trainer = SFTTrainer(
        model=model,
        train_dataset=transformed,
        peft_config=peft_config,
        dataset_text_field="text",
        max_seq_length=max_seq_length,
        tokenizer=tokenizer,
        args=training_arguments,
        packing=packing,
    )

    trainer.train()
    trainer.model.save_pretrained(new_model)
    base_model = AutoModelForCausalLM.from_pretrained(
        model_name,
        low_cpu_mem_usage=True,
        return_dict=True,
        torch_dtype=torch.float16,
        device_map=device_map,
    )
    model = PeftModel.from_pretrained(base_model, new_model)
    model = model.merge_and_unload()
    generation_pipeline = pipeline(
        task="text-generation",
        model=model,
        tokenizer=tokenizer,
    )

    mlflow.log_params(peft_config.to_dict())
    mlflow.transformers.log_model(
        transformers_model=generation_pipeline,
        artifact_path="model",  # This is a relative path to save model files within MLflow run
        prompt_template="{prompt}"
    )
