# The boot gate

Every unit-test world, focused or full, must boot clean: **no runtime and no logged warning before the
first test starts**. A world that did fails the run with its own reason, whatever the tests did, so a
boot-time runtime fails for whoever introduces it on their very next focused run, not for the next
agent who happens to read the log.

## What counts

| Counted | Where it comes from |
|---|---|
| A runtime | `world/Error()` (`GLOB.total_runtimes`); the text is in `data/logs/<run>/runtime-errors.log` |
| A warning | `WARNING()` / `warning()` ("## WARNING: ..."), and a refused `move_into()` ("MOVE_INTO: ... refused: ...") |

Both counters (`GLOB.total_runtimes`, `GLOB.boot_noise_count` in `code/_helpers/logging/_logging.dm`) are read by
`unit_test_boot_gate()` (`code/modules/unit_tests/unit_test.dm`) right after "Unit-test suite starting".
Informational lines (`log_world()`, "System X initialized", a shuttle without a landmark on the test map)
are not counted; a problem worth fixing is logged with `WARNING()`.

## What you see when it trips

- `tests.log`: `::error title=Boot gate::Boot was not clean: N runtime(s) and M warning(s) before the first test`,
  then the first warnings.
- `data/logs/<run>/boot_report.json`: the counts and the first 20 warnings.
- The build (`dm-test`, so `tools/dq_focused_test.sh`): a `BOOT GATE:` error line after the log tails, the first
  warnings and the start of `runtime-errors.log`.
- The run's verdict: `FinishTestRun()` adds the reason, so `clean_run.lk` is not written.

## Checking boot alone

```sh
bash tools/dq_focused_test.sh --boot              # the test map; runs only dq_boot_gate
bash tools/dq_focused_test.sh --boot --full-map   # Southern Cross
```

## Fixing a trip

Fix the cause; don't silence it. A `WARNING()` that is really information becomes `log_world()`. A runtime
or a refused move at boot is a bug in the type that logged it (`Initialize()`, a system's init, a mapped
fixture). The boot is the same for every test, so the gate's trip is never the focused test's fault unless
the change under test runs at boot.

## Fixed when the gate landed (October 2026)

- `load_jobwhitelist()` warned on every `#` comment line of `config/jobwhitelist.txt` (11 warnings).
- `default_use_hicell()` created the high-capacity cell inside the machine and then moved it in again
  ("MOVE_INTO ... refused: it is already there", every recharge station and fluid pump).
- The suite itself started as a scheduler callback that slept ("OM: SLEPT /proc/RunUnitTests"); it now
  starts through `start_unit_tests()`, which returns at once.
