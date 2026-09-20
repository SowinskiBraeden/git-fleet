type error =
  | Git_unavailable of string
  | Not_a_repository of string
  | No_such_remote of string
  | Not_a_push_destination of { remote : string; url : string }
  | Implicit_push_destination of { remote : string; url : string }
  | Command_failed of { args : string list; status : int; stderr : string }

type remote = {
  name : string;
  fetch_urls : string list;
  push_urls : string list;
  explicit_push_urls : string list;
}

type action =
  | Add_remote of { name : string; url : string }
  | Set_fetch_url of { name : string; url : string }
  | Add_push_url of { name : string; url : string }
  | Clear_push_urls of { name : string }

let executable = "git"

(* Read every pipe to end of file without blocking on one while the other
   fills up. *)
let drain fds =
  let buffers = List.map (fun fd -> (fd, Buffer.create 1024)) fds in
  let chunk = Bytes.create 65536 in
  let rec loop open_fds =
    if open_fds <> [] then begin
      let ready =
        try
          let ready, _, _ = Unix.select open_fds [] [] (-1.0) in
          ready
        with Unix.Unix_error (Unix.EINTR, _, _) -> []
      in
      let finished =
        List.filter
          (fun fd ->
            match Unix.read fd chunk 0 (Bytes.length chunk) with
            | 0 -> true
            | n ->
                Buffer.add_subbytes (List.assq fd buffers) chunk 0 n;
                false
            | exception Unix.Unix_error (Unix.EINTR, _, _) -> false)
          ready
      in
      loop (List.filter (fun fd -> not (List.memq fd finished)) open_fds)
    end
  in
  loop fds;
  List.map (fun (_, buffer) -> Buffer.contents buffer) buffers

type output = { status : int; stdout : string; stderr : string }

(* Run [git] with [args] as distinct argv entries. No shell is involved. *)
let exec args =
  let out_read, out_write = Unix.pipe ~cloexec:true () in
  let err_read, err_write = Unix.pipe ~cloexec:true () in
  let close_all () =
    List.iter
      (fun fd -> try Unix.close fd with Unix.Unix_error _ -> ())
      [ out_read; out_write; err_read; err_write ]
  in
  match
    let devnull = Unix.openfile Filename.null [ Unix.O_RDONLY ] 0 in
    Fun.protect
      ~finally:(fun () -> Unix.close devnull)
      (fun () ->
        Unix.create_process executable
          (Array.of_list (executable :: args))
          devnull out_write err_write)
  with
  | exception Unix.Unix_error (code, _, _) ->
      close_all ();
      Error (Git_unavailable (Unix.error_message code))
  | pid ->
      Unix.close out_write;
      Unix.close err_write;
      let stdout, stderr =
        match drain [ out_read; err_read ] with
        | [ stdout; stderr ] -> (stdout, stderr)
        | _ -> ("", "")
      in
      Unix.close out_read;
      Unix.close err_read;
      let status =
        match snd (Unix.waitpid [] pid) with
        | Unix.WEXITED code -> code
        | Unix.WSIGNALED signal | Unix.WSTOPPED signal -> 128 + signal
      in
      Ok { status; stdout; stderr }

let failed args { status; stderr; _ } =
  Command_failed { args; status; stderr = String.trim stderr }

let in_repo ~cwd args = exec ("-C" :: cwd :: args)

(* Run a command that is expected to succeed, returning its standard output. *)
let output ~cwd args =
  match in_repo ~cwd args with
  | Error _ as error -> error
  | Ok ({ status = 0; stdout; _ } : output) -> Ok stdout
  | Ok result -> Error (failed args result)

let lines text =
  String.split_on_char '\n' text
  |> List.map String.trim
  |> List.filter (fun line -> line <> "")

let unit_of_output result = Result.map (fun (_ : string) -> ()) result

let is_repository ~cwd =
  match in_repo ~cwd [ "rev-parse"; "--is-inside-work-tree" ] with
  | Ok { status = 0; stdout; _ } -> String.trim stdout = "true"
  | Ok _ | Error _ -> false

let remotes ~cwd = Result.map lines (output ~cwd [ "remote" ])

let remote_exists ~cwd ~name =
  Result.map (fun names -> List.mem name names) (remotes ~cwd)

(* [git remote get-url] fails when the remote is unknown; report that as a
   first class error rather than a raw command failure. *)
let get_urls ~cwd ~name args =
  match in_repo ~cwd args with
  | Error _ as error -> error
  | Ok ({ status = 0; stdout; _ } : output) -> Ok (lines stdout)
  | Ok result -> (
      match remote_exists ~cwd ~name with
      | Ok false -> Error (No_such_remote name)
      | Ok true -> Error (failed args result)
      | Error _ as error -> error)

let get_fetch_urls ~cwd ~name =
  get_urls ~cwd ~name [ "remote"; "get-url"; "--all"; name ]

let get_push_urls ~cwd ~name =
  get_urls ~cwd ~name [ "remote"; "get-url"; "--push"; "--all"; name ]

let get_explicit_push_urls ~cwd ~name =
  let key = "remote." ^ name ^ ".pushurl" in
  let args = [ "config"; "--get-all"; key ] in
  match in_repo ~cwd args with
  | Error _ as error -> error
  | Ok ({ status = 0; stdout; _ } : output) -> Ok (lines stdout)
  (* Exit status 1 means the key is simply not set. *)
  | Ok { status = 1; _ } -> Ok []
  | Ok result -> Error (failed args result)

let ( let* ) = Result.bind

let remote ~cwd ~name =
  let* fetch_urls = get_fetch_urls ~cwd ~name in
  let* push_urls = get_push_urls ~cwd ~name in
  let* explicit_push_urls = get_explicit_push_urls ~cwd ~name in
  Ok { name; fetch_urls; push_urls; explicit_push_urls }

let command_of_action = function
  | Add_remote { name; url } -> [ "git"; "remote"; "add"; name; url ]
  | Set_fetch_url { name; url } -> [ "git"; "remote"; "set-url"; name; url ]
  | Add_push_url { name; url } ->
      [ "git"; "remote"; "set-url"; "--add"; "--push"; name; url ]
  | Clear_push_urls { name } ->
      [ "git"; "config"; "--unset-all"; "remote." ^ name ^ ".pushurl" ]

let apply ~cwd action =
  let args = List.tl (command_of_action action) in
  match action with
  | Clear_push_urls _ -> (
      match in_repo ~cwd args with
      | Error _ as error -> error
      (* Status 5 means there was nothing to unset. *)
      | Ok ({ status = 0 | 5; _ } : output) -> Ok ()
      | Ok result -> Error (failed args result))
  | Add_remote _ | Set_fetch_url _ | Add_push_url _ ->
      unit_of_output (output ~cwd args)

let string_of_error = function
  | Git_unavailable reason -> "could not run git: " ^ reason
  | Not_a_repository cwd -> "not a Git repository: " ^ cwd
  | No_such_remote name -> "no such remote: " ^ name
  | Not_a_push_destination { remote; url } ->
      Printf.sprintf "%s is not a push destination of remote '%s'" url remote
  | Implicit_push_destination { remote; url } ->
      Printf.sprintf
        "%s is the implicit push destination of remote '%s' and follows its \
         fetch URL; change the fetch URL instead"
        url remote
  | Command_failed { args; status; stderr } ->
      let command = String.concat " " ("git" :: args) in
      if stderr = "" then
        Printf.sprintf "%s exited with status %d" command status
      else Printf.sprintf "%s: %s" command stderr
