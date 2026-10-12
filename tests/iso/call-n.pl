% Closure arity / shared-variable regression corpus for ISO call/N.
unary(a).
unary(b).
binary(a,b).
binary(a,c).
ternary(a,b,c).
septary(a,b,c,d,e,f,g).
octary(a,b,c,d,e,f,g,h).
app_unary(X) :- call(unary, X).
app_binary(X,Y) :- call(binary, X, Y).
app_ternary(X,Y,Z) :- call(ternary, X, Y, Z).
app_octary(A,B,C,D,E,F,G,H) :- call(octary(A), B,C,D,E,F,G,H).
part_binary(Y) :- call(binary(a), Y).
part_ternary(Z) :- call(ternary(a,b), Z).
meta_twice(X) :- call(call(unary), X).
meta_equals(X) :- call(=, X, a).
meta_alias(X,Y) :- call(=, X, Y).
meta_direct(P) :- P.
