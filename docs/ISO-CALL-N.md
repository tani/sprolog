# ISO meta-call closure application and cut boundary design

## Implemented: call/2 ... call/8

The optional `sprolog/iso` interpreter now supports the arity-raising
`call/N` family for `2 <= N <= 8` (ISO/IEC 13211-1 corrigendum 2).
`call/1` remains the ordinary opaque meta-call.

For any callable ISO term `C` with functor `f` and argument list
`[A1, ..., Ak]`, and additional arguments `[B1, ..., Bm]`, the
expansion obeys:

```text
call(C, B1, ..., Bm)  ==>  f(A1, ..., Ak, B1, ..., Bm)
```

where `m = N - 1`. The expansion does *not* instantiate
`C` by unifying its variables with a copied representation:
existing and appended arguments must retain precisely the same logic
variables as the invoking goal. A runtime-bound closure such as
`P = binary(a), call(P, X)` can therefore bind the original `X`.

This is implemented entirely in ordinary S-expression Prolog relations
(`iso-append/3`, `iso-extend-closure/3`). Seven `iso-solve/1`
clauses, generated from the `install-extended-calls` macro, handle
`call/2` through `call/8`. Only dispatch and the callable check use
the existing native WAM machinery; no Lisp data-copy bridge is involved
in creating the extended goal.

Both statically supplied closures and runtime-bound closures are supported.
A variable used directly as an object-language clause body is now checked
at the `iso-solve/1` entry point *before* clause-head unification.
Execution uses a dedicated `iso-dispatch/1` relation only after the check,
so an unbound body variable cannot incorrectly become `true`, `fail`,
or `!` merely by unifying against dispatch rules.

An unbound closure raises `instantiation_error` and a noncallable
closure raises `type_error(callable, ...)`. The expanded goal is
resolved by the same ISO interpreter, including its current
`existence_error` checks. The test corpus exercises both atoms and
compound closures, nested `call`, shared variables, and the maximum
declared arity.

Run from the repository root:

```sh
sbcl --noinform --disable-debugger --script tests/iso/call-tests.lisp
```

The independent SWI reference suite includes `meta.call*` and
`meta.direct*` cases in `tests/iso/reference-cases.tsv`.

## Still pending: transparent cut at arbitrary positions

The current source-to-source cut transformation is correct only for
cut occurrences in a source clause's *top-level conjunction*.
It must **not** be lifted unchanged through an arbitrary branch.
There are three distinct scoping rules:

1. Disjunction is transparent: `(A ; B)` does not create an opaque
   cut boundary.
2. The condition of if-then-else is opaque for cuts; its THEN and ELSE
   continuations are not automatically opaque.
3. Meta-calling, including `call/N`, is opaque: a cut inside the
   meta-called goal may not prune choice points created by its caller.

Implementing arbitrary cut requires a first-class predicate-entry
choice-point barrier and an explicit meta-call boundary, not merely
replacing every `!` by the host-language cut instruction.
The WAM's native `machine-cut` currently belongs to the predicate
being executed, which is `iso-solve`, not necessarily the source ISO
predicate being interpreted. A direct substitution would prune the
interpreter's own alternatives instead of the source predicate's
alternatives.

The next implementation should carry a logical cut frame across
`iso-solve` steps, with at least these invariants:

- A cut can remove choice points introduced since the entry of the
  *object-language* predicate, but never earlier caller choices.
- A committed clause cannot fall through to later clauses even when
  a suffix after the cut fails.
- Cuts occurring inside an opaque meta-call/conditional condition
  only prune within that opaque frame.
- On exceptions and backtracking, frames and trail marks are restored
  according to existing WAM unwind semantics.
- Cuts do not change the identity or sharing of variables in existing
  ISO terms.

As an interim safety property, a dynamically constructed `!`
encountered through `call(G)` raises the explicit
`unsupported-iso-goal` condition rather than silently failing.
This is a deliberately incomplete behavior, *not* ISO compliance.
The existing nested source-cut restrictions remain in force.

Proposed regression seeds, to be compared against SWI:

```prolog
scope0(X) :- (X = a, ! ; X = b).
scope0(fallback).

scope1(X) :- (X = a ; X = b, !), X = b.
scope1(fallback).

scope2(X) :- call((X = a, !, fail ; X = b)).
scope2(fallback).

scope3(X) :- (X = a -> (X = a, !) ; X = b).
scope3(fallback).
```

An executable version of the cut-scope requirements now lives in
`tests/iso/cut-boundaries-swi.pl`. It runs **only on SWI-Prolog**
within the independent reference workflow and covers cut in left and
right disjunction branches, post-cut failure, caller/callee boundaries,
meta-call opacity, condition opacity, and transparent THEN/ELSE branches.

These SWI-side passes are **not sprolog/iso passes**. They define the
reference outcomes to which the eventual explicit choice-point barrier
implementation must conform. At that point they should be moved to the
shared `reference-cases.tsv` corpus rather than rewriting expected
results to accommodate the candidate.

## Non-goals

This change does not extend the native Lisp-first S-expression Prolog
API, add a new term representation, or make the ISO lexer fully
standards-compliant. The standalone ISO bootstrap remains experimental
and does not claim full ISO conformance.
