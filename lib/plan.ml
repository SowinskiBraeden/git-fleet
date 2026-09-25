type t = Git.action list

let ( let* ) = Result.bind

(* Plan whatever is needed for [url] to become one of the remote's effective
   push destinations, leaving the existing destinations in place.

   Git stops using the fetch URL as soon as a remote has an explicit pushurl,
   so the implicit destination has to be written out before the first explicit
   one is added. *)
let ensure_push_destination ~name ~explicit ~effective ~url =
  let add url = Git.Add_push_url { name; url } in
  if List.mem url explicit then []
  else if explicit <> [] then [ add url ]
  else if effective = [ url ] then []
  else List.map add effective @ [ add url ]

let add ~cwd ~name ~fetch ~push ~url =
  (* With neither flag the URL is a push destination. *)
  let want_fetch = fetch and want_push = push || not fetch in
  let* exists = Git.remote_exists ~cwd ~name in
  if not exists then
    (* A new remote fetches and, implicitly, pushes to its only URL. *)
    Ok [ Git.Add_remote { name; url } ]
  else
    let* remote = Git.remote ~cwd ~name in
    let fetch_actions =
      if want_fetch && remote.fetch_urls <> [ url ] then
        [ Git.Set_fetch_url { name; url } ]
      else []
    in
    let push_actions =
      if not want_push then []
      else
        (* A changed fetch URL also moves the implicit push destination. *)
        let effective =
          if fetch_actions <> [] && remote.explicit_push_urls = [] then [ url ]
          else remote.push_urls
        in
        ensure_push_destination ~name ~explicit:remote.explicit_push_urls
          ~effective ~url
    in
    Ok (fetch_actions @ push_actions)

let remove ~cwd ~name ~url =
  let* remote = Git.remote ~cwd ~name in
  if not (List.mem url remote.explicit_push_urls) then
    if remote.explicit_push_urls = [] && List.mem url remote.push_urls then
      Error (Git.Implicit_push_destination { remote = name; url })
    else Error (Git.Not_a_push_destination { remote = name; url })
  else
    let remaining =
      List.filter (fun existing -> existing <> url) remote.explicit_push_urls
    in
    let clear = Git.Clear_push_urls { name } in
    (* Dropping every explicit entry, or keeping only the fetch URL, restores
       Git's implicit push behaviour. *)
    if remaining = [] || remaining = remote.fetch_urls then Ok [ clear ]
    else
      Ok (clear :: List.map (fun url -> Git.Add_push_url { name; url }) remaining)

let execute ~cwd plan =
  List.fold_left
    (fun result action ->
      let* () = result in
      Git.apply ~cwd action)
    (Ok ()) plan
