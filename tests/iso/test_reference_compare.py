"""Unit tests for reference comparison and baseline discipline."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

FILE = Path(__file__).with_name("reference-compare.py")
SPEC = importlib.util.spec_from_file_location("sprolog_reference_compare", FILE)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class ReferenceCompareTests(unittest.TestCase):
    def test_exact_order_and_structure(self):
        base = [{"id": "x", "goal": "g(X).", "baseline": "agree", "limit": 3}]
        reference = {"x": {"id": "x", "status": "ok", "solutions": [
            {"X": {"atom": "a"}}, {"X": {"atom": "b"}}]}}
        candidate = {"x": {"id": "x", "status": "ok", "solutions": [
            {"X": {"atom": "b"}}, {"X": {"atom": "a"}}]}}
        self.assertEqual(MODULE.compare(base, reference, candidate)["summary"]["unexpected"], 1)
        candidate = {"x": {"id": "x", "status": "ok", "solutions": [
            {"X": {"atom": "a"}}, {"X": {"atom": "b"}}]}}
        self.assertEqual(MODULE.compare(base, reference, candidate)["summary"]["pass"], 1)

    def test_solution_exhaustion_is_part_of_equality(self):
        rows = [{"id": "bounded", "goal": "choice(X).", "baseline": "agree", "limit": 2}]
        base = {"bounded": {"status": "ok", "solutions": [{"X": {"atom": "a"}}],
                            "truncated": False}}
        more = {"bounded": {"status": "ok", "solutions": [{"X": {"atom": "a"}}],
                            "truncated": True}}
        self.assertEqual(MODULE.compare(rows, base, more)["summary"]["unexpected"], 1)
        self.assertEqual(MODULE.compare(rows, base, base)["summary"]["pass"], 1)

    def test_known_divergence_not_silent_skip(self):
        rows = [{"id": "u", "goal": "unknown.", "baseline": "diverge", "limit": 4}]
        swipl = {"u": {"status": "exception", "exception": "existence_error"}}
        sprolog = {"u": {"status": "ok", "solutions": []}}
        out = MODULE.compare(rows, swipl, sprolog)["summary"]
        self.assertEqual(out["known_divergence"], 1)
        self.assertEqual(out["total"], 1)
        self.assertEqual(out["agreed"], 0)
        self.assertEqual(
            MODULE.compare(rows, swipl, swipl)["summary"]["resolved"], 1)

    def test_missing_case_is_invalid(self):
        rows = [{"id": "case", "goal": "true.", "baseline": "agree", "limit": 4}]
        with self.assertRaises(ValueError):
            MODULE.compare(rows, {}, {})

    def test_manifest_rejects_duplicate_and_invalid_baseline(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "manifest.tsv"
            path.write_text("a\ttrue.\t2\tagree\na\ttrue.\t2\tagree\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                MODULE.read_cases(path)
            path.write_text("a\ttrue.\t2\tskip\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                MODULE.read_cases(path)

    def test_exception_class_not_error_message(self):
        rows = [{"id": "c", "goal": "throw(ball).", "baseline": "agree", "limit": 2}]
        ref = {"c": {"status": "exception", "exception": "ball"}}
        self.assertEqual(MODULE.compare(rows, ref, ref)["summary"]["pass"], 1)
        other = {"c": {"status": "exception", "exception": "type_error"}}
        self.assertEqual(MODULE.compare(rows, ref, other)["summary"]["unexpected"], 1)


if __name__ == "__main__":
    unittest.main()
