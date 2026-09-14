open Cmdliner

let cmd =
  let doc = "Manage Git repositories across multiple destinations." in
  Cmd.v
    (Cmd.info "git-fleet" ~version:Version.value ~doc)
    (Term.const ())
