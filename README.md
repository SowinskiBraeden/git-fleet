# git-fleet

A Git extension for managing repositories across multiple Git hosts and destinations.

`git-fleet` is a native CLI I'm building to simplify the Git workflows I use across self-hosted Git services and public hosts. The project started as a few personal scripts for configuring dual-push repositories and is being rebuilt in OCaml as a single, reusable command.

## Status

**v0.1.0: CLI foundation**

Initial release is just figuring out the project structure and command-line interface:

- Native OCaml executable
- Dune build system
- Cmdliner command interface
- `git fleet` Git subcommand integration
- Automated tests

Remote and multi-destination management will begin in v0.2.0.

## Usage

Once `git-fleet` is installed somewhere on your `PATH`, Git automatically exposes it as a subcommand:

```sh
git fleet --help
git fleet --version
```

You can also invoke the executable directly:

```sh
git-fleet --help
```

## Development

Install the project dependencies:

```sh
opam install . --deps-only --with-test
```

Build:

```sh
dune build
```

Run the tests:

```sh
dune runtest
```

Run the development executable:

```sh
dune exec git-fleet -- --help
dune exec git-fleet -- --version
```

## License

MIT
