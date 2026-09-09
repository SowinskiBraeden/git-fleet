#!/usr/bin/env python3

import re
import subprocess
from pathlib import Path

PROJECTS_DIR = Path.home() / "Projects"

OWNER = "SowinskiBraeden"
GITHUB_HOST = "github.com"
GITEA_HOST = "git.sowinski.dev"


def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        text=True,
        capture_output=True,
        check=check,
    )


def find_git_repositories(root: Path) -> list[Path]:
    """Find all Git repositories recursively below root."""
    repositories = set()

    for git_path in root.rglob(".git"):
        if git_path.is_dir() or git_path.is_file():
            repositories.add(git_path.parent)

    return sorted(repositories)


def parse_repo_name(url: str) -> str | None:
    """
    Extract the repository name if the URL belongs to OWNER on either
    GitHub or our Gitea instance.

    Supported examples:

      git@github.com:SowinskiBraeden/example.git
      https://github.com/SowinskiBraeden/example.git

      git@git.sowinski.dev:SowinskiBraeden/example.git
      https://git.sowinski.dev/SowinskiBraeden/example.git
    """

    hosts = [
        re.escape(GITHUB_HOST),
        re.escape(GITEA_HOST),
    ]

    host_pattern = "(?:" + "|".join(hosts) + ")"

    patterns = [
        rf"^git@{host_pattern}:{re.escape(OWNER)}/([^/]+?)(?:\.git)?$",
        rf"^https?://{host_pattern}/{re.escape(OWNER)}/([^/]+?)(?:\.git)?/?$",
        rf"^ssh://git@{host_pattern}/{re.escape(OWNER)}/([^/]+?)(?:\.git)?/?$",
    ]

    for pattern in patterns:
        match = re.match(pattern, url)

        if match:
            return match.group(1)

    return None


def get_origin(repo: Path) -> str | None:
    result = git(
        repo,
        "remote",
        "get-url",
        "origin",
        check=False,
    )

    if result.returncode != 0:
        return None

    return result.stdout.strip()


def configure_repository(repo: Path) -> bool:
    origin = get_origin(repo)

    if origin is None:
        print(f"SKIP   {repo}")
        print("       No origin remote")
        return False

    repo_name = parse_repo_name(origin)

    if repo_name is None:
        print(f"SKIP   {repo}")
        print(f"       Unrecognized/non-{OWNER} origin:")
        print(f"       {origin}")
        return False

    gitea_url = f"git@{GITEA_HOST}:{OWNER}/{repo_name}.git"
    github_url = f"git@{GITHUB_HOST}:{OWNER}/{repo_name}.git"

    print(f"UPDATE {repo}")
    print(f"       Repository: {OWNER}/{repo_name}")

    #
    # FETCH
    #
    # Gitea is authoritative.
    #
    git(
        repo,
        "remote",
        "set-url",
        "origin",
        gitea_url,
    )

    print(f"       fetch -> {gitea_url}")

    #
    # PUSH
    #
    # Reset the push URL list so running this utility repeatedly cannot
    # create duplicate push destinations.
    #
    current_push_urls = git(
        repo,
        "remote",
        "get-url",
        "--all",
        "--push",
        "origin",
    ).stdout.splitlines()

    # Delete existing explicit push URLs.
    #
    # Git returns an error if there are no explicit push URLs matching,
    # which is harmless here.
    for push_url in current_push_urls:
        git(
            repo,
            "remote",
            "set-url",
            "--delete",
            "--push",
            "origin",
            re.escape(push_url),
            check=False,
        )

    # Establish Gitea as the primary push destination.
    git(
        repo,
        "remote",
        "set-url",
        "--push",
        "origin",
        gitea_url,
    )

    # GitHub remains the public/legacy destination.
    git(
        repo,
        "remote",
        "set-url",
        "--add",
        "--push",
        "origin",
        github_url,
    )

    print(f"       push  -> {gitea_url}")
    print(f"       push  -> {github_url}")
    print()

    return True


def main():
    if not PROJECTS_DIR.exists():
        raise SystemExit(
            f"Projects directory does not exist: {PROJECTS_DIR}"
        )

    repositories = find_git_repositories(PROJECTS_DIR)

    print(f"Searching: {PROJECTS_DIR}")
    print(f"Found {len(repositories)} Git repositories.")
    print()

    configured = 0
    skipped = 0

    for repo in repositories:
        if configure_repository(repo):
            configured += 1
        else:
            skipped += 1

    print("=" * 60)
    print("Finished")
    print(f"Configured: {configured}")
    print(f"Skipped:    {skipped}")
    print(f"Total:      {len(repositories)}")


if __name__ == "__main__":
    main()
