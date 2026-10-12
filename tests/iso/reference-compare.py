#!/usr/bin/env python3
"""Compare ISO interpreter behavior against independently executed SWI-Prolog.

The manifest owns expected agreement/divergence. A changed denominator and
an unknown/missing result are failures, never silent skips.
"""
from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from pathlib import Path


def read_cases(path: Path) -> list[dict]:
    cases: list[dict] = []
    seen: set[str] = set()
    with path.open(newline="", encoding="utf-8") as source:
        for number, row in enumerate(csv.reader(source, delimiter="\t"), 1):
            if not row or (row[0].startswith("#")):
                continue
            if len(row) != 4:
                raise ValueError(f"{path}:{number}: expected four columns")
            identifier, goal, limit, baseline = row
            if not identifier or identifier in seen:
                raise ValueError(f"{path}:{number}: empty or repeated ID: {identifier}")
            if not goal or not limit.isdigit() or not 0 < int(limit) < 1000:
                raise ValueError(f"{path}:{number}: invalid goal or limit")
            if baseline not in {"agree", "diverge"}:
                raise ValueError(f"{path}:{number}: unknown baseline: {baseline}")
            seen.add(identifier)
            cases.append(dict(id=identifier, goal=goal,
                              limit=int(limit), baseline=baseline))
    if not cases:
        raise ValueError(f"{path}: no oracle cases")
    return cases


def read_observations(path: Path) -> dict[str, dict]:
    result: dict[str, dict] = {}
    with path.open(encoding="utf-8") as source:
        for number, line in enumerate(source, 1):
            if not line.strip():
                continue
            row = json.loads(line)
            identifier = row.get("id")
            if not isinstance(identifier, str) or identifier in result:
                raise ValueError(f"{path}:{number}: missing or duplicate ID {identifier}")
            if row.get("status") not in {"ok", "exception", "unsupported", "error"}:
                raise ValueError(f"{path}:{number}: unknown status {row.get('status')}")
            if row["status"] == "ok" and not isinstance(row.get("solutions"), list):
                raise ValueError(f"{path}:{number}: missing solutions")
            if row["status"] == "ok" and not isinstance(row.get("truncated"), bool):
                raise ValueError(f"{path}:{number}: missing solution-exhaustion flag")
            if row["status"] == "exception" and not isinstance(row.get("exception"), str):
                raise ValueError(f"{path}:{number}: missing exception class")
            result[identifier] = row
    return result


def meaningful(observation: dict) -> dict:
    status = observation["status"]
    if status == "ok":
        # JSON objects represent bindings; object key order is immaterial.
        return {"status": status, "solutions": observation["solutions"],
                "truncated": observation.get("truncated", False)}
    if status == "exception":
        return {"status": status, "exception": observation["exception"]}
    return {"status": status, "message": observation.get("message", "")}


def compare(cases: list[dict], reference: dict, candidate: dict) -> dict:
    expected_ids = {case["id"] for case in cases}
    for name, results in [("SWI", reference), ("sprolog/iso", candidate)]:
        missing = expected_ids - results.keys()
        extra = results.keys() - expected_ids
        if missing or extra:
            raise ValueError(
                f"{name}: missing={sorted(missing)}, extra={sorted(extra)}")
    entries = []
    for case in cases:
        identifier = case["id"]
        a, b = meaningful(reference[identifier]), meaningful(candidate[identifier])
        equivalent = a == b
        if a["status"] in {"unsupported", "error"}:
            state = "oracle-error"
        elif b["status"] in {"unsupported", "error"}:
            state = "unexpected"
        elif case["baseline"] == "agree":
            state = "pass" if equivalent else "unexpected"
        else:
            state = "resolved" if equivalent else "known-divergence"
        entries.append({
            **case, "result": state, "equal": equivalent,
            "reference": a, "candidate": b,
        })
    counts = Counter(x["result"] for x in entries)
    summary = {
        "total": len(entries),
        "agreed": counts["pass"] + counts["resolved"],
        "pass": counts["pass"],
        "known_divergence": counts["known-divergence"],
        "resolved": counts["resolved"],
        "unexpected": counts["unexpected"],
        "oracle_error": counts["oracle-error"],
    }
    return {"summary": summary, "cases": entries}


def markdown(report: dict) -> str:
    summary = report["summary"]
    lines = [
        "# ISO Prolog differential reference report",
        "",
        "Reference: SWI-Prolog; candidate: sprolog/iso tagged-term meta-interpreter.",
        "Comparisons include **ordered answer bindings and ISO term structure**, "
        "failure, and exception classes; they are not an ISO certification.",
        "",
        "| Outcome | Count |",
        "|---|---:|",
    ]
    labels = [
        ("pass", "Expected agreement"),
        ("known_divergence", "Declared divergences"),
        ("resolved", "Previously divergent, now agrees"),
        ("unexpected", "Unexpected differences"),
        ("oracle_error", "Oracle execution errors"),
    ]
    for key, title in labels:
        lines.append(f"| {title} | {summary[key]} |")
    lines.extend([
        f"| Total cases | {summary['total']} |",
        "",
        "| Test ID | Baseline | Outcome |",
        "|---|---|---|",
    ])
    for entry in report["cases"]:
        lines.append(
            f"| {entry['id']} | {entry['baseline']} | {entry['result']} |")
    lines.append("")
    differing = [c for c in report["cases"] if not c["equal"]]
    if differing:
        lines.append("## Differences")
        lines.append("")
        for c in differing:
            lines.extend([
                f"**{c['id']}** — {c['goal']}",
                "",
                f"- SWI: \`{json.dumps(c['reference'], ensure_ascii=False)}\`",
                f"- sprolog/iso: \`{json.dumps(c['candidate'], ensure_ascii=False)}\`",
                "",
            ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("reference", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--output", type=Path, default=Path("compat-results/oracle"))
    args = parser.parse_args()
    report = compare(read_cases(args.manifest),
                     read_observations(args.reference),
                     read_observations(args.candidate))
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "diff.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (args.output / "summary.md").write_text(markdown(report), encoding="utf-8")
    print(markdown(report))
    summary = report["summary"]
    return 1 if summary["unexpected"] or summary["oracle_error"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
