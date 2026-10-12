;;; JSON Lines observations from the experimental ISO Prolog interpreter.
;;; Run: sbcl --script tests/iso/reference-lisp.lisp CASES OUTFILE
(require :asdf)
(asdf:load-asd (merge-pathnames "../../sprolog.asd" *load-truename*))
(asdf:load-system "sprolog/iso")
(defpackage #:sprolog/iso/reference-runner (:use #:cl))
(in-package #:sprolog/iso/reference-runner)

(defparameter *root* (uiop:pathname-directory-pathname *load-truename*))
(defparameter *sources* (list (merge-pathnames "bootstrap.pl" *root*)
                              (merge-pathnames "controls.pl" *root*)))

(defun json-string (text output)
  (write-char #\" output)
  (loop for char across text do
    (case char
      (#\" (write-string "\\\"" output))
      (#\\ (write-string "\\\\" output))
      (#\Newline (write-string "\\n" output))
      (#\Return (write-string "\\r" output))
      (#\Tab (write-string "\\t" output))
      (otherwise
       (if (< (char-code char) 32)
           (format output "\\u~4,'0X" (char-code char))
           (write-char char output)))))
  (write-char #\" output))

(defun json-key (key output)
  (json-string key output)
  (write-char #\: output))

(defun serialize-term (term output variables)
  "Encode term structure, never print native cons as an ISO list.
Repeated unbound variables receive stable per-solution numeric identities."
  (cond
    ((sprolog/iso:atom-p term)
     (write-string "{\"atom\":" output)
     (json-string (sprolog/iso:term-functor term) output)
     (write-char #\} output))
    ((sprolog/iso:compound-p term)
     (write-string "{\"functor\":" output)
     (json-string (sprolog/iso:term-functor term) output)
     (write-string ",\"args\":[" output)
     (loop for arg in (sprolog/iso:term-arguments term)
           for first = t then nil do
       (unless first (write-char #\, output))
       (serialize-term arg output variables))
     (write-string "]}" output))
    ((integerp term)
     (write-string "{\"integer\":" output)
     (json-string (write-to-string term :base 10 :radix nil) output)
     (write-char #\} output))
    ((and (symbolp term) (sprolog::variable-symbol-p term))
     (multiple-value-bind (index exists) (gethash term variables)
       (unless exists
         (setf index (hash-table-count variables)
               (gethash term variables) index))
       (format output "{\"var\":~D}" index)))
    (t (error "Unsupported answer term in ISO reference suite: ~S" term))))

(defun serialize-answer (bindings output)
  (let ((unbound (make-hash-table :test 'eq)))
    (write-char #\{ output)
    (loop for (name . value) in bindings
          for first = t then nil do
      (unless first (write-char #\, output))
      ;; Sprolog's source ?Who variable maps to reference name Who.
      (json-key (subseq (symbol-name name) 1) output)
      (serialize-term value output unbound))
    (write-char #\} output)))

(defun serialize-observation (id result output)
  (write-char #\{ output)
  (json-key "id" output)
  (json-string id output)
  (cond
    ((eq (first result) :ok)
     (write-string ",\"status\":\"ok\",\"solutions\":[" output)
     (loop for answer in (second result)
           for first = t then nil do
       (unless first (write-char #\, output))
       (serialize-answer answer output))
     (write-string "],\"truncated\":" output)
     (write-string (if (third result) "true" "false") output))
    ((eq (first result) :exception)
     (write-string ",\"status\":\"exception\",\"exception\":" output)
     (json-string (second result) output))
    ((eq (first result) :unsupported)
     (write-string ",\"status\":\"unsupported\",\"message\":" output)
     (json-string (second result) output))
    (t
     (write-string ",\"status\":\"error\",\"message\":" output)
     (json-string (second result) output)))
  (write-string "}" output)
  (terpri output))

(defun prolog-exception-name (condition)
  (let* ((value (sprolog:iso-exception-term condition))
         (descriptor (if (and (consp value)
                              (symbolp (car value))
                              (string-equal (symbol-name (car value)) "error"))
                         (second value)
                         value)))
    (cond
      ((sprolog/iso:atom-p descriptor)
       (sprolog/iso:term-functor descriptor))
      ((sprolog/iso:compound-p descriptor)
       (sprolog/iso:term-functor descriptor))
      ((and (consp descriptor) (symbolp (car descriptor)))
       (string-downcase (symbol-name (car descriptor))))
      ((symbolp descriptor) (string-downcase (symbol-name descriptor)))
      (t (princ-to-string descriptor)))))

(defun run-goal (source limit)
  (handler-case
      (let ((runtime (sprolog/iso:make-runtime)))
        (dolist (file *sources*) (sprolog/iso:consult file :runtime runtime))
        (let ((observed (sprolog/iso:query source :runtime runtime
                                           :limit (1+ limit))))
          (list :ok (if (> (length observed) limit)
                        (subseq observed 0 limit) observed)
                (> (length observed) limit))))
    (sprolog:iso-exception (condition)
      (list :exception (prolog-exception-name condition)))
    (sprolog/iso:unsupported-iso-goal (condition)
      (list :unsupported (princ-to-string condition)))
    (error (condition)
      (list :error (format nil "~A: ~A" (type-of condition) condition)))))

(defun run-cases (input output)
  (with-open-file (source input)
    (with-open-file (destination output :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create)
      (loop for line = (read-line source nil nil) while line do
        (unless (or (zerop (length line)) (char= (char line 0) #\#))
          (let ((fields (uiop:split-string line :separator '(#\Tab))))
            (unless (= (length fields) 4)
              (error "Invalid reference case row: ~S" line))
            (destructuring-bind (id goal count baseline) fields
              (declare (ignore baseline))
              (let ((limit (parse-integer count :junk-allowed nil)))
                (unless (and (< 0 limit) (< limit 1000))
                  (error "Bad solution limit for ~A" id))
                (serialize-observation id (run-goal goal limit)
                                       destination)))))))))

(let ((args (uiop:command-line-arguments)))
  (unless (= 2 (length args))
    (error "Usage: reference-lisp.lisp CASES.tsv OBSERVATIONS.jsonl"))
  (run-cases (first args) (second args)))
