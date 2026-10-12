# Independent ISO Prolog reference oracle

This suite evaluates **exactly the same conventional Prolog source programs and
queries** with SWI-Prolog and the experimental `sprolog/iso` interpreter.
Neither runtime uses the other as its execution engine.

The reference oracle does not establish full ISO/IEC 13211-1 conformance:
it compares a selected finite common subset. Other standards-conformance
tests in this repository are separately maintained.

## Reproduce the CI comparison

Requirements: Common Lisp (SBCL), SWI-Prolog with standard libraries, and
Python 3. No Python third-party packages or Lisp third-party libraries.

Run from the repository root:

```sh
mkdir -p compat-results/oracle

swipl -q -s tests/iso/reference-swi.pl -- \
  tests/iso/reference-cases.tsv \
  compat-results/oracle/swi.jsonl \
  tests/iso/bootstrap.pl \
  tests/iso/controls.pl \
  tests/iso/call-n.pl

sbcl --noinform --disable-debugger --script \
  tests/iso/reference-lisp.lisp \
  tests/iso/reference-cases.tsv \
  compat-results/oracle/sprolog.jsonl

python3 tests/iso/reference-compare.py \
  tests/iso/reference-cases.tsv \
  compat-results/oracle/swi.jsonl \
  compat-results/oracle/sprolog.jsonl \
  --output compat-results/oracle
```

CI runs these commands in the `ISO reference differential` workflow and
uploads `swi.jsonl`, `sprolog.jsonl`, `diff.json` and `summary.md`.
The Markdown report is also appended to the Actions job summary.
A missing, duplicate, or unexpected test result is an error.

## Result normalization

Each newline is a JSON object with a stable test ID. A successful observation
contains an **ordered array of all answers up to the test's explicit limit**,
including each answer's named variable bindings. Both runners probe one
additional solution and report `"truncated":true` when more answers exist.
Thus, equal prefixes with different search exhaustion do not count as
agreement. ISO terms are *not* printed
using host language conventions: they are recursively encoded.

| ISO term | Canonical JSON |
|---|---|
| `a` | `{"atom":"a"}` |
| `42` | `{"integer":"42"}` |
| `f(a,b)` | `{"functor":"f","args":[{"atom":"a"},{"atom":"b"}]}` |
| `[a]` | Nested `{"functor":".","args":[HEAD,TAIL]}` |
| Unbound variable | `{"var":0}`, stable per answer |

A successful goal without bindings is one empty object (`[{}]`), whereas
failure produces `[]`. Errors are recorded by *exception class* rather than
unstable printer messages, e.g.
`{"status":"exception","exception":"instantiation_error"}`.
The comparator compares parsed JSON objects and ordered answer arrays, not
whitespace or native Prolog term printing.

For SWI-Prolog, `numbervars/3` assigns stable identities to residual variables
within each answer; the Lisp runner numbers dereferenced symbolic residual
variables using the same convention. For now the manifest exercises only
finite, acyclic terms. Term cycles, floats and character escape syntax require
additional normalization and parser support.

## Baseline semantics

`tests/iso/reference-cases.tsv` has four tab-separated fields:

```text
ID    GOAL    MAX_SOLUTIONS    BASELINE
```

The baseline is either `agree` or `diverge`:

- `agree`: The complete, ordered observations must match. Any difference
  fails CI.
- `diverge`: A known mismatch is **not excluded** and remains visible as
  `known-divergence`. If both engines converge, the report records
  `resolved` as an improvement.
- An oracle error or missing result always fails CI, regardless of baseline.

Initially, unknown predicate calls exposed a missing `existence_error`
in `sprolog/iso`; that problem is now corrected and the corresponding
`unknown.*` cases are required to agree with SWI-Prolog.

SWI-Prolog 7 and later deliberately treats the empty list `[]` as a
special constant that is **not** an atom and is distinct from the
quoted atom `'[]'`. Traditional ISO Prolog treats `[]` as an atom.
The cases `types.atom` and `types.empty-equivalence` are therefore
declared divergences, not changes to force sprolog to imitate SWI's
non-ISO representation. See the
[SWI-Prolog list representation documentation](https://www.swi-prolog.org/pldoc/man?section=ext-lists).

A solution limit bounds memory and runtime. The harness checks up to one
additional answer to distinguish complete enumeration from truncation, but
for truly larger/infinite search spaces the comparison still concerns only
the finite observed prefix and its truncation bit. The two interpreters must
not be claimed equivalent beyond that prefix.

## Coverage development

When extending this corpus, prioritize:

1. Named-variable answer **values and order**, including aliasing and unbound
   variables.
2. Cut scope across nested disjunctions, if-then-else, predicates, and
   `call/N`; currently only a restricted fragment is interpreted.
3. Parser conformance: quoted atoms, escape sequences, custom operators,
   floats, comments, and ISO parser errors.
4. Exception categories, error balls, and contexts.
5. Logical update view, I/O behavior, and declaration semantics.

The suite includes finite `call/2..8` closure and unbound-variable
regressions, and tracks exhaustion beyond answer limits separately.
The interpreter's unsupported dynamic meta-call cuts are documented in
[ISO-CALL-N.md](ISO-CALL-N.md).

Add expected divergences explicitly and with an explanation in the manifest.
Never change a Prolog goal to make it match the candidate runtime or convert
an observed discrepancy into an invisible skipped test. The independent oracle
is the adjudicator, not the new implementation under test.
