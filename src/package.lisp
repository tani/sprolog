(defpackage #:sprolog/src/package
  (:nicknames #:sprolog)
  (:use #:cl)
  (:export #:<- #:<-- #:?- #:prolog #:--> #:---> #:phrase #:dcg-expand #:query #:make-query #:next-solution
           #:slg-incomplete-cut #:table #:untable #:tnot #:close-query #:clear-database #:*database* #:make-database
           #:*iso-halt-function* #:iso-exception #:iso-exception-term #:builtin-predicate-inventory
           #:collect-query-garbage #:query-statistics #:disassemble-predicate #:read-prolog #:load-prolog #:parse-prolog-goal))
(in-package #:sprolog)
