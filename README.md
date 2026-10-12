# sprolog

S-expression Prolog for Common Lisp, with native Lisp cons terms, an explicit WAM execution model, DCGs, SLG variant tabling and VM garbage collection.

An independent implementation inspired by the PAIP / Allegro Prolog APIs. ISO Prolog conformance and full Allegro compatibility are outside its scope. [MIT licensed](LICENSE).

## Load

No external Lisp libraries are required. From the repository directory:

```lisp
(require :asdf)
(asdf:load-asd (truename "sprolog.asd"))
(asdf:load-system "sprolog")
(use-package :sprolog)
```

## ASDF .pl loader

To load conventional Prolog source files (facts, rules, lists and basic DCGs),
load the optional ASDF extension `sprolog/asdf` in the consuming system:

```lisp
(asdf:defsystem "my-prolog-program"
  :defsystem-depends-on ("sprolog/asdf")
  :depends-on ("sprolog")
  :serial t
  :components ((:prolog "example" :package "CL-USER")
               (:file "main")))
```

The `:prolog "example"` component reads `example.pl`. Use
`(sprolog:load-prolog "example.pl")` to consult a file directly.
The source syntax bridge is intentionally limited; it is not a full ISO
Prolog parser. See [the loader guide](docs/PROLOG-LOADER.md).

## Nix

The flake follows [nix-common-lisp](https://github.com/tani/nix-common-lisp),
with a pinned `flake.lock` and no external Lisp dependencies.

```sh
nix develop                    # all available implementations
nix develop .#sbcl -c sbcl      # one implementation
nix run .#main-sbcl             # REPL with sprolog loaded
nix run .#test-sbcl             # complete test suite
nix build .#lib-sbcl            # ASDF library
nix flake check -L              # test all available implementations
```

Replace `sbcl` with `ecl`, `abcl`, `ccl`, `mkcl`, `clisp`, `cmucl_binary`
or `clasp-common-lisp`. Outputs are provided only where the pinned Nixpkgs
supports the implementation. GitHub Actions tests those outputs on Linux
(x86-64 and ARM64) and macOS (ARM64).

ASDF uses `package-inferred-system`: module dependencies are declared by each
file's `defpackage`. The implementation remains in the shared `sprolog`
package, preserving public symbols and existing `sprolog::` references.
See [development notes](docs/DEVELOPMENT.md) for module layout and portability.

## Define and query

```lisp
(<-- (append () ?ys ?ys))
(<- (append (?x . ?xs) ?ys (?x . ?zs))
    (append ?xs ?ys ?zs))

(?- (append ?xs ?ys (a b c)))
```

`<--` replaces clauses of the same name and arity; `<-` appends a clause. `?x` is a logic variable; each `?` is anonymous. `?-` computes and displays one answer at a time. Type `;` followed by Enter for the next answer, or Enter alone to stop. EOF also stops. Failure prints `false.`; success without bindings prints `true.`. It returns no values.

Use `(query '((append ?xs ?ys (a b c))))` to collect all answers as binding alists, or add `:limit` to bound collection.

Terms and lists share the same Lisp cons representation. Write `(f a b)` or `(a . ?tail)` directly. Definition and query macros treat goals as data, so ordinary terms need no quote.

## DCGs

```lisp
(---> (article) '(the))
(---> (noun cat) '(cat))
(--> (noun dog) '(dog))
(---> (sentence ?noun)
  (article)
  (noun ?noun))

(?- (phrase (sentence ?noun) (the cat)))
;; Prints ?NOUN = CAT; Enter stops.
```

`--->` replaces grammar clauses; `-->` appends one. Within a DCG, `'(a b)` denotes a token sequence; variables inside it still unify. Use `and` for sequences, `or` for alternatives and `do` for ordinary goals that consume no input.

## Tabling

```lisp
(table 'path 2)
(<-- (path ?x ?y) (path ?x ?z) (edge ?z ?y))
(<- (path ?x ?y) (edge ?x ?y))
(<-- (edge a b))
(<- (edge b c))
(<- (edge c a))

(?- (path a ?y))
;; Prints ?Y = B; type ; for another answer.
```

SLG supports left and mutual recursion, plus ground `tnot`. Conditional answers display `undefined` and their delayed negations. Cuts over unfinished tables raise an error. See the [user guide](docs/MANUAL.md#slg-resolution) for details and restrictions.

Use `prolog` / `lisp` / `lispp` for lexical Lisp callbacks and `(let name expression)` for a Lisp binding shared by subsequent callbacks and `make-query` / `next-solution` / `close-query` for streaming answers. Builtins cover unification, arithmetic, dynamic definitions, exceptions, answer collection and character/byte I/O.

## Examples and tests

```sh
sbcl --script examples/interactive.lisp
sbcl --script examples/append.lisp
sbcl --script examples/dcg.lisp
sbcl --script examples/slg.lisp
sbcl --script examples/builtins.lisp
sbcl --script examples/let.lisp
sbcl --dynamic-space-size 2048 --control-stack-size 1 --script tests/run.lisp
```

Validated on SBCL 2.2.9 / Linux x86-64: 4,190 checks pass, including one million tail calls with a 1 MiB Lisp control stack.

## Documentation

See the [documentation index](docs/README.md).

- [User guide](docs/MANUAL.md): terms, queries, Lisp callbacks, DCGs, SLG, WAM, GC and limitations
- [Builtins](docs/BUILTINS.md): supported predicates and Lisp-friendly names
- [Validation](docs/VALIDATION.md): semantic coverage and stress tests
- [Benchmarks](docs/BENCHMARKS.md): timings, allocation profiles and bottlenecks
- [Roadmap](docs/ROADMAP.md) and [changelog](CHANGELOG.md)
