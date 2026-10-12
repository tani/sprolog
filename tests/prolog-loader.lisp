(defpackage #:sprolog/tests/prolog-loader (:use #:cl #:sprolog/tests/let))
(in-package #:sprolog/tests)

(defun run-prolog-loader-tests ()
  (let* ((*database* (make-database))
         (root (asdf:system-source-directory "sprolog"))
         (source (merge-pathnames "tests/fixtures/relations.pl" root))
         (invalid (merge-pathnames "tests/fixtures/invalid.pl" root)))
    (let ((forms (read-prolog source :package :sprolog/tests)))
      (check (= 10 (length forms)) "pl reader returns all source clauses")
      (check (equal (caar forms) :fact) "pl reader recognizes facts")
      (check (equal (car (fourth forms)) :rule) "pl reader recognizes rules"))
    (check (handler-case (progn (read-prolog invalid :package :sprolog/tests) nil)
             (error () t)) "syntax errors are signaled")
    (check (not (gethash (cons 'pl_invalid 1)
                         (sprolog::database-predicates *database*)))
           "bad file has not been loaded")
    ;; Do not nest ASDF:OPERATE inside ASDF's TEST-OP: exercise loading
    ;; directly here and run the ASDF integration smoke test separately.
    (check (find-class 'asdf::prolog nil) "ASDF extension registered")
    (load-prolog source :package :sprolog/tests)
    (check (equal (mapcar (lambda (s) (value-of '?who s))
                          (query '((pl_ancestor alice ?who))))
                  '(bob charlie)) "loaded multiple Prolog clauses")
    (check (equal '(a b) (value-of '?rest
                       (first (query '((pl_split (z a b) ?head ?rest))))))
           "Prolog list tail syntax")
    (check (= 7 (value-of '?x (first (query '((pl_seven ?x))))))
           "operator precedence and arithmetic")
    (check (query '((pl_distinct a b))) "negation-as-failure succeeds")
    (check (null (query '((pl_distinct a a)))) "negation-as-failure fails")
    (check (equal 'cat (value-of '?word
                        (first (query '((phrase (pl_sentence ?word) (cat)))))))
           "DCG terminals and nonterminals")
    (check (= 2 (length (query '((pl_parent ?x ?y)))))
           "two file clauses retained")
    ;; A reload replaces the first clause for each predicate instead of adding
    ;; duplicate copies to the global database.
    (load-prolog source :package :sprolog/tests)
    (check (= 2 (length (query '((pl_parent ?x ?y)))))
           "manual reload does not duplicate clauses")
    ;; A parsed malformed file must not partially publish an earlier fact.
    (check (handler-case
               (progn (load-prolog invalid :package :sprolog/tests) nil)
             (error () t)) "loading malformed file fails")
    (check (not (gethash (cons 'pl_invalid 1)
                         (sprolog::database-predicates *database*)))
           "failed parse leaves database unchanged")))
