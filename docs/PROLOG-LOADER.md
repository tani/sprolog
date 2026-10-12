# Prolog source loader and ASDF integration

The optional `sprolog/asdf` system registers an ASDF component class named
`:prolog`. Such components have a `.pl` extension and load conventional
Prolog clause syntax into sprolog's native Lisp-cons/WAM database.

## Use in another .asd file

```lisp
(asdf:defsystem "my-program"
  :defsystem-depends-on ("sprolog/asdf")
  :depends-on ("sprolog")
  :serial t
  :components ((:prolog "example" :package "CL-USER")
               (:file "main")))
```

This loads `example.pl` before `main.lisp`. The component's `:package`
determines the Lisp symbol identities used for predicate names, atoms and
variables. If `main.lisp` lives in `MY-APP`, specify
`:package "MY-APP"` and ensure the package exists before the component is
loaded (for example with a preceding `:file "package"`). The default is
`CL-USER`.

Load and query programmatically:

```lisp
(require :asdf)
(asdf:load-asd (truename "sprolog.asd"))
(asdf:load-asd (truename "examples/asdf-prolog-demo.asd"))
(asdf:load-system "asdf-prolog-demo")
(sprolog:query '((ancestor alice ?who)))
```

## Supported .pl syntax

```prolog
parent(alice, bob).
parent(bob, charlie).
ancestor(X, Y) :- parent(X, Y).
ancestor(X, Y) :- parent(X, Z), ancestor(Z, Y).

member(X, [X|_]).
member(X, [_|Xs]) :- member(X, Xs).

word(cat) --> [cat].
word(dog) --> [dog].
sentence(X) --> word(X).

:- table(path/2).
```

Facts, rules, integers, variables, anonymous `_`, quoted atoms, quoted
strings, lists (including `[Head|Tail]`), `!`, parentheses, conjunction,
disjunction, simple if-then, negation (`\\+`), common comparisons and integer
arithmetic operators are recognized. The loader supports DCG terminal lists,
nonterminals, conjunction and disjunction. `table(Name/Arity)` is the only
load-time directive currently accepted.

This is deliberately a restricted *syntax bridge*, **not** an ISO Prolog
implementation. Compound terms become ordinary Lisp cons terms. Uppercase
variables become Lisp `?NAME` symbols. Quoted strings become Lisp strings.
Module declarations, user-defined operators, floats, cuts in directives,
`{Goal}` DCG escapes, term expansion, Prolog-specific I/O and the ISO
directive ecosystem are not implemented. Unsupported inputs signal errors;
they are not silently ignored.

## Loading and recompilation

`(sprolog:read-prolog pathname :package ...)` parses without side effects.
`(sprolog:load-prolog pathname :package ... :database ...)` loads clauses
into a database. For each predicate, the first clause in the file replaces
existing clauses and later clauses append. Parsing finishes before database
mutation, so lexical/syntax errors cannot partially load a source file.
There is no rollback of semantic errors encountered while adding clauses.

ASDF `compile-op` validates `.pl` source but produces no FASL, because WAM
code is compiled directly into the live database by `load-op`.
`load-source-op` also consults the file. ASDF tracks file inputs and load
actions; forcing a reload consults the file again. Predicate state is in the
current Lisp image, not a persistent compilation cache.

Existing S-expression syntax (`<-`, `<--`, `-->`, `--->`) remains
the primary native interface. This loader does not change those APIs.
