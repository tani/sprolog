# ISO Prolog bootstrap interpreter (experimental)

The optional ASDF system `sprolog/iso` implements a deliberately restricted
ISO-style Horn-clause interpreter **in S-expression Prolog**. It uses the
existing native WAM, unifier, and choice-point machinery as its Stage 0
execution substrate. The interpreter is not an ISO/IEC 13211-1 implementation
yet, and the earlier `sprolog:load-prolog` native syntax bridge remains
available unchanged.

## Load and run

```lisp
(require :asdf)
(asdf:load-asd (truename "sprolog.asd"))
(asdf:load-system "sprolog/iso")

(defparameter *iso* (sprolog/iso:make-runtime))
(sprolog/iso:consult "tests/iso/bootstrap.pl" :runtime *iso*)
(sprolog/iso:query "ancestor(alice, Who)." :runtime *iso*)
;; Two answers; values are tagged ISO terms, not Lisp-native Prolog terms.

(sprolog/iso:query "f(a,b) = [f,a,b]." :runtime *iso*)
;; NIL — distinct ISO compound functors.
```

The `:runtime` argument is explicit for persisting clauses across calls.
Without it, `query` and `consult` each create a fresh, empty environment.
A runtime's `runtime-database` holds native WAM clauses. Consulting appends
all clauses after parsing the whole file; there is not yet ISO
`consult/1` / `reconsult/1` replacement semantics.

## Representation

ISO terms are **tagged** so that Common Lisp's cons/list representation does
not conflate `f(a,b)` with `[f,a,b]`:

| Prolog term | Lisp data representation (schematic) |
|---|---|
| `a` | `(:iso-atom <atom-symbol-a>)` |
| `[]` | `(:iso-atom <atom-symbol-[]>)` |
| `f(a,b)` | `(:iso-compound <atom-symbol-f> (:iso-atom ...) (:iso-atom ...))` |
| `[a,b]` | `(:iso-compound <atom-symbol-.> A (:iso-compound <atom-symbol-.> B EMPTY))` |
| `42` | Common Lisp integer `42` |
| `X` | Lisp logic variable symbol with `?` prefix (scoped to ISO source package) |

ISO atoms are interned with their **exact case** in the pre-existing
`sprolog/atoms` package, which is excluded from the engine's logic-variable
heuristic. Quoted atoms beginning with `?` remain atoms. The ISO-only parser
retains quoted/unquoted atom syntax before the tagged-term conversion;
the existing `sprolog:read-prolog` parser keeps its previous native behavior.

The tags use ordinary Lisp cons cells, allowing the existing WAM's structural
unification, environment instantiation, and garbage collection to operate
without changing the native term representation. The interpreter accepts
finite, acyclic source terms in this first stage.

## Interpreter

On creation, `make-runtime` installs ordinary `sprolog:<-` / `<--`
clauses equivalent to:

```lisp
(sprolog:<-- (iso-solve (:iso-atom sprolog/atoms::|true|)))
(sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|,| ?a ?b))
  (iso-solve ?a)
  (iso-solve ?b))
(sprolog:<- (iso-solve ?goal)
  (iso-clause ?goal ?body)
  (iso-solve ?body))
```

The interpreter uses the existing WAM's native control primitives for
the following additional object-language operators:

| ISO goal | Interpretation |
|---|---|
| `call(G)` | Verify callable target and recurse into `iso-solve(G)` |
| `once(G)` | Use native opaque `once/1` around `iso-solve(G)` |
| `\\+ G` | Use native scoped negation around `iso-solve(G)` |
| `(If -> Then ; Else)` | Use native if-then-else with commitment on first `If` solution |
| `If -> Then` | Use native committed if-then |
| `catch(G, Ball, Recovery)` | Use the existing WAM exception handler and unwind trail |
| `throw(Ball)` | Propagate tagged ISO terms through the existing exception mechanism |
| `var/1`, `nonvar/1`, `atom/1`, `compound/1`, etc. | Inspect tagged ISO terms, not Lisp cons objects |
| `==/2`, `\\=/2`, `unify_with_occurs_check/2` | Use the native WAM unifier and term predicates on tagged ISO terms |
| `is/2` | Translate tagged arithmetic expressions into the native numeric evaluator |

