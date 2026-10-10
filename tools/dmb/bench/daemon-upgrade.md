# Owned dual-generation upgrade prototype

Requires two distinct immutable compiler images implementing the optional
`DMB_DAEMON_NAMESPACE` endpoint suffix. No run is admitted for older binaries.
The default user endpoint is never probed, replaced or retired.

Example (root owns execution):

```powershell
python tools/dmb/bench/daemon-upgrade.py --old E:/dq-cache/old.exe --old-sha256 OLD_SHA256 --new E:/dq-cache/new.exe --new-sha256 NEW_SHA256 --template E:/dq-cache/template.dmb --template-sha256 TEMPLATE_SHA256
```

The new generation's normal CLI client must initiate the upgrade. The helper
never sends `Retire`. Success requires an observed retiring Hello before the old
build completes, successful old output, authenticated replacement process/image,
and exact DMB/RSC equality against each generation's independent fresh compile.
A missed tiny-build overlap fails explicitly instead of claiming drain coverage.

Overall execution is bounded to 300 seconds; two client requests at most, two
compiler workers each. An owned Windows job applies a 4 GB committed-memory limit
and owns client-autostart descendants for cleanup. Each child starts suspended, enters the owned job, then resumes; descendants
therefore inherit ownership before any compiler code executes.
This is a lifecycle correctness prototype, not six-worktree, game-runtime or
performance acceptance. No compiler invocation has been run for this helper yet.
