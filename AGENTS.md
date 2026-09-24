# Agent workflow

After changing Webcard, run:

```sh
./scripts/reinstall-app.sh
```

This is the single finalization command. It tests, rebuilds, installs, and opens the new build. The `main` worktree replaces `/Applications/Webcard.app`. Every other worktree automatically installs an isolated app under `~/Applications/Webcard Worktrees/<worktree>/Webcard.app` with its own name and bundle identifier. Do not run a separate installation while this command is active.

The command uses a machine-wide per-user lock for each destination. Different worktrees can build and install concurrently. If another agent owns the same destination lock, the command exits with owner, process, start time, repository, and destination details. Wait for that agent to finish rather than bypassing or deleting an active lock.

Set `WEBCARD_INSTALL_OWNER` to a recognizable agent or task name when available. Set `WEBCARD_INSTALL_PATH` only when intentionally overriding the worktree's default destination. Set `WEBCARD_INSTALL_VARIANT` to create an isolated named variant from the `main` worktree.
