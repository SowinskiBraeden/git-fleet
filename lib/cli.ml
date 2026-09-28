open Cmdliner

let exit_error = 1

let fail message =
  prerr_endline ("git-fleet: " ^ message);
  exit_error

let report = function Ok () -> 0 | Error error -> fail (Git.string_of_error error)

let ( let* ) = Result.bind

let repository () =
  let cwd = Sys.getcwd () in
  if Git.is_repository ~cwd then Ok cwd else Error (Git.Not_a_repository cwd)

(* Only quote arguments that would otherwise be misread when pasted into a
   shell, so that ordinary Git URLs stay readable. *)
let shell_safe = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '@' | ':' | '/' | '.' | '_' | '-'
  | '+' | '~' | '=' ->
      true
  | _ -> false

let quote argument =
  if argument <> "" && String.for_all shell_safe argument then argument
  else Filename.quote argument

let print_action action =
  print_endline
    ("  " ^ String.concat " " (List.map quote (Git.command_of_action action)))

let render_remote (remote : Git.remote) =
  let line label url = Printf.sprintf "  %-5s  %s" label url in
  String.concat "\n"
    ((remote.name :: List.map (line "fetch") remote.fetch_urls)
    @ List.map (line "push") remote.push_urls)

let print_remote remote = print_endline (render_remote remote)

let show_remote ~cwd ~name =
  let* remote = Git.remote ~cwd ~name in
  print_remote remote;
  Ok ()

let run_plan ~cwd ~name ~dry_run ~unchanged plan =
  if plan = [] then (
    print_endline unchanged;
    Ok ())
  else if dry_run then (
    Printf.printf "Would change remote '%s':\n" name;
    List.iter print_action plan;
    Ok ())
  else
    let* () = Plan.execute ~cwd plan in
    show_remote ~cwd ~name

let remote_arg =
  let doc = "The Git remote to operate on." in
  Arg.(value & opt string "origin" & info [ "remote" ] ~docv:"REMOTE" ~doc)

let dry_run_arg =
  let doc = "Report the Git commands that would run, changing nothing." in
  Arg.(value & flag & info [ "dry-run" ] ~doc)

let url_arg ~doc = Arg.(required & pos 0 (some string) None & info [] ~docv:"URL" ~doc)

let status_term =
  let run name =
    report
      (let* cwd = repository () in
       show_remote ~cwd ~name)
  in
  Term.(const run $ remote_arg)

let status_cmd =
  let doc = "Show the destinations of a remote." in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Print the fetch URL and every push destination of a remote. A remote \
         with no explicit push destination pushes to its fetch URL, and that \
         destination is shown as well.";
      `S Manpage.s_examples;
      `Pre "git fleet status";
      `Pre "git fleet status --remote upstream";
    ]
  in
  Cmd.v (Cmd.info "status" ~doc ~man) status_term

let add_term =
  let fetch_arg =
    let doc = "Use $(i,URL) as the fetch URL of the remote." in
    Arg.(value & flag & info [ "fetch" ] ~doc)
  in
  let push_arg =
    let doc = "Add $(i,URL) as a push destination of the remote." in
    Arg.(value & flag & info [ "push" ] ~doc)
  in
  let run name fetch push dry_run url =
    report
      (let* cwd = repository () in
       let* plan = Plan.add ~cwd ~name ~fetch ~push ~url in
       let unchanged =
         Printf.sprintf "Remote '%s' already uses %s; nothing to change." name
           url
       in
       run_plan ~cwd ~name ~dry_run ~unchanged plan)
  in
  Term.(
    const run $ remote_arg $ fetch_arg $ push_arg $ dry_run_arg
    $ url_arg ~doc:"The Git URL to add.")

let add_cmd =
  let doc = "Add a destination to a remote." in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Add a Git URL to a remote. With neither $(b,--fetch) nor $(b,--push) \
         the URL becomes a push destination.";
      `P
        "A remote that does not exist yet is created with $(i,URL) as its \
         fetch URL. When a remote gains its first explicit push destination, \
         the destination it already pushed to is kept, so that pushing \
         continues to reach it.";
      `S Manpage.s_examples;
      `Pre "git fleet add git@github.com:user/project.git";
      `Pre "git fleet add git@git.example.invalid:user/project.git --fetch --push";
      `Pre "git fleet add git@github.com:user/project.git --remote upstream";
      `Pre "git fleet add git@github.com:user/project.git --dry-run";
    ]
  in
  Cmd.v (Cmd.info "add" ~doc ~man) add_term

let remove_term =
  let run name dry_run url =
    report
      (let* cwd = repository () in
       let* plan = Plan.remove ~cwd ~name ~url in
       let unchanged =
         Printf.sprintf "Remote '%s' does not push to %s; nothing to change."
           name url
       in
       run_plan ~cwd ~name ~dry_run ~unchanged plan)
  in
  Term.(
    const run $ remote_arg $ dry_run_arg
    $ url_arg ~doc:"The push destination to remove.")

let remove_cmd =
  let doc = "Remove a push destination from a remote." in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Remove a push destination from a remote. The URL is matched exactly, \
         as it appears in $(b,git fleet status).";
      `P
        "When the only destination left is the remote's fetch URL, the \
         redundant configuration is removed and the remote returns to Git's \
         usual behaviour of pushing to where it fetches from.";
      `S Manpage.s_examples;
      `Pre "git fleet remove git@github.com:user/project.git";
      `Pre "git fleet remove git@github.com:user/project.git --remote upstream";
      `Pre "git fleet remove git@github.com:user/project.git --dry-run";
    ]
  in
  Cmd.v (Cmd.info "remove" ~doc ~man) remove_term

let cmd =
  let doc = "Manage Git repositories across multiple destinations." in
  let man =
    [
      `S Manpage.s_description;
      `P
        "git-fleet manages the destinations of ordinary Git remotes. A remote \
         fetches from one URL and may push to several, which keeps a \
         repository mirrored across more than one Git host.";
      `P
        "Installed on $(b,PATH), git-fleet is available as $(b,git fleet). \
         Commands act on the remote $(b,origin) unless $(b,--remote) says \
         otherwise.";
      `S Manpage.s_examples;
      `Pre "git fleet status";
      `Pre "git fleet add git@github.com:user/project.git";
      `Pre "git fleet remove git@github.com:user/project.git";
    ]
  in
  let exits =
    Cmd.Exit.info exit_error ~doc:"on a git-fleet error, such as an unknown remote."
    :: Cmd.Exit.defaults
  in
  let info = Cmd.info "git-fleet" ~version:Version.value ~doc ~man ~exits in
  let default = Term.ret (Term.const (`Help (`Pager, None))) in
  Cmd.group info ~default [ status_cmd; add_cmd; remove_cmd ]
