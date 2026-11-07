# Private model experiments

Exports and models belong under ignored `.private/`, never in Git or public artifacts. No user sample is automatically a training target. Public availability does not establish training permission: confirm rights before approving an example.

1. Pull samples/deletions with `scripts/Export-Contributions.ps1` from the project root.
2. Review private `examples/<id>.json` files. Set `review.approved`, `review.rights_confirmed`, `review.category`, and independently correct `review.target` (valid extraction JSON with supported source evidence). Do not approve copied hallucinations.
3. From the project root run `node cloud/tools/dataset.mjs`. It calls the app's actual Dart evidence parser, rejects invalid schema-3 targets/references and adds the exact numbered-source/system prompt used by Linqo. It uses the local Flutter SDK or `LINQO_DART`/`dart` from PATH. Normalized-source hashing holds out 20% and prevents exact source leakage. Review near duplicates manually.
4. `python tools/training/train.py` validates the dataset without downloading a model or starting training.
5. In a separate virtual environment install `tools/training/requirements.txt`. Install a CUDA-compatible PyTorch build for your hardware. Record resolved dependency versions in the experiment; this environment has not been GPU-validated on this laptop.
6. Start a bounded manual experiment with `scripts/Train-LocalModel.ps1 -Revision <pinned-Qwen-commit> -MaxSteps 100 -QLoRA`. This refreshes deletions, rebuilds the reviewed dataset and explicitly starts local GPU work. Direct Python training also requires a successful deletion pull within five minutes. This may download base weights and use GPU resources. There is no hosted compute provisioning. Omit `-QLoRA` for ordinary LoRA.

The script masks prompt tokens, rejects over-context examples, saves a local adapter, disables reporting/upload and limits checkpoints. Export scheduling never invokes it. Review schema/evidence accuracy independently; lower evaluation loss alone is not enough.

Before any distribution: evaluate the incumbent and candidate against the same held-out recipe/article/tutorial/place/general fixtures; measure unsupported claims, correct category, ingredients/steps/servings, malformed output, cancellation, peak RSS and latency. Require no additional unsupported details, improved useful-field coverage and no more than 10% p95 latency/RSS regression on the Redmi at two threads. Keep a manual adversarial/privacy review and preserve the incumbent model as rollback.

Merge/export the adapter and quantize with a pinned, reviewed llama.cpp toolchain only after acceptance. Re-test the quantized GGUF, generate SHA-256, retain base/adapter provenance and licenses, and update the optional model manifest only in a separately reviewed release. Training/publishing is deliberately not automatic.
