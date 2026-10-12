#!/usr/bin/env python3
"""Compare two native Prolog-interface JSON reports without external packages.

The percentage uses only attempted probes, never declared UNSUPPORTED entries.
A score change is not assumed to represent full ISO/IEC 13211-1 compliance.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

STATUSES = {"pass", "fail", "error", "unsupported"}


def read_report(path: Path) -> dict:
    with path.open(encoding="utf-8") as stream:
        report = json.load(stream)
    cases = report["results"]
    by_id: dict[str, dict] = {}
    for case in cases:
        identifier = case["id"]
        status = case["status"].lower().lstrip(":")
        if status not in STATUSES:
            raise ValueError(f"{path}: invalid status {status!r}")
        if identifier in by_id:
            raise ValueError(f"{path}: duplicate case ID {identifier!r}")
        by_id[identifier] = {**case, "status": status}
    if not by_id:
        raise ValueError(f"{path}: no cases")
    if len(cases) != report["summary"]["total"]:
        raise ValueError(f"{path}: inconsistent totals")
    return by_id


def summarize(cases: dict[str, dict]) -> dict[str, int | float]:
    counts = {status: sum(c["status"] == status for c in cases.values())
              for status in STATUSES}
    attempted = len(cases) - counts["unsupported"]
    return {
        "total": len(cases),
        "attempted": attempted,
        **counts,
        "rate": counts["pass"] / attempted if attempted else 0.0,
    }


def compare(old: dict[str, dict], new: dict[str, dict]) -> dict:
    old_ids, new_ids = set(old), set(new)
    shared_ids = old_ids & new_ids
    improved = sorted(
        identifier for identifier in shared_ids
        if old[identifier]["status"] in {"fail", "error", "unsupported"}
        and new[identifier]["status"] == "pass"
    )
    regressed = sorted(
        identifier for identifier in shared_ids
        if old[identifier]["status"] == "pass"
        and new[identifier]["status"] != "pass"
    )
    changed = [
        {"id": identifier,
         "before": old[identifier]["status"],
         "after": new[identifier]["status"]}
        for identifier in sorted(shared_ids)
        if old[identifier]["status"] != new[identifier]["status"]
    ]
    return {
        "before": summarize(old),
        "after": summarize(new),
        "common_cases": len(shared_ids),
        "added": sorted(new_ids - old_ids),
        "removed": sorted(old_ids - new_ids),
        "improved": improved,
        "regressed": regressed,
        "changed": changed,
    }


def markdown(result: dict) -> str:
    before, after = result["before"], result["after"]
    lines = [
        "# Prolog compatibility delta",
        "",
        "Scores refer to the exercised local/ported probes only, not to "
        "overall ISO Prolog compliance.",
        "",
        "| Metric | Before | After |",
        "|---|---:|---:|",
        f"| PASS | {before['pass']} | {after['pass']} |",
        f"| FAIL | {before['fail']} | {after['fail']} |",
        f"| ERROR | {before['error']} | {after['error']} |",
        f"| UNSUPPORTED | {before['unsupported']} | {after['unsupported']} |",
        f"| Attempted | {before['attempted']} | {after['attempted']} |",
        f"| Pass rate (attempted) | {before['rate']:.1%} | {after['rate']:.1%} |",
        "",
    ]
    for heading, field in (
        ("Regressions (previously PASS)", "regressed"),
        ("Improvements (newly PASS)", "improved"),
        ("Added cases", "added"),
        ("Removed cases", "removed"),
    ):
        lines.append(f"## {heading}")
        lines.append("")
        cases = result[field]
        lines.extend(f"- `{identifier}`" for identifier in cases)
        if not cases:
            lines.append("None.")
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path, help="earlier results.json")
    parser.add_argument("after", type=Path, help="newer results.json")
    parser.add_argument("--json-out", type=Path, help="write structured differences")
    parser.add_argument("--fail-on-regression", action="store_true",
                        help="nonzero exit for cases previously PASS that are no longer PASS")
    args = parser.parse_args()
    result = compare(read_report(args.before), read_report(args.after))
    print(markdown(result))
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(result, indent=2) + "\n",
                                 encoding="utf-8")
    return 1 if args.fail_on_regression and result["regressed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
