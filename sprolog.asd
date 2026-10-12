(asdf:defsystem "sprolog"
  :class :package-inferred-system
  :description "Stack-safe S-expression Prolog with a WAM-derived register VM"
  :version "0.9.1"
  :license "MIT"
  :depends-on ("uiop" "sprolog/src/prolog-loader")
  :in-order-to ((asdf:test-op (asdf:test-op "sprolog/tests"))))

;; Experimental ISO interpreter, layered on the original S-expression VM.
(asdf:defsystem "sprolog/iso"
  :depends-on ("sprolog" "sprolog/src/iso"))
(asdf:register-system-packages "sprolog/src/iso" '("SPROLOG/ISO"))

;; The inferred module packages declare dependencies while implementation
;; definitions share SPROLOG. Map its public nickname to the defining module.
;; ASDF extension for (:prolog "name") components in consumer systems.
(asdf:defsystem "sprolog/asdf"
  :depends-on ("sprolog")
  :components ((:file "asdf-support")))

(asdf:register-system-packages "sprolog/src/package" '("SPROLOG"))
(asdf:register-system-packages "sprolog/src/builtins" '("SPROLOG/ATOMS"))
(asdf:register-system-packages "sprolog/tests/tests" '("SPROLOG/TESTS"))

(asdf:defsystem "sprolog/tests"
  :depends-on ("sprolog/asdf" "sprolog/tests/prolog-loader")
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :sprolog/tests :run-tests)))
