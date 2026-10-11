open Git_fleet

let primary = "git@git.example.invalid:user/project.git"
let github = "git@github.com:user/project.git"
let backup = "git@backup.example.invalid:user/project.git"
let urls = Alcotest.(list string)

let ok = function
  | Ok value -> value
  | Error error ->
      Alcotest.failf "unexpected error: %s" (Git.string_of_error error)

let error = function
  | Ok _ -> Alcotest.fail "expected an error"
  | Error error -> error

(* Arrange repository state with Git itself, so that the assertions do not
   depend on the code under test. *)
let git_exn dir args =
  let argv = Array.of_list (("git" :: "-C" :: dir :: args)) in
  let input = Unix.openfile Filename.null [ Unix.O_RDONLY ] 0 in
  let output = Unix.openfile Filename.null [ Unix.O_WRONLY ] 0 in
  let pid = Unix.create_process "git" argv input output output in
  let _, status = Unix.waitpid [] pid in
  Unix.close input;
  Unix.close output;
  match status with
  | Unix.WEXITED 0 -> ()
  | _ -> Alcotest.failf "git %s failed" (String.concat " " args)

let rec remove_tree path =
  match Unix.lstat path with
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()
  | { st_kind = Unix.S_DIR; _ } ->
      Array.iter
        (fun entry -> remove_tree (Filename.concat path entry))
        (Sys.readdir path);
      Unix.rmdir path
  | _ -> Unix.unlink path

(* Temporary directories only: the git-fleet repository itself is never
   touched by the tests. *)
let with_dir f =
  let dir = Filename.temp_dir "git-fleet-test" "" in
  Fun.protect ~finally:(fun () -> remove_tree dir) (fun () -> f dir)

let with_repo f =
  with_dir (fun dir ->
      git_exn dir [ "init"; "-q" ];
      f dir)

let with_origin f =
  with_repo (fun cwd ->
      git_exn cwd [ "remote"; "add"; "origin"; primary ];
      f cwd)

let add ?(name = "origin") ?(fetch = false) ?(push = false) ~cwd url =
  let plan = ok (Plan.add ~cwd ~name ~fetch ~push ~url) in
  ok (Plan.execute ~cwd plan);
  plan

let remove ?(name = "origin") ~cwd url =
  let plan = ok (Plan.remove ~cwd ~name ~url) in
  ok (Plan.execute ~cwd plan);
  plan

let explicit ?(name = "origin") cwd = ok (Git.get_explicit_push_urls ~cwd ~name)
let effective ?(name = "origin") cwd = ok (Git.get_push_urls ~cwd ~name)
let fetch_urls ?(name = "origin") cwd = ok (Git.get_fetch_urls ~cwd ~name)

let test_not_a_repository () =
  with_dir (fun dir ->
      Alcotest.(check bool) "outside a work tree" false (Git.is_repository ~cwd:dir))

let test_empty_repository () =
  with_repo (fun cwd ->
      Alcotest.(check bool) "inside a work tree" true (Git.is_repository ~cwd);
      Alcotest.(check urls) "no remotes" [] (ok (Git.remotes ~cwd)))

let test_create_origin () =
  with_repo (fun cwd ->
      let plan = add ~cwd primary in
      Alcotest.(check int) "one action" 1 (List.length plan);
      Alcotest.(check urls) "remotes" [ "origin" ] (ok (Git.remotes ~cwd));
      Alcotest.(check urls) "fetch" [ primary ] (fetch_urls cwd);
      Alcotest.(check urls) "effective push" [ primary ] (effective cwd);
      Alcotest.(check urls) "no explicit push" [] (explicit cwd))

let test_custom_remote_name () =
  with_repo (fun cwd ->
      ignore (add ~cwd ~name:"upstream" primary);
      Alcotest.(check urls) "remotes" [ "upstream" ] (ok (Git.remotes ~cwd));
      Alcotest.(check urls) "fetch" [ primary ] (fetch_urls ~name:"upstream" cwd))

let test_change_fetch_url () =
  with_origin (fun cwd ->
      ignore (add ~cwd ~fetch:true backup);
      Alcotest.(check urls) "fetch" [ backup ] (fetch_urls cwd);
      Alcotest.(check urls) "no explicit push" [] (explicit cwd);
      Alcotest.(check urls) "push follows fetch" [ backup ] (effective cwd))

let test_first_push_url_preserves_implicit () =
  with_origin (fun cwd ->
      ignore (add ~cwd github);
      Alcotest.(check urls)
        "implicit destination kept first" [ primary; github ] (explicit cwd);
      Alcotest.(check urls) "effective push" [ primary; github ] (effective cwd);
      Alcotest.(check urls) "fetch unchanged" [ primary ] (fetch_urls cwd))

let test_add_second_push_url () =
  with_origin (fun cwd ->
      ignore (add ~cwd github);
      ignore (add ~cwd backup);
      Alcotest.(check urls)
        "three destinations" [ primary; github; backup ] (explicit cwd))

let test_duplicate_push_url_is_idempotent () =
  with_origin (fun cwd ->
      ignore (add ~cwd github);
      let before = explicit cwd in
      let plan = add ~cwd github in
      Alcotest.(check int) "nothing planned" 0 (List.length plan);
      Alcotest.(check urls) "configuration unchanged" before (explicit cwd))

let test_implicit_destination_is_idempotent () =
  with_origin (fun cwd ->
      let plan = add ~cwd primary in
      Alcotest.(check int) "nothing planned" 0 (List.length plan);
      Alcotest.(check urls) "still implicit" [] (explicit cwd))

