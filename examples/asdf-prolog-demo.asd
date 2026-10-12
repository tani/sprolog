(asdf:defsystem "asdf-prolog-demo"
  :defsystem-depends-on ("sprolog/asdf")
  :depends-on ("sprolog")
  :components ((:prolog "relations" :package "CL-USER")))
