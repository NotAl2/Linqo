import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest

module_path = Path(__file__).resolve().parents[1] / "train.py"
spec = importlib.util.spec_from_file_location("linqo_training", module_path)
training = importlib.util.module_from_spec(spec)
spec.loader.exec_module(training)


class ValidationTests(unittest.TestCase):
    def setUp(self):
        work = module_path.parents[2] / ".tools" / "training-tests"
        work.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=work)
        self.root = Path(self.temp.name)
        (self.root / "examples").mkdir()
        self.write("checkpoint.json", {"last_success": time.time() * 1000, "deletion": 0})
        self.write("dataset-manifest.json", {"deletion_cursor": 0})
        for split, source in (("train", "Browser caches are stored locally."), ("eval", "Mix oats and milk in a bowl.")):
            row = {"id": split, "source": source, "category": "general", "target": '{"schema_version":3}', "messages": [{"role": "system", "content": "Ground the answer."}, {"role": "user", "content": source}]}
            self.write(f"examples/{split}.json", {"sample": {"source": source}, "review": {"approved": True, "rights_confirmed": True, "target": row["target"], "category": "general"}})
            (self.root / f"{split}.jsonl").write_text(json.dumps(row) + "\n")

    def tearDown(self):
        self.temp.cleanup()

    def write(self, name, value):
        (self.root / name).write_text(json.dumps(value))

    def test_reviewed_dataset_validates_without_loading_training_libraries(self):
        self.assertEqual(set(training.validate(self.root)), {"train", "eval"})

    def test_deletions_require_dataset_rebuild(self):
        self.write("checkpoint.json", {"last_success": time.time() * 1000, "deletion": 1})
        with self.assertRaisesRegex(ValueError, "Rebuild dataset"):
            training.validate(self.root)

    def test_unreviewed_or_unpermitted_examples_cannot_train(self):
        path = self.root / "examples/train.json"
        value = json.loads(path.read_text())
        value["review"]["rights_confirmed"] = False
        path.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, "unapproved"):
            training.validate(self.root)

    def test_stale_download_requires_new_deletion_pull(self):
        self.write("checkpoint.json", {"last_success": time.time() * 1000 - 8 * 86400000, "deletion": 0})
        with self.assertRaisesRegex(ValueError, "Pull deletion requests"):
            training.validate(self.root)

    def test_training_requires_an_immediate_deletion_pull_not_only_weekly_freshness(self):
        self.write("checkpoint.json", {"last_success": time.time() * 1000 - 10 * 60000, "deletion": 0})
        with self.assertRaisesRegex(ValueError, "Pull deletion requests"):
            training.validate(self.root, require_fresh=True)


if __name__ == "__main__":
    unittest.main()
