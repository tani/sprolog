(asdf:defsystem "sprolog-fixture"
  :defsystem-depends-on ("sprolog/asdf")
  :depends-on ("sprolog")
  :serial t
  :components ((:prolog "fixtures/relations" :package "CL-USER")))
