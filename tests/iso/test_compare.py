#!/usr/bin/env python3
"""Unit tests for compatibility score changes and denominator semantics."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SOURCE = Path(__file__).with_name("compare.py")
spec = importlib.util.spec_from_file_location("prolog_compat_compare", SOURCE)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


def make(cases):
    return {
        key: {"id": key, "status": status, "area": "unit"}
        for key, status in cases.items()
    }


class CompareTests(unittest.TestCase):
    def test_exclusions_not_in_denominator(self):
        summary = module.summarize(make({
            "a": "pass", "b": "fail", "c": "error",
            "d": "unsupported", "e": "unsupported",
        }))
        self.assertEqual(summary["attempted"], 3)
        self.assertAlmostEqual(summary["rate"], 1 / 3)

    def test_regression_and_improvement_are_per_case(self):
        old = make({"a": "pass", "b": "fail", "c": "unsupported", "gone": "pass"})
        new = make({"a": "error", "b": "pass", "c": "pass", "added": "unsupported"})
        result = module.compare(old, new)
        self.assertEqual(result["regressed"], ["a"])
        self.assertEqual(result["improved"], ["b", "c"])
        self.assertEqual(result["added"], ["added"])
        self.assertEqual(result["removed"], ["gone"])
        self.assertIn("previously PASS", module.markdown(result))

    def test_bad_report_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "results.json"
            path.write_text(json.dumps({
                "summary": {"total": 2},
                "results": [{"id": "dup", "status": "pass"},
                            {"id": "dup", "status": "pass"}]
            }), encoding="utf-8")
            with self.assertRaises(ValueError):
                module.read_report(path)

    def test_simple_no_change(self):
        cases = make({"same": "pass", "unknown": "unsupported"})
        result = module.compare(cases, cases)
        self.assertFalse(result["changed"])
        self.assertFalse(result["regressed"])


if __name__ == "__main__":
    unittest.main()
