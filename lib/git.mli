(** Execution of [git] subprocesses and inspection of repository remotes.

    Every operation runs the [git] executable directly. User supplied values,
    such as URLs, are always passed as separate arguments and are never
    interpolated into a shell command line. *)

(** Failures that are expected during normal use of the command line. *)
type error =
  | Git_unavailable of string
      (** The [git] executable could not be started. *)
  | Not_a_repository of string  (** The directory is not a Git work tree. *)
  | No_such_remote of string  (** The repository has no such remote. *)
  | Not_a_push_destination of { remote : string; url : string }
      (** The URL is not configured as a push destination of the remote. *)
  | Implicit_push_destination of { remote : string; url : string }
      (** The URL is the remote's implicit push destination, which follows its
          fetch URL and so cannot be removed on its own. *)
  | Command_failed of { args : string list; status : int; stderr : string }
      (** A [git] command exited with a non-zero status. *)

val string_of_error : error -> string
(** A concise single line description, without a trailing newline. *)

(** A Git remote.

    [push_urls] are the destinations Git actually pushes to. When a remote has
    no [remote.<name>.pushurl] entries, Git pushes to the fetch URL, so
    [explicit_push_urls] is empty while [push_urls] is not. *)
type remote = {
  name : string;
  fetch_urls : string list;
  push_urls : string list;
  explicit_push_urls : string list;
}

val is_repository : cwd:string -> bool
(** Whether [cwd] is inside a Git work tree. *)

val remotes : cwd:string -> (string list, error) result
(** The names of every configured remote, in Git's order. *)

val remote_exists : cwd:string -> name:string -> (bool, error) result
val get_fetch_urls : cwd:string -> name:string -> (string list, error) result

val get_push_urls : cwd:string -> name:string -> (string list, error) result
(** The effective push destinations, including the implicit one. *)

val get_explicit_push_urls :
  cwd:string -> name:string -> (string list, error) result
(** The [remote.<name>.pushurl] entries, in configuration order. *)

val remote : cwd:string -> name:string -> (remote, error) result

(** A single change to a repository's configuration. *)
type action =
  | Add_remote of { name : string; url : string }
  | Set_fetch_url of { name : string; url : string }
  | Add_push_url of { name : string; url : string }
  | Clear_push_urls of { name : string }

val command_of_action : action -> string list
(** The equivalent Git command line, as an argument list starting with ["git"]. *)

val apply : cwd:string -> action -> (unit, error) result
