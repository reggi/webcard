# Agent workflow

Use this branch and pull request lifecycle for every task:

1. Fetch `origin` and create a feature branch and worktree from `origin/main`.
2. Complete the requested work and commit it on the feature branch.
3. Decide whether human verification is required.
4. If human verification is required, build the application with `./scripts/reinstall-app.sh`, ask the human to test it, and stop until explicit approval is received.
5. If human verification is not required, continue without requesting testing or running the reinstall command as a finalization step.
6. Push the feature branch to `origin`.
7. Open a pull request targeting `main`.
8. Report the pull request and leave it for review and merging.
9. After the pull request is confirmed merged, remove the feature worktree and delete the local feature branch with `git branch -d`.

Do not merge a feature branch into `main` locally, push directly to `main`, merge a pull request unless explicitly requested, deploy, run additional post-merge installation tests, list all worktrees as a finalization step, or use force deletion.

## Human verification builds

The reinstall command tests, rebuilds, installs, and opens the new build. The `main` worktree replaces `/Applications/Webcard.app`. Every other worktree automatically installs an isolated app under `~/Applications/Webcard Worktrees/<worktree>/Webcard.app` with its own name, bundle identifier, and visibly badged app icon. Do not run a separate installation while this command is active.

The command uses a machine-wide per-user lock for each destination. Different worktrees can build and install concurrently. If another agent owns the same destination lock, the command exits with owner, process, start time, repository, and destination details. Wait for that agent to finish rather than bypassing or deleting an active lock.

Set `WEBCARD_INSTALL_OWNER` to a recognizable agent or task name when available. Set `WEBCARD_INSTALL_PATH` only when intentionally overriding the worktree's default destination. Set `WEBCARD_INSTALL_VARIANT` to create an isolated named variant from the `main` worktree.
