% Predicate-local cut and opaque meta-control regression corpus.
prefix(a).
prefix(b).
prefix(c).

stop(X) :- prefix(X), !.
stop(fallback).

cut_then_fail(X) :- prefix(X), !, fail.
cut_then_fail(fallback).

cut_after_guard(X) :- X = a, !, prefix(X).
cut_after_guard(X) :- X = other.

double_cut(X) :- prefix(X), !, X = a, !.
double_cut(fallback).

before_cut(previous).
before_cut(X) :- prefix(X), !.
before_cut(later).

after_cut(X) :- stop(X).
after_cut(fallback).

without_cut(X) :- prefix(X).
without_cut(fallback).

disjunction_cut(X) :- (X = a ; X = b), !.
disjunction_cut(fallback).

once_pick(X) :- once(prefix(X)).
call_pick(X) :- call(prefix(X)).
not_pick(X) :- \+ prefix(X).

choose(X) :- (X = a -> true ; X = b).
choose(X) :- X = c.
cut_after_then(X) :- X = a, !, (true -> X = a ; X = other).
cut_after_then(fallback).
