% Minimal conventional-Prolog definitions used by the compatibility probes.
% This fixture is intentionally self-contained; the ISO suite is not copied.
edge(a, b).
edge(b, c).
edge(c, d).

path(X, Y) :- edge(X, Y).
path(X, Y) :- edge(X, Z), path(Z, Y).

pick(red).
pick(blue).
pick(green).

same(X, X).
different(X, Y) :- \+ (X = Y).

head_tail([Head|Tail], Head, Tail).
sequence([], []).
sequence([H|T], [H|R]) :- sequence(T, R).

commit(red) :- !.
commit(blue).

cut_choice(X) :- pick(X), !.
cut_choice(fallback).

color(red) --> [red].
color(blue) --> [blue].
color(green) --> [green].
sentence(X) --> color(X).

sum_seven(X) :- X is 1 + 2 * 3.
one_or_two(X) :- X = 1 ; X = 2.
once_choice(X) :- once(pick(X)).
nonunify(X, Y) :- X \= Y.
