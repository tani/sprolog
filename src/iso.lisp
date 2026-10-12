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

(defun validate-goal (goal)
  ;; Never execute cut/negation/if-then with incorrect meta-interpreter
  ;; semantics. A future control-frame implementation must handle them.
  (cond ((or (name-is goal "," 2) (name-is goal ";" 2))
         (dolist (child (term-arguments goal)) (validate-goal child)))
        ((or (name-is goal "!" 0) (name-is goal "->" 2)
             (name-is goal "*->" 2) (name-is goal "\\+" 1)
             (name-is goal "call" 1) (name-is goal "once" 1)
             (name-is goal "catch" 3) (name-is goal "throw" 1)
             (name-is goal "is" 2))
         (error 'unsupported-iso-goal :goal goal))))

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
          (let ((body
                  (cond ((sprolog::pl-accept reader ".") (atom "true"))
                        ((sprolog::pl-accept reader ":-")
                         (prog1 (read-expression reader)
                           (sprolog::pl-expect reader ".")))
                        (t (sprolog::pl-error reader
                              "Expected '.' or ':-' after clause head")))))
            (validate-goal body)
            (push (cons head body) clauses)))))))

(defstruct (runtime (:constructor %make-runtime (database)))
  database)

(defun install-interpreter (database)
  "Bootstrap the goal evaluator USING SPROLOG CLAUSES, not a Lisp evaluator."
  (let ((sprolog:*database* database))
    ;; Distinct tagged terms prevent f(a,b) from unifying with [f,a,b].
    (sprolog:<-- (iso-solve (:iso-atom sprolog/atoms::|true|)))
    (sprolog:<- (iso-solve (:iso-atom sprolog/atoms::|fail|)) fail)
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|=| ?x ?y))
      (= ?x ?y))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|,| ?a ?b))
      (iso-solve ?a) (iso-solve ?b))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|;| ?a ?b))
      (iso-solve ?a))
    (sprolog:<- (iso-solve (:iso-compound sprolog/atoms::|;| ?a ?b))
      (iso-solve ?b))
    ;; The empty definition prevents a native undefined-predicate exception.
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
  "Append ISO facts and Horn clauses to RUNTIME via native S-expression facts."
  (let ((clauses (read-program pathname))
        (database (runtime-database runtime)))
    (dolist (clause clauses)
      (sprolog::add-clause
       (list 'iso-clause (car clause) (cdr clause)) nil nil database))
    (values runtime (length clauses))))

(defun query (text &key (runtime (make-runtime)) limit)
  "Solve a Prolog-source goal via the S-expression meta-interpreter.
Answers use tagged ISO terms; predicates and variables preserve case."
  (let ((goal (parse-goal text)))
    (validate-goal goal)
    (sprolog:query (list (list 'iso-solve goal))
                   :database (runtime-database runtime) :limit limit)))
