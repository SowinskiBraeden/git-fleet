(** Working out which Git actions a request needs.

    Planning is separated from execution so that a dry run and a real run
    describe exactly the same changes. A plan is applied in order; an empty
    plan means the repository is already in the requested state. *)

type t = Git.action list

val add :
  cwd:string ->
  name:string ->
  fetch:bool ->
  push:bool ->
  url:string ->
  (t, Git.error) result
(** [add ~cwd ~name ~fetch ~push ~url] plans the addition of [url] to remote
    [name] as a fetch URL, a push destination, or both.

    The remote is created when it does not exist yet. When the first explicit
    push destination is added, the remote's current implicit destination is
    recorded first, so that Git keeps pushing where it already pushed. Adding
    a destination that is already in use plans nothing. *)

val remove : cwd:string -> name:string -> url:string -> (t, Git.error) result
(** [remove ~cwd ~name ~url] plans the removal of the push destination [url]
    from remote [name]. URLs are matched exactly.

    When the only remaining explicit destination is the remote's fetch URL,
    the redundant entries are dropped so that the remote returns to Git's
    implicit push behaviour. *)

val execute : cwd:string -> t -> (unit, Git.error) result
(** Apply every action in order, stopping at the first failure. *)
