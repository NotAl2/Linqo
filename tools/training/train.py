"""Manual LoRA/QLoRA experiment. Never invoked by scheduled exports or the app."""
import argparse
import hashlib
import json
from pathlib import Path
import time


def validate(root, require_fresh=False):
    state = json.loads((root / "checkpoint.json").read_text(encoding="utf-8"))
    manifest = json.loads((root / "dataset-manifest.json").read_text(encoding="utf-8"))
    freshness = 5 * 60000 if require_fresh else 7 * 86400000
    if time.time() * 1000 - state["last_success"] > freshness:
        raise ValueError("Pull deletion requests before training.")
    if manifest["deletion_cursor"] != state["deletion"]:
        raise ValueError("Rebuild dataset after processing deletions.")
    rows = {}
    for split in ("train", "eval"):
        rows[split] = [json.loads(line) for line in (root / f"{split}.jsonl").read_text(encoding="utf-8").split("\n") if line.strip()]
        if not rows[split]:
            raise ValueError(f"Missing {split} examples.")
        for row in rows[split]:
            example = json.loads((root / "examples" / f"{row['id']}.json").read_text(encoding="utf-8"))
            review = example["review"]
            if not review.get("approved") or not review.get("rights_confirmed"):
                raise ValueError("Dataset includes an unapproved example.")
            if row["source"] != example["sample"]["source"] or row["target"] != review["target"] or row["category"] != review["category"]:
                raise ValueError("Dataset is stale; rebuild it.")
            messages = row.get("messages", [])
            if len(messages) != 2 or [message.get("role") for message in messages] != ["system", "user"] or not all(isinstance(message.get("content"), str) for message in messages):
                raise ValueError("Missing app-validated training prompts; rebuild the dataset.")
    source_key = lambda row: hashlib.sha256(" ".join(row["source"].strip().lower().split()).encode()).hexdigest()
    if set(map(source_key, rows["train"])) & set(map(source_key, rows["eval"])):
        raise ValueError("Source leakage between training and evaluation.")
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, default=Path(".private/linqo-training"))
    parser.add_argument("--train", action="store_true", help="Explicitly allow model download and GPU training")
    parser.add_argument("--qlora", action="store_true")
    parser.add_argument("--revision", help="Required pinned Qwen model commit for a training run")
    parser.add_argument("--max-steps", type=int, default=100)
    args = parser.parse_args()
    rows = validate(args.data, require_fresh=args.train)
    if not args.train:
        print(json.dumps({"validated": {k: len(v) for k, v in rows.items()}, "training_started": False}))
        return
    if not args.revision or not 1 <= args.max_steps <= 1000:
        parser.error("Pin --revision and choose --max-steps between 1 and 1000.")
    import torch
    from transformers import AutoTokenizer, AutoModelForCausalLM, BitsAndBytesConfig, Trainer, TrainingArguments
    from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training
    if not torch.cuda.is_available():
        raise RuntimeError("This experiment requires a supported local CUDA GPU. No cloud compute is provisioned.")
    name = "Qwen/Qwen3-0.6B"
    tokenizer = AutoTokenizer.from_pretrained(name, revision=args.revision)
    dtype = torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16
    options = {"revision": args.revision, "torch_dtype": dtype}
    if args.qlora:
        options["quantization_config"] = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type="nf4", bnb_4bit_use_double_quant=True, bnb_4bit_compute_dtype=dtype)
        options["device_map"] = {"": 0}
    model = AutoModelForCausalLM.from_pretrained(name, **options)
    if args.qlora:
        model = prepare_model_for_kbit_training(model)
    model.config.use_cache = False
    model = get_peft_model(model, LoraConfig(r=8, lora_alpha=16, lora_dropout=0.05, target_modules=["q_proj", "k_proj", "v_proj", "o_proj"], task_type="CAUSAL_LM"))
    def encode(row):
        prompt = tokenizer.apply_chat_template(row["messages"], tokenize=False, add_generation_prompt=True, enable_thinking=False)
        prefix = tokenizer(prompt, add_special_tokens=False)["input_ids"]
        target = tokenizer(row["target"], add_special_tokens=False)["input_ids"] + [tokenizer.eos_token_id]
        if len(prefix) + len(target) > 2048:
            raise ValueError(f"Example {row['id']} exceeds context. Review a shorter example; no silent truncation.")
        return {"input_ids": prefix + target, "attention_mask": [1] * (len(prefix) + len(target)), "labels": [-100] * len(prefix) + target}
    encoded = {k: [encode(row) for row in values] for k, values in rows.items()}
    def collate(batch):
        maximum = max(len(x["input_ids"]) for x in batch)
        return {key: torch.tensor([row[key] + [pad] * (maximum - len(row[key])) for row in batch]) for key, pad in (("input_ids", tokenizer.pad_token_id or tokenizer.eos_token_id), ("attention_mask", 0), ("labels", -100))}
    output = args.data / "experiments" / str(int(time.time()))
    settings = TrainingArguments(output_dir=str(output), max_steps=args.max_steps, per_device_train_batch_size=1, per_device_eval_batch_size=1, gradient_accumulation_steps=8, learning_rate=1e-4, eval_strategy="steps", eval_steps=25, save_steps=25, save_total_limit=2, logging_steps=10, report_to="none", bf16=dtype == torch.bfloat16, fp16=dtype == torch.float16, seed=42)
    trainer = Trainer(model=model, args=settings, train_dataset=encoded["train"], eval_dataset=encoded["eval"], data_collator=collate, processing_class=tokenizer)
    trainer.train()
    model.save_pretrained(output / "adapter")
    tokenizer.save_pretrained(output / "adapter")
    (output / "evaluation.json").write_text(json.dumps(trainer.evaluate()), encoding="utf-8")
    print("Adapter saved locally. Loss alone is not a release approval. Run grounding and Redmi benchmarks before distribution.")


if __name__ == "__main__":
    main()
