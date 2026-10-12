% Bootstrap Horn fragment. These clauses are interpreted, not WAM compiled.
parent(alice, bob).
parent(bob, charlie).
ancestor(X, Y) :- parent(X, Y).
ancestor(X, Y) :- parent(X, Z), ancestor(Z, Y).
value(f(a,b)).
value([f,a,b]).
empty_list([]).
lowercase(nil).
mixed('MiXeD').
pair([a,b]).
choice(1).
choice(2).
alternative(X) :- (X = red ; X = blue).
