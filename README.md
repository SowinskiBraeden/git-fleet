# git-fleet

Small collection of Git utilities I use to keep my local repositories configured between my self-hosted Gitea instance and GitHub.

Gitea is my primary Git server. GitHub is kept as a secondary/public copy of my repositories.

## `setup_dual_push.py`

Scans my local Git repositories and updates repos owned by `SowinskiBraeden` to use:

- **Fetch:** `git.sowinski.dev`
- **Push:** `git.sowinski.dev`
- **Push:** `github.com`

Other repositories and repositories without a recognized origin are skipped.

Useful for configuring existing projects or setting up a new machine.

## `git-new`

Small command for initializing new projects with my normal Git configuration.

Run it from inside the project directory:

```bash
git-new <repo-name>
```

It will:

Refuse to run if the directory is already inside a Git repository
Initialize a new Git repository
Set the default branch to main
Set Gitea as the fetch origin
Set Gitea and GitHub as push origins

The repo name does not need to match the local directory name.

## Setup

Make the script executable:

```bash
chmod +x git-new
```

Symlink it into /usr/local/bin:

```bash
sudo ln -s "$(pwd)/git-new" /usr/local/bin/git-new
```

It can then be used from any directory:

```bash
mkdir my-project
cd my-project

git-new my-repo-name
```

The repositories must already exist on Gitea and GitHub before pushing.