let test_remove_push_url () =
  with_origin (fun cwd ->
      ignore (add ~cwd github);
      ignore (add ~cwd backup);
      ignore (remove ~cwd github);
      Alcotest.(check urls) "order preserved" [ primary; backup ] (explicit cwd);
      Alcotest.(check urls) "fetch unchanged" [ primary ] (fetch_urls cwd))

let test_remove_collapses_to_implicit () =
  with_origin (fun cwd ->
      ignore (add ~cwd github);
      ignore (remove ~cwd github);
      Alcotest.(check urls) "redundant entry removed" [] (explicit cwd);
      Alcotest.(check urls) "pushes where it fetches" [ primary ] (effective cwd))

let test_remove_unknown_url () =
  with_origin (fun cwd ->
      ignore (add ~cwd github);
      match error (Plan.remove ~cwd ~name:"origin" ~url:backup) with
      | Git.Not_a_push_destination { remote = "origin"; url } ->
          Alcotest.(check string) "reported url" backup url
      | other -> Alcotest.failf "unexpected error: %s" (Git.string_of_error other))

let test_remove_implicit_destination () =
  with_origin (fun cwd ->
      match error (Plan.remove ~cwd ~name:"origin" ~url:primary) with
      | Git.Implicit_push_destination { remote = "origin"; url } ->
          Alcotest.(check string) "reported url" primary url
      | other -> Alcotest.failf "unexpected error: %s" (Git.string_of_error other))

let test_unknown_remote () =
  with_origin (fun cwd ->
      Alcotest.(check bool)
        "remote_exists" false
        (ok (Git.remote_exists ~cwd ~name:"upstream"));
      match error (Git.remote ~cwd ~name:"upstream") with
      | Git.No_such_remote name -> Alcotest.(check string) "name" "upstream" name
      | other -> Alcotest.failf "unexpected error: %s" (Git.string_of_error other))

let test_planning_changes_nothing () =
  with_origin (fun cwd ->
      let plan = ok (Plan.add ~cwd ~name:"origin" ~fetch:false ~push:true ~url:github) in
      Alcotest.(check int) "two actions planned" 2 (List.length plan);
      Alcotest.(check urls) "no explicit push url written" [] (explicit cwd);
      Alcotest.(check urls) "fetch untouched" [ primary ] (fetch_urls cwd);
      Alcotest.(check (list string))
        "equivalent git commands"
        [
          "git remote set-url --add --push origin " ^ primary;
          "git remote set-url --add --push origin " ^ github;
        ]
        (List.map
           (fun action -> String.concat " " (Git.command_of_action action))
           plan))

let test_status_representation () =
  with_origin (fun cwd ->
      ignore (add ~cwd github);
      let remote = ok (Git.remote ~cwd ~name:"origin") in
      Alcotest.(check string)
        "rendered status"
        (String.concat "\n"
           [
             "origin";
             "  fetch  " ^ primary;
             "  push   " ^ primary;
             "  push   " ^ github;
           ])
        (Cli.render_remote remote))

(* A URL that would run a command, or lose its meaning, if git-fleet built
   shell command lines out of user input. *)
let test_hostile_url () =
  with_repo (fun cwd ->
      let marker = Filename.concat cwd "pwned" in
      let hostile =
        Printf.sprintf "ssh://git@example.invalid/a b;$(touch %s)`touch %s`.git"
          marker marker
      in
      ignore (add ~cwd primary);
      ignore (add ~cwd hostile);
      Alcotest.(check bool) "no command was executed" false (Sys.file_exists marker);
      Alcotest.(check urls) "stored verbatim" [ primary; hostile ] (explicit cwd);
      ignore (remove ~cwd hostile);
      Alcotest.(check urls) "removed exactly" [] (explicit cwd);
      Alcotest.(check urls) "fetch url intact" [ primary ] (fetch_urls cwd))

let test_version () =
  Alcotest.(check string) "version" "0.2.0" Version.value

let case name f = Alcotest.test_case name `Quick f

let () =
  (* Keep the developer's own Git configuration, such as url rewrites, out of
     the results. *)
  Unix.putenv "GIT_CONFIG_GLOBAL" Filename.null;
  Unix.putenv "GIT_CONFIG_SYSTEM" Filename.null;
  Alcotest.run "git-fleet"
    [
      ( "repository",
        [
          case "outside a repository" test_not_a_repository;
          case "empty repository" test_empty_repository;
          case "unknown remote" test_unknown_remote;
        ] );
      ( "fetch urls",
        [
          case "creates origin" test_create_origin;
          case "custom remote name" test_custom_remote_name;
          case "changes the fetch url" test_change_fetch_url;
        ] );
      ( "push destinations",
        [
          case "first push url preserves the implicit one"
            test_first_push_url_preserves_implicit;
          case "adds a second push url" test_add_second_push_url;
          case "duplicate push url is idempotent" test_duplicate_push_url_is_idempotent;
          case "implicit destination is idempotent" test_implicit_destination_is_idempotent;
          case "removes a push url" test_remove_push_url;
          case "collapses to implicit push" test_remove_collapses_to_implicit;
          case "removing an unconfigured url fails" test_remove_unknown_url;
          case "removing the implicit destination fails" test_remove_implicit_destination;
          case "urls are never interpreted by a shell" test_hostile_url;
        ] );
      ( "planning",
        [ case "planning does not touch the repository" test_planning_changes_nothing ] );
      ( "status", [ case "renders a remote" test_status_representation ] );
      ( "version", [ case "reports 0.2.0" test_version ] );
    ]
