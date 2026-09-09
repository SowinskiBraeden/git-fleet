#!/usr/bin/env python3

import re
import subprocess
from pathlib import Path

PROJECTS_DIR = Path.home() / "Projects"
GITHUB_USER = "SowinskiBraeden"
GITEA_HOST = "git.sowinski.dev"


def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        text=True,
        capture_output=True,
        check=check,
    )


def find_git_repositories(root: Path):
    """
    Find repositories recursively under ~/Projects.

    Once a .git directory/file is found, don't recurse further into that
    repository looking for nested repositories.
    """
    repositories = []

    for path in root.rglob(".git"):
        if path.is_dir() or path.is_file():
            repositories.append(path.parent)

    return sorted(set(repositories))


def github_repo_name(origin: str):
    """
    Recognize origins such as:

      git@github.com:SowinskiBraeden/example.git
      https://github.com/SowinskiBraeden/example.git
      ssh://git@github.com/SowinskiBraeden/example.git

    Returns "example" or None.
    """

    patterns = [
        rf"^git@github\.com:{re.escape(GITHUB_USER)}/([^/]+?)(?:\.git)?$",
        rf"^https?://github\.com/{re.escape(GITHUB_USER)}/([^/]+?)(?:\.git)?/?$",
        rf"^ssh://git@github\.com/{re.escape(GITHUB_USER)}/([^/]+?)(?:\.git)?/?$",
    ]

    for pattern in patterns:
        match = re.match(pattern, origin)

        if match:
            return match.group(1)

    return None


def configure_repository(repo: Path):
    result = git(repo, "remote", "get-url", "origin", check=False)

    if result.returncode != 0:
        print(f"SKIP   {repo}")
        print("       No origin remote")
        return

    origin = result.stdout.strip()
    repo_name = github_repo_name(origin)

    if not repo_name:
        print(f"SKIP   {repo}")
        print(f"       Origin is not {GITHUB_USER}'s GitHub: {origin}")
        return

    github_url = f"git@github.com:{GITHUB_USER}/{repo_name}.git"
    gitea_url = f"git@{GITEA_HOST}:{GITHUB_USER}/{repo_name}.git"

    existing_push_urls = git(
        repo,
        "remote",
        "get-url",
        "--all",
        "--push",
        "origin",
    ).stdout.splitlines()

    print(f"FOUND  {repo}")
    print(f"       Repository: {GITHUB_USER}/{repo_name}")

    # Explicitly establish GitHub as the first push destination.
    #
    # If no separate pushurl exists yet, this creates one without changing
    # the fetch URL.
    if github_url not in existing_push_urls:
        git(repo, "remote", "set-url", "--push", "origin", github_url)
        print(f"       + push -> {github_url}")
    else:
        print("       = GitHub push already configured")

    # Re-read because set-url --push may have replaced the implicit
    # origin push URL.
    existing_push_urls = git(
        repo,
        "remote",
        "get-url",
        "--all",
        "--push",
        "origin",
    ).stdout.splitlines()

    if gitea_url not in existing_push_urls:
        git(
            repo,
            "remote",
            "set-url",
            "--add",
            "--push",
            "origin",
            gitea_url,
        )
        print(f"       + push -> {gitea_url}")
    else:
        print("       = Gitea push already configured")

    print()


def main():
    if not PROJECTS_DIR.exists():
        raise SystemExit(f"Projects directory does not exist: {PROJECTS_DIR}")

    repositories = find_git_repositories(PROJECTS_DIR)

    print(f"Searching {PROJECTS_DIR}")
    print(f"Found {len(repositories)} Git repositories.\n")

    for repo in repositories:
        configure_repository(repo)

    print("Done.")


if __name__ == "__main__":
    main()
