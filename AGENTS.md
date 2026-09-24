# Agent workflow

After changing Webcard, run:

```sh
./scripts/reinstall-app.sh
```

This is the single finalization command. It tests, rebuilds, replaces `/Applications/Webcard.app`, and opens the new build. Do not run a separate installation while this command is active.

The command uses a machine-wide per-user lock shared by worktrees. If another agent owns the lock, it exits with owner, process, start time, repository, and destination details. Wait for that agent to finish rather than bypassing or deleting an active lock.

Set `WEBCARD_INSTALL_OWNER` to a recognizable agent or task name when available. Set `WEBCARD_INSTALL_PATH` only when intentionally installing somewhere other than `/Applications/Webcard.app`.
