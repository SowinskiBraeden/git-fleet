# git-fleet

A Git extension for managing repositories across multiple Git hosts and destinations.

`git-fleet` is a native CLI I'm building to simplify the Git workflows I use across self-hosted Git services and public hosts. The project started as a few personal scripts for configuring dual-push repositories and is being rebuilt in OCaml as a single, reusable command.

## Status

**v0.2.0: remote management**

- `git fleet status`, `git fleet add` and `git fleet remove`
- Multiple push destinations on a single remote
- Preserves the destination a remote already pushed to
- Collapses redundant configuration back to plain Git behaviour
- `--dry-run` on every command that changes something
- Git is run directly, never through a shell

## How it works

`git-fleet` configures ordinary Git remotes. A remote fetches from one URL and may push to several, which is how a repository stays mirrored across more than one host:

```ini
[remote "origin"]
	url = git@git.example.invalid:user/project.git
	fetch = +refs/heads/*:refs/remotes/origin/*
	pushurl = git@git.example.invalid:user/project.git
	pushurl = git@github.com:user/project.git
```

A remote with no `pushurl` pushes to the URL it fetches from. As soon as it has one `pushurl`, Git pushes only to the URLs listed there, so `git fleet add` writes out the existing destination before adding a new one. Removing a destination reverses that: when the only one left is the fetch URL, the redundant configuration is dropped.

Every command works on `origin` unless `--remote` says otherwise.

## Usage

Show where a remote fetches from and pushes to:

```sh
git fleet status
git fleet status --remote upstream
```

```
origin
  fetch  git@git.example.invalid:user/project.git
  push   git@git.example.invalid:user/project.git
  push   git@github.com:user/project.git
```

Add a destination. With neither `--fetch` nor `--push`, the URL is added as a push destination. A remote that does not exist yet is created:

```sh
git fleet add git@github.com:user/project.git
git fleet add git@git.example.invalid:user/project.git --fetch
git fleet add git@git.example.invalid:user/project.git --fetch --push
git fleet add git@github.com:user/project.git --remote upstream
```

Remove a push destination. URLs are matched exactly, as they appear in `git fleet status`:

```sh
git fleet remove git@github.com:user/project.git
```

Preview the Git commands instead of running them:

```sh
git fleet add git@github.com:user/project.git --dry-run
```

```
Would change remote 'origin':
  git remote set-url --add --push origin git@git.example.invalid:user/project.git
  git remote set-url --add --push origin git@github.com:user/project.git
```

Commands exit with `1` and a single line on standard error when something is wrong, such as running outside a repository or naming a remote that does not exist.

## Installation

Build a release binary and put it on your `PATH`:

```sh
dune build --release
install -Dm755 _build/default/bin/main.exe ~/.local/bin/git-fleet
```

Git exposes any `git-*` executable on `PATH` as a subcommand, so `git-fleet` becomes:

```sh
git fleet --help
git fleet --version
```

## Development

Install the project dependencies:

```sh
opam install . --deps-only --with-test
```

Build, test and run:

```sh
dune build
dune runtest
dune exec git-fleet -- status
```

The tests create temporary repositories and never change the configuration of this one.

## License

MIT
