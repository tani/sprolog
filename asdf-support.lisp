;; Loaded by (asdf:defsystem ... :defsystem-depends-on ("sprolog/asdf")).
;; Define the component type in ASDF's namespace so (:prolog "name") works.
(in-package #:asdf)

(defclass prolog (source-file)
  ((type :initform "pl")
   (package :initarg :package :initform "CL-USER" :reader prolog-source-package)))

(defmethod input-files ((op compile-op) (component prolog))
  (declare (ignore op))
  (list (component-pathname component)))

(defmethod input-files ((op load-op) (component prolog))
  (declare (ignore op))
  (list (component-pathname component)))

(defmethod input-files ((op load-source-op) (component prolog))
  (declare (ignore op))
  (list (component-pathname component)))

;; .pl clauses compile to the sprolog database at load-time, not to a Lisp
;; FASL. Compile-op validates source without modifying global predicate state.
(defmethod perform ((op compile-op) (component prolog))
  (declare (ignore op))
  (sprolog:read-prolog (component-pathname component)
                       :package (prolog-source-package component)))

(defmethod perform ((op load-op) (component prolog))
  (declare (ignore op))
  (sprolog:load-prolog (component-pathname component)
                       :package (prolog-source-package component)))

(defmethod perform ((op load-source-op) (component prolog))
  (declare (ignore op))
  (sprolog:load-prolog (component-pathname component)
                       :package (prolog-source-package component)))
