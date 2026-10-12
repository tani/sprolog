# Documentation

[Project README](../README.md)

- [User guide](MANUAL.md): term syntax, queries, lexical `let`, Lisp callbacks, DCGs, SLG, WAM and GC.
- [Builtin reference](BUILTINS.md): supported predicates, arithmetic and Lisp-friendly names.
- [Validation](VALIDATION.md): test coverage, stress tests and current limitations.
- [Benchmarks](BENCHMARKS.md): measured performance, allocation profiles, bottlenecks and reproduction commands.
- [Type declaration experiment](TYPE-DECLARATIONS.md): SBCL measurements without algorithm changes.
- [Roadmap](ROADMAP.md): implementation status and planned improvements.
- [Changelog](../CHANGELOG.md): release history.

Commands in these documents are run from the repository root. Benchmark scripts and raw results are in [`benchmarks/`](../benchmarks/); runnable examples are in [`examples/`](../examples/).

- [Development](DEVELOPMENT.md): package-inferred ASDF systems, Nix outputs and portability

- [Prolog .pl loader and ASDF integration](PROLOG-LOADER.md): syntax, packages, component operations, limitations

- [ISO Prolog compatibility measurements](ISO-COMPATIBILITY.md): .pl probes, pass-rate denominator, CI reports and upstream sources

- [ISO Prolog bootstrap](ISO-BOOTSTRAP.md): tagged terms, S-expression Prolog interpreter, current semantics and milestones
