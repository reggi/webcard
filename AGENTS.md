# Agent workflow

Use this local worktree lifecycle for every task:

1. Create a feature branch and worktree from `main`.
2. Complete the requested work and commit it locally.
3. Decide whether human verification is required.
4. If human verification is required, build the application with `./scripts/reinstall-app.sh`, ask the human to test it, and stop until explicit approval is received.
5. If human verification is not required, continue without requesting testing or running the reinstall command as a finalization step.
6. Check whether the `main` worktree has uncommitted changes.
7. If `main` is dirty, report the changed files and stop until the human confirms it is ready. Do not stash, discard, or commit those changes.
8. After approval, check `main` again and continue only if it is clean.
9. Merge the feature branch into `main` locally.
10. If the merge fails or conflicts, stop and report the problem.
11. After a successful merge, change to the `main` worktree, remove the feature worktree, and delete the local feature branch with `git branch -d`.

Do not push, open a pull request, deploy, interact with GitHub, run additional post-merge installation tests, list all worktrees as a finalization step, use force deletion, or leave the completed worktree and branch behind.

## Human verification builds

The reinstall command tests, rebuilds, installs, and opens the new build. The `main` worktree replaces `/Applications/Webcard.app`. Every other worktree automatically installs an isolated app under `~/Applications/Webcard Worktrees/<worktree>/Webcard.app` with its own name, bundle identifier, and visibly badged app icon. Do not run a separate installation while this command is active.

The command uses a machine-wide per-user lock for each destination. Different worktrees can build and install concurrently. If another agent owns the same destination lock, the command exits with owner, process, start time, repository, and destination details. Wait for that agent to finish rather than bypassing or deleting an active lock.

Set `WEBCARD_INSTALL_OWNER` to a recognizable agent or task name when available. Set `WEBCARD_INSTALL_PATH` only when intentionally overriding the worktree's default destination. Set `WEBCARD_INSTALL_VARIANT` to create an isolated named variant from the `main` worktree.
