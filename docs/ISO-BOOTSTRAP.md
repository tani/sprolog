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

The actual evaluator also implements `fail/0`, `=/2`, and `;/2`.
Each parsed ISO clause is stored as a **fact about the object language**:
`(iso-clause <tagged-head> <tagged-body>)`. These are not directly installed
as executable ISO predicates in the native WAM; only the **meta-interpreter**
is directly executable. This makes it possible to introduce and test
separate ISO rules for control and builtins later.

## Limitations: strict boundary

Stage 2 currently supports finite Horn programs, recursion, conjunction,
disjunction, truth, failure, and equality. It does **not** implement ISO cut,
if-then, negation-as-failure, meta-call, exceptions, arithmetic builtins,
DCGs, directives, dynamic predicates, operator declarations, or a standalone
ISO module system. The ISO parser is still the restricted existing Prolog
scanner; floating-point and double-quoted syntax are not silently accepted.

Recognized unsupported *control constructs* (for example `!`, `->`,
`\\+`, `call/1`, `once/1`, `catch/3`, `throw/1`, `is/2`) are rejected
with `unsupported-iso-goal`, including when they appear in a consulted
clause body. This is intentional: interpreting cut as an ordinary goal would
violate its predicate-local pruning semantics. Other unimplemented predicates
currently behave as absent facts (failure) rather than raising ISO's
`existence_error`, which is a **known semantic deviation**.

The meta-interpreter does not aim at production performance: `iso-clause/2`
is currently a native compiled predicate that is rebuilt when clauses are
consulted; clause indexing and specialization are future optimizations.

## Test and future milestones

```sh
sbcl --noinform --disable-debugger --script tests/iso/bootstrap-tests.lisp
```

GitHub Actions runs these assertions independently of the pre-existing
`tests/iso/run.lisp` compatibility suite, which exercises the **native** .pl
loader and must not be interpreted as an ISO bootstrap compliance rate.

Next:
1. Source-positioned ISO lexer/parser, finite terms, floating point numbers,
   operator declarations and syntax-error classification.
2. Explicit clause-entry choice-point / cut barriers, meta-call,
   if-then-else, negation, exception propagation and ISO error terms.
3. ISO database semantics including assert/retract, proper stream/atom/type
   handling, and separate indexed clauses.
4. A differential execution test driver for interpreted ISO programs versus
   a reference ISO implementation and the native WAM compilation path.
5. Bootstrapped parser and ISO-to-WAM compilation with the interpreter as
   semantic reference.
