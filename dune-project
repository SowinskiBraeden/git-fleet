(lang dune 3.16)

(name git-fleet)
(version 0.1.0)

(generate_opam_files true)

(source
 (github SowinskiBraeden/git-fleet))

(authors "Braeden Sowinski")
(maintainers "Braeden Sowinski <braeden@sowinski.dev>")

(license MIT)

(package
 (name git-fleet)
 (synopsis "Manage Git repositories across multiple destinations")
 (description
  "git-fleet is a Git extension for managing repositories across multiple Git hosts and push destinations.")
 (depends
  (ocaml (>= 5.1))
  (dune (>= 3.16))
  (cmdliner (>= 1.3.0))
  (alcotest :with-test))
 (tags
  ("git" "cli" "developer-tools")))