### Predicate-local cut without leaking through the meta-interpreter

A cut is not an ordinary Prolog goal that can be added naively to
`iso-solve/1`. A cut inside a meta-interpreter would otherwise prune the
wrong WAM choice-point scope.

For the supported placement — a top-level conjunction in a source clause —
the loader **eliminates cuts at consult time**, preserving the original
source order and each clause's variables. Source clauses with the same
functor/arity are grouped into one `iso-clause/2` object-language fact
whose body is an explicit disjunction of clause alternatives.

For example,

```prolog
p(X) :- q(X), !, r(X).
p(fallback).
```

becomes, schematically,

```prolog
p(Call) :-
   (Call = p(X), q(X) -> r(X) ;
    Call = p(fallback)).
```

The fallback is visited only if the prefix (including head unification and
`q(X)`) fails. If the prefix succeeds, only its first solution is retained
and **failure in `r(X)` cannot fall through to the next clause**. Earlier
clause alternatives and caller choices retain their scope. Subsequent cuts
in a conjunction become further nested committed conditionals.

This is cut *elimination for a restricted fragment*, not general ISO cut
handling. Cuts appearing inside nested disjunctions, conditionals, negations,
meta-calls, or standalone top-level queries are explicitly rejected with
`unsupported-iso-goal`. No unsupported cut is executed with a guessed
meaning.

Every clause remains represented as data in `iso-clause/2`; the WAM
directly compiles the S-expression `iso-solve` interpreter, not the ISO
user-defined predicates. Consult currently recompiles its meta-clause
lookup relation for the current runtime.

## Limitations: strict boundary

The interpreter supports finite Horn programs, recursion, conjunction,
disjunction, truth, failure, equality, restricted predicate-local cuts,
`call/1`, `once/1`, `\\+/1`, if-then-else, `catch/3` and `throw/1`.
It does **not** implement general arbitrary-position ISO cut,
`call/N` for `N>1`, arithmetic comparisons and some ISO arithmetic
functions, DCGs, directives, dynamic predicates, operator declarations,
proper streams, or a standalone
ISO module system. The ISO lexer/parser is still deliberately restricted:
floating-point and double-quoted syntax are not accepted.

Other unimplemented predicates currently behave as absent facts
(failure) rather than signalling ISO `existence_error`, which is a
**known semantic deviation**. The reader protects the implemented static/control predicate indicators,
but does not yet enforce the full ISO static/dynamic predicate rules.

This subsystem is a *bootstrap interpretation layer*, not an implementation
claiming complete ISO/IEC 13211-1 compliance. Its tests are separate from
those of the native `.pl` loader.

## Test and future milestones

```sh
sbcl --noinform --disable-debugger --script tests/iso/bootstrap-tests.lisp
sbcl --noinform --disable-debugger --script tests/iso/control-tests.lisp
sbcl --noinform --disable-debugger --script tests/iso/differential-tests.lisp
```

The differential suite executes identical Prolog input against both the
legacy `sprolog:load-prolog` path and the tagged ISO interpreter, checking
shared results and recording intentional representation differences:
`f(a,b)` vs `[f,a,b]`, `[]` vs `nil`, and case-sensitive atoms.
These are behavioral smoke tests, not proof of semantic equivalence.

GitHub Actions runs these assertions independently of the pre-existing
`tests/iso/run.lisp` compatibility suite, which exercises the **native** .pl
loader and must not be interpreted as an ISO bootstrap compliance rate.

Next:
1. Source-positioned ISO lexer/parser, finite terms, floating point numbers,
   operator declarations and syntax-error classification.
2. General arbitrary-position cut and meta-call scope semantics, plus
   complete ISO type/domain/permission errors and exception behavior.
3. ISO database semantics including assert/retract, proper stream/atom/type
   handling, and separate indexed clauses.
4. A differential execution test driver for interpreted ISO programs versus
   a reference ISO implementation and the native WAM compilation path.
5. Bootstrapped parser and ISO-to-WAM compilation with the interpreter as
   semantic reference.
