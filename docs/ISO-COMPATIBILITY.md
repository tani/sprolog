# Prolog-interface compatibility measurements

This harness measures **a selected, locally authored collection of ISO-oriented
Prolog Core behavior probes** using sprolog's conventional .pl reader and WAM
execution engine. It is **not** an ISO/IEC 13211-1 certification, does **not**
run Logtalk directly, and does not yet count all upstream ISO test cases.

## Run

From the repository root:

```sh
sbcl --noinform --disable-debugger --script tests/iso/run.lisp
sbcl --noinform --disable-debugger --script tests/iso/run.lisp --strict --output compat-results/
```

Outputs are `compat-results/results.json` and
`compat-results/summary.md`. The JSON includes the source manifest,
commit SHA (when running on GitHub Actions), total and per-case status.
CI uploads both files and publishes the Markdown summary in the workflow job
summary. An unexpected result is recorded even when other cases pass.

The CI `--strict` mode only fails when a case explicitly marked
`:required t` no longer passes. A non-required failure is **not** masked as
success; it appears in JSON/Markdown without blocking the whole workflow. If
the runner, manifest validation, or JSON structure breaks, CI fails.

## Data model

Each item of `tests/iso/cases.sexp` is a property list:

```lisp
(:id "arithmetic.precedence"
 :area "arithmetic"
 :goal "X is 1 + 2 * 3, X = 7."
 :expect :success
 :required t)
```

`goal` is real Prolog source text, parsed by
`sprolog:parse-prolog-goal`, not Lisp source or an S-expression impersonating
Prolog. `tests/iso/core.pl` is consulted afresh into an isolated database for
each case using `sprolog:load-prolog`.

Supported expectations:

- `:success`: at least one solution
- `:failure`: no solutions
- `(:count N)`: exactly N solutions, checked with an N+1 upper bound
- `(:error "type_error")`: a Prolog exception of the named class
- `:unsupported`: **not executed**, with mandatory `:reason`

Outcomes are `PASS` for expected observations, `FAIL` for contradictory
observations, `ERROR` for a parser/runtime/harness exception or timeout, and
`UNSUPPORTED` for declared exclusions. Case IDs are unique and stable.
Malformed manifests, empty suites, duplicate case IDs, or unknown categories
fail the runner instead of artificially improving the score.

The headline pass rate is `PASS / (PASS + FAIL + ERROR)`. Unsupported
cases are separately counted, with no contribution to either side of the ratio.
The denominator is the number of attempted *probes*, **not** the total count of
features in ISO/IEC 13211-1. All per-case results are retained and grouped by
syntax, unification, control, clauses, arithmetic, types, exceptions, DCGs
and I/O.

Queries may be non-terminating. Under SBCL, a five-second per-case timeout
records `ERROR`. On other Common Lisp implementations the runner has no
portable timeout; use a process-level time limit. Infinite enumerations
should not be added as unbounded `:count` cases.

## Relationship to upstream tests

Public comparison references:

- [Logtalk Prolog conformance tests](https://github.com/LogtalkDotOrg/logtalk3/tree/master/tests/prolog),
  whose `iso_` test IDs identify tests sourced from ISO standards. Its suite
  also includes de facto standards and extensions.
- [Ciao ISO tests](https://github.com/ciao-lang/iso_tests).
- [Scryer Prolog test suite](https://github.com/mthom/scryer-prolog/tree/master/tests-pl).

The local core.pl/cases.sexp probes are authored for this harness; no upstream
test code is copied or included in the project. A matching category or a
passing local probe must **not** be reported as passing a specific upstream
Logtalk test ID. A future upstream import adapter must record provenance,
skip unsupported Logtalk test DSL features, and preserve the original test
expectations rather than silently rewriting failing examples.

## Comparing two runs

Download `results.json` from the GitHub Actions artifacts of two commits
and run:

```sh
python3 tests/iso/compare.py old/results.json new/results.json --fail-on-regression
python3 tests/iso/compare.py old/results.json new/results.json --json-out delta.json
```

The comparison is keyed by stable test ID. It lists passing cases that
regressed, newly passing cases, newly added cases and removed cases separately.
A changing denominator is never hidden in an apparent percentage improvement.

The local manifest also contains a small number of **source-equivalent
adaptations** of published Logtalk ISO-prefixed test cases, with explicit
`:upstream` paths and IDs. These are selected, adapted cases, **not**
unmodified execution of the upstream Logtalk suite. In the JSON report,
`upstream` is empty for locally authored probes. Logtalk test cases requiring
floating-point source syntax are marked `UNSUPPORTED` rather than counted as
passing.

## Known differences

sprolog models compound terms and lists using native Common Lisp cons cells,
treats Lisp symbols as atoms, and allows rational-tree unification by default.
The restricted .pl loader does not implement user-defined operators, numeric
floats, full ISO term I/O, module semantics, or the Logtalk test framework.
Sprolog's existing core documentation explicitly does not promise full ISO
conformance. Some tests can therefore be excluded or expected to fail. The
report captures observed behavior; unsupported cases must never be counted as
passes.

When improving compatibility, add a concrete .pl query and expected result,
run it against a trusted ISO implementation, then mark it `:required t` only
once it reliably passes sprolog across the supported target environments.
