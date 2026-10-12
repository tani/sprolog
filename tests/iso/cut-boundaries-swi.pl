% Independent SWI-Prolog baseline for the ISO interpreter's FUTURE
% explicit object-language cut frame. Not loaded into sprolog/iso.
:- initialization(main, main).

choice(a).
choice(b).

cut_in_left(X) :-
    ( choice(X), ! ; X = other ).
cut_in_left(fallback).

cut_in_right(X) :-
    ( X = a ; X = b, ! ),
    X = b.
cut_in_right(fallback).

cut_then_fail(X) :-
    ( X = a, !, fail ; X = b ).
cut_then_fail(fallback).

caller(X) :- cut_in_left(X).
caller(fallback).

opaque_meta(X) :-
    call((X = a, !, fail ; X = b)).
opaque_meta(fallback).

opaque_condition(X) :-
    ( X = a, !, fail -> true ; X = b ).
opaque_condition(fallback).

transparent_then(X) :-
    ( true -> (X = a, !, true) ; X = b ).
transparent_then(fallback).

transparent_else(X) :-
    ( fail -> X = a ; (X = b, !, true) ).
transparent_else(fallback).

first_clause_cut(X) :-
    choice(X), !.
first_clause_cut(fallback).

expect(Name, Goal, Expected) :-
    findall(X, call(Goal, X), Actual),
    ( Actual == Expected ->
        format('PASS ~w ~w~n', [Name, Actual])
    ; format(user_error,
             'FAILED ~w: expected ~q, observed ~q~n',
             [Name, Expected, Actual]),
      throw(error(iso_cut_reference_mismatch(Name), expect/3))
    ).

main :-
    expect(left_disjunction_cut, cut_in_left, [a]),
    expect(right_disjunction_cut, cut_in_right, [b]),
    expect(failure_after_cut, cut_then_fail, []),
    expect(callee_opaque_to_caller, caller, [a,fallback]),
    expect(meta_call_opaque, opaque_meta, [fallback]),
    expect(condition_opaque, opaque_condition, [b,fallback]),
    expect(then_transparent, transparent_then, [a]),
    expect(else_transparent, transparent_else, [b]),
    expect(simple_cut, first_clause_cut, [a]),
    writeln('9 reference cut-scope checks passed.').
