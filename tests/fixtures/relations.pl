% Conventional Prolog syntax, converted to sprolog native terms.
pl_parent(alice, bob).
pl_parent(bob, charlie).
pl_ancestor(X, Y) :- pl_parent(X, Y).
pl_ancestor(X, Y) :- pl_parent(X, Z), pl_ancestor(Z, Y).
pl_split([Head|Tail], Head, Tail).
pl_seven(X) :- X is 1 + 2 * 3.
pl_distinct(X, Y) :- \+ (X = Y).
pl_word(cat) --> [cat].
pl_word(dog) --> [dog].
pl_sentence(X) --> pl_word(X).
