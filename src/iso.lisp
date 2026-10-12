;; ISO Prolog bootstrap on top of the Lisp-native S-expression WAM.
;; The native sprolog database and term representation remain unchanged.
(defpackage #:sprolog/src/iso
  (:nicknames #:sprolog/iso)
  (:use #:cl #:sprolog/src/prolog-loader)
  (:shadow #:atom)
  (:export #:make-runtime #:runtime-database #:consult #:query
           #:parse-term #:parse-goal #:atom #:compound #:atom-p
           #:compound-p #:term-functor #:term-arguments
           #:unsupported-iso-goal))
(defpackage #:sprolog/iso/source (:use))
(in-package #:sprolog/iso)

;; ISO atom names are case-sensitive. SPROLOG/ATOMS is already present in the
;; native engine and is excluded from its ?-variable heuristic.
(defun iso-symbol (name)
  (intern name (find-package :sprolog/atoms)))

(defun atom (name)
  "Construct an ISO atom, including [] and quoted atoms. Never returns NIL."
  (check-type name string)
  (list :iso-atom (iso-symbol name)))

(defun compound (name &rest arguments)
  "Construct an ISO compound term, which is distinct from every ISO list."
  (check-type name string)
  (unless arguments (error "ISO compound ~S must have positive arity" name))
  (list* :iso-compound (iso-symbol name) arguments))

(defun atom-p (term)
  (and (consp term) (eq (first term) :iso-atom)
       (consp (cdr term)) (null (cddr term))
       (symbolp (second term))))

(defun compound-p (term)
  (and (consp term) (eq (first term) :iso-compound)
       (consp (cdr term)) (symbolp (second term))
       (consp (cddr term)) (sprolog::finite-list-p term)))

(defun term-functor (term)
  (cond ((atom-p term) (symbol-name (second term)))
        ((compound-p term) (symbol-name (second term)))
        (t (error "Not an ISO atom or compound: ~S" term))))

(defun term-arguments (term)
  (if (compound-p term) (cddr term)
      (error "Not an ISO compound: ~S" term)))

(defun source-parser (stream)
  (sprolog::make-pl-reader stream (find-package :sprolog/iso/source)))

(defun encode-list (items)
  (cond ((sprolog::pl-list-p items)
         (encode-list (sprolog::pl-list-value items)))
        ((null items) (atom "[]"))
        ((consp items)
         (compound "." (encode-term (car items)) (encode-list (cdr items))))
        (t (encode-term items))))

(defun encode-term (raw)
  (cond ((sprolog::pl-list-p raw) (encode-list raw))
        ((sprolog::pl-iso-atom-p raw)
         (atom (symbol-name (sprolog::pl-iso-atom-name raw))))
        ((and (symbolp raw) (sprolog::variable-symbol-p raw)) raw)
        ((symbolp raw) (atom (symbol-name raw)))
        ((integerp raw) raw)
        ((stringp raw)
         (error "ISO double-quoted string syntax is not implemented: ~S" raw))
        ((consp raw)
         (unless (and (symbolp (car raw)) (cdr raw)
                      (sprolog::finite-list-p raw))
           (error "Unsupported ISO compound syntax: ~S" raw))
         (apply #'compound (symbol-name (car raw))
                (mapcar #'encode-term (cdr raw))))
        (t (error "Unsupported ISO term: ~S" raw))))

(defun read-expression (reader)
  (encode-term (sprolog::pl-expression reader 0)))

(defun check-eof (reader)
  (sprolog::pl-accept reader ".")
  (unless (eq :eof (car (sprolog::pl-peek reader)))
    (sprolog::pl-error reader "Unexpected source after ISO term")))

(defun parse-term (text)
  "Parse one ISO-style term while retaining compound/list/atom distinctions."
  (with-input-from-string (stream text)
    (let* ((reader (source-parser stream))
           (term (read-expression reader)))
      (check-eof reader)
      term)))

(defun iso-callable-p (term)
  (or (atom-p term) (compound-p term)))

(defun parse-goal (text)
  (let ((term (parse-term text)))
    (unless (iso-callable-p term)
      (error "ISO goal must be callable: ~S" term))
    term))

(define-condition unsupported-iso-goal (error)
  ((goal :initarg :goal :reader unsupported-goal))
  (:report (lambda (c stream)
             (format stream "Unsupported ISO control/builtin goal: ~S"
                     (unsupported-goal c)))))

(defun name-is (term name arity)
  (and (if (zerop arity) (atom-p term) (compound-p term))
       (string= (term-functor term) name)
       (or (zerop arity) (= arity (length (term-arguments term))))))

(defun iso-control-branch-p (term)
  (name-is term "->" 2))

(defun ensure-callable (value)
  "Check the already-reified ISO call target in a native Lisp bridge."
  (unless (iso-callable-p value)
    (if (and (symbolp value) (sprolog::variable-symbol-p value))
        (sprolog::iso-error "instantiation_error")
        (sprolog::iso-error "type_error" (sprolog::iso-atom "callable") value)))
  t)

(defun validate-goal (goal &optional allow-cut)
  "Conservatively admit only control constructs with implemented semantics.
Cut is accepted solely in the top-level conjunction of a source clause;
the enclosing predicate's clause alternatives are compiled into one guarded
object-level conditional, preserving its commit point."
  (cond
    ((name-is goal "," 2)
     (dolist (child (term-arguments goal))
       (validate-goal child allow-cut)))
    ((name-is goal "!" 0)
     (unless allow-cut
       (error 'unsupported-iso-goal :goal goal)))
    ((or (name-is goal ";" 2) (name-is goal "->" 2))
     (dolist (child (term-arguments goal))
       (validate-goal child nil)))
    ((or (name-is goal "call" 1) (name-is goal "once" 1)
         (name-is goal "\\+" 1))
     (validate-goal (first (term-arguments goal)) nil))
    ((name-is goal "catch" 3)
     (validate-goal (first (term-arguments goal)) nil)
     (validate-goal (third (term-arguments goal)) nil))
    ((name-is goal "throw" 1) nil)
    ((name-is goal "*->" 2)
     (error 'unsupported-iso-goal :goal goal))))
(defun reserved-iso-head-p (head)
  "Protect the static/control predicate indicators implemented by Stage 2."
  (some (lambda (indicator)
          (name-is head (car indicator) (cdr indicator)))
        '(("true" . 0) ("fail" . 0) ("!" . 0)
          ("," . 2) (";" . 2) ("->" . 2) ("=" . 2)
          ("call" . 1) ("once" . 1) ("\\+" . 1)
          ("catch" . 3) ("throw" . 1)
          ("is" . 2) ("==" . 2) ("\\==" . 2) ("\\=" . 2)
          ("unify_with_occurs_check" . 2)
          ("atom" . 1) ("atomic" . 1) ("compound" . 1)
          ("callable" . 1) ("var" . 1) ("nonvar" . 1)
          ("integer" . 1) ("number" . 1) ("ground" . 1))))

(defun read-program (pathname)
  "Parse all clauses before mutating a database. No directives/DCGs yet."
  (with-open-file (stream pathname :direction :input)
    (let ((reader (source-parser stream)) (clauses nil))
      (loop
        (when (eq (car (sprolog::pl-peek reader)) :eof)
          (return (nreverse clauses)))
        (when (sprolog::pl-is reader ":-")
          (sprolog::pl-error reader "ISO directives are not implemented"))
        (let ((head (encode-term (sprolog::pl-expression reader 16))))
          (unless (iso-callable-p head)
            (sprolog::pl-error reader "Clause head must be callable"))
          (when (reserved-iso-head-p head)
            (sprolog::pl-error reader
              "Cannot redefine a static ISO control or builtin predicate: ~S"
              head))
          (let ((body
                  (cond ((sprolog::pl-accept reader ".") (atom "true"))
                        ((sprolog::pl-accept reader ":-")
                         (prog1 (read-expression reader)
                           (sprolog::pl-expect reader ".")))
                        (t (sprolog::pl-error reader
                              "Expected '.' or ':-' after clause head")))))
            (validate-goal body t)
            (push (cons head body) clauses)))))))

(defun control (name &rest args)
  (if args (apply #'compound name args) (atom name)))

(defun goal-sequence (goal)
  "Flatten only top-level conjunction. Nested control remains opaque."
  (if (name-is goal "," 2)
      (append (goal-sequence (first (term-arguments goal)))
              (goal-sequence (second (term-arguments goal))))
      (list goal)))

(defun conjunction (goals)
  (if (null goals) (atom "true")
      (reduce (lambda (left right) (control "," left right))
              (cdr goals) :initial-value (car goals))))

(defun iso-rename-clause (clause)
  "Standardize apart all variables, preserving each within-clause alias."
  (let ((variables (make-hash-table :test 'eq)))
    (destructuring-bind (head . body)
        (sprolog::map-term
         (list (car clause) (cdr clause))
         (lambda (value)
           (if (and (symbolp value) (sprolog::variable-symbol-p value))
               (or (gethash value variables)
                   (setf (gethash value variables) (gensym "?ISO-")))
               value)))
      (cons head (car body)))))

(defun head-key (head)
  (cond ((atom-p head) (cons (term-functor head) 0))
        ((compound-p head)
         (cons (term-functor head) (length (term-arguments head))))
        (t (error "Invalid ISO head ~S" head))))

(defun clause-prototype (key)
  (if (zerop (cdr key)) (atom (car key))
      (apply #'compound (car key)
             (loop repeat (cdr key) collect (gensym "?ARG-")))))

(defun split-at-cut (goals)
  (let ((prefix nil))
    (dolist (goal goals (values nil nil nil))
      (if (name-is goal "!" 0)
          (return-from split-at-cut
            (values (nreverse prefix) (cdr (member goal goals :test #'eq)) t))
          (push goal prefix)))))

(defun compile-guarded-clause (prototype clause alternatives)
  "Eliminate a top-level cut by guarding the remaining clauses with ->.
The condition commits on its FIRST successful prefix, *even if* the
suffix then fails. The ELSE alternative is considered only when the
prefix fails. Earlier clauses remain in the outer disjunction."
  (let* ((entry (iso-rename-clause clause))
         (head-test (control "=" prototype (car entry)))
         (goals (goal-sequence (cdr entry))))
    (labels ((lower (pending alternative extra)
               (multiple-value-bind (prefix suffix cutp) (split-at-cut pending)
                 (if cutp
                     (control ";" (control "->"
                                            (conjunction (append extra prefix))
                                            (lower suffix (atom "fail") nil))
                              alternative)
                     (let ((this (conjunction (append extra pending))))
                       (if (name-is alternative "fail" 0) this
                           (control ";" this alternative)))))))
      (lower goals alternatives (list head-test)))))

(defun grouped-iso-clauses (clauses)
  "Compile all source clauses for each predicate into a single meta clause.
This leaves ISO resolution inside iso-solve, while giving each predicate one
explicit choice/cut scope in its object-level disjunction."
  (let ((keys nil) (groups (make-hash-table :test 'equal)))
    (dolist (clause clauses)
      (let ((key (head-key (car clause))))
        (unless (gethash key groups) (push key keys))
        (push clause (gethash key groups))))
    (loop for key in (nreverse keys)
          for prototype = (clause-prototype key)
          for cases = (nreverse (gethash key groups))
          collect (cons prototype
                        (loop with result = (atom "fail")
                              for source in (reverse cases)
                              do (setf result (compile-guarded-clause
                                               prototype source result))
                              finally (return result))))))

(defstruct (runtime (:constructor %make-runtime (database &optional clauses)))
  database clauses)

(defun iso-arithmetic->native (term)
  "Bridge ISO arithmetic syntax to the existing native numeric evaluator.
The ISO term representation stays tagged everywhere else."
  (cond
    ((numberp term) term)
    ((and (symbolp term) (sprolog::variable-symbol-p term))
     (sprolog::iso-error "instantiation_error"))
    ((atom-p term) (iso-symbol (term-functor term)))
    ((compound-p term)
     (cons (iso-symbol (term-functor term))
           (mapcar #'iso-arithmetic->native (term-arguments term))))
    (t (sprolog::iso-error "type_error" (sprolog::iso-atom "evaluable") term))))

(defun install-interpreter (database)
  "Bootstrap the control evaluator USING native S-expression Prolog clauses.
Native -> and once introduce the correct opacity/commit semantics for
the supported ISO constructs. Cut is eliminated at consult time."
  (let ((sprolog:*database* database))
    (sprolog:<-- (iso-solve (:iso-atom sprolog/atoms::|true|)))
    (sprolog:<- (iso-solve (:iso-atom sprolog/atoms::|fail|)) fail)
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|=| ?x ?y))
      (= ?x ?y))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|,| ?a ?b))
      (iso-solve ?a) (iso-solve ?b))
    ;; The first alternative of a conditional disjunction must commit
    ;; at this disjunction's frame, including when its THEN branch fails.
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|;|
                            (:iso-compound sprolog/atoms::|->| ?condition ?then)
                            ?otherwise))
      (or (-> (iso-solve ?condition) (iso-solve ?then))
          (iso-solve ?otherwise)))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|;| ?a ?b))
      (lispp (not (iso-control-branch-p ?a)))
      (or (iso-solve ?a) (iso-solve ?b)))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|->| ?if ?then))
      (-> (iso-solve ?if) (iso-solve ?then)))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|call| ?goal))
      (lispp (ensure-callable ?goal))
      (iso-solve ?goal))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|once| ?goal))
      (lispp (ensure-callable ?goal))
      (once (iso-solve ?goal)))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|\\+| ?goal))
      (lispp (ensure-callable ?goal))
      (|\\+| (iso-solve ?goal)))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|catch| ?protected ?catcher ?recovery))
      (catch (iso-solve ?protected) ?catcher (iso-solve ?recovery)))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|throw| ?ball))
      (throw ?ball))
    ;; Structural term predicates run on the tagged ISO representation,
    ;; not on the host's Lisp cons/atom classification.
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|==| ?x ?y))
      (== ?x ?y))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|\\==| ?x ?y))
      (|\\==| ?x ?y))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|\\=| ?x ?y))
      (|\\=| ?x ?y))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|unify_with_occurs_check| ?x ?y))
      (unify_with_occurs_check ?x ?y))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|var| ?x))
      (lispp (sprolog::variable-symbol-p ?x)))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|nonvar| ?x))
      (lispp (not (sprolog::variable-symbol-p ?x))))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|atom| ?x))
      (lispp (atom-p ?x)))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|atomic| ?x))
      (lispp (or (atom-p ?x) (numberp ?x))))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|compound| ?x))
      (lispp (compound-p ?x)))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|callable| ?x))
      (lispp (iso-callable-p ?x)))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|integer| ?x))
      (lispp (integerp ?x)))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|number| ?x))
      (lispp (numberp ?x)))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|ground| ?x))
      (lispp (null (sprolog::variables-in ?x))))
    ;; The WAM numeric evaluator remains the source of integer operations,
    ;; instantiation/type errors, and arithmetic exceptions.
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|is| ?x ?e))
      (lisp ?native (iso-arithmetic->native ?e))
      (is ?x ?native))
    ;; Remains defined (as failure) until source predicates are consulted.
    (sprolog:<-- (iso-clause ?head ?body) fail)
    (sprolog:<- (iso-solve ?goal)
      (iso-clause ?goal ?body)
      (iso-solve ?body))))

(defun make-runtime ()
  "Create an isolated ISO interpreter running on a native sprolog WAM DB."
  (let ((database (sprolog:make-database)))
    (install-interpreter database)
    (%make-runtime database)))

(defun consult (pathname &key (runtime (make-runtime)))
  "Parse before modifying RUNTIME; then rebuild grouped meta clauses."
  (let* ((new (read-program pathname))
         (all (append (runtime-clauses runtime) new))
         (grouped (grouped-iso-clauses all))
         (database (runtime-database runtime)))
    (sprolog::add-clause '(iso-clause ?head ?body) '((fail)) t database)
    (dolist (entry grouped)
      (sprolog::add-clause (list 'iso-clause (car entry) (cdr entry))
                          nil nil database))
    (setf (runtime-clauses runtime) all)
    (values runtime (length new))))

(defun query (text &key (runtime (make-runtime)) limit)
  "Solve a Prolog-source goal via the S-expression meta-interpreter.
Answers use tagged ISO terms; predicates and variables preserve case."
  (let ((goal (parse-goal text)))
    (validate-goal goal)
    (sprolog:query (list (list 'iso-solve goal))
                   :database (runtime-database runtime) :limit limit)))
