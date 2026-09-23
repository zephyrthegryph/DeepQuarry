# Testing

Everything CI checks can be run locally. On Windows use the `bin/*.cmd` entry
points or `tools\build\build.bat`; on Linux (and in Git Bash) use
`tools/build/build.sh`. Both take the same targets and `-D` defines.

## Quick reference

| Goal | Command | Typical time |
|---|---|---|
| Full unit-test suite on the test map | `bin/test.cmd` · `tools/build/build.sh dm-test` | about 4 minutes plus compile |
| A few tests only (use this while developing) | `bash tools/dq_focused_test.sh /datum/unit_test/<name> [...]` | compile + about 25 s |
| Unit tests on Southern Cross | `tools/build/build.sh dm-test -DCITESTING_FULL_MAP` | much longer |
| Focused tests on Southern Cross | `bash tools/dq_focused_test.sh --full-map /datum/unit_test/<name>` | |
| DM lint + TGUI lint and types | `tools/build/build.sh lint` | a few minutes |
| TGUI tests | `tools/build/build.sh tgui-test` | under a minute |
| Build everything | `bin/build.cmd` · `tools/build/build.sh` | |
| Rust extension | `cd verdigris && cargo test --package verdigris` | |
| Flaky or pre-existing failure? | `tools/build/build.sh test-repeat --runs=5` · `test-baseline` | suite × runs |
| Benchmarks (memory, tick cost, overruns) | `bin/bench.cmd` · `tools/build/build.sh bench` | a few minutes per boot |

## Unit tests

Unit tests are `/datum/unit_test` subtypes under `code/modules/unit_tests/`,
registered in `_unit_tests.dm`. `dm-test` compiles the game with `UNIT_TESTS`,
`CITESTING` and `CIBUILDING`, boots it in DreamDaemon, runs every test, and
shuts down. It also repacks icons and builds Verdigris first if they are stale.

- **Map.** Under `CITESTING` the world boots `maps/virgo_minitest/`, one small
  station level that loads in seconds. Add `-DCITESTING_FULL_MAP` to boot
  Southern Cross instead; use that for map-specific tests.
- **Results.** The runner prints a pass/fail/skip summary. Details are in
  `data/unit_tests.json` (per test) and `data/logs/ci/tests.log`. A run is clean
  only if every test passed and there were no runtimes; the world then writes
  `data/logs/ci/clean_run.lk`. Runtimes alone fail the run
  (`data/logs/ci/runtime.log`).
- **Writing tests.** See `code/modules/unit_tests/README.md` for the API
  (`allocate()`, `TEST_ASSERT*`, `TEST_FAIL`). Use real game objects where you
  can, and avoid `prob()`, since RNG is seeded during tests.

### Focused runs

**While developing, run only the tests you are working on. Run the full suite
only when you integrate** (before merging, or when asked to). A full run costs
about 3 minutes of compile, 40 seconds of boot and three minutes of tests; a
focused run costs the compile plus about 25 seconds.

`tools/dq_focused_test.sh` is that loop. It adds `TEST_FOCUS(...)` lines to
`code/modules/unit_tests/dq_focus.dm`, runs `dm-test`, and restores the file
afterwards, even if the run fails. It works from any checkout, including a git
worktree, because it runs from the directory the script lives in. You can also
edit `dq_focus.dm` by hand and run `bin/test.cmd`.

```sh
bash tools/dq_focused_test.sh /datum/unit_test/belly_damage /datum/unit_test/spritesheets
DQ_WIP_TREE=1 bash tools/dq_focused_test.sh /datum/unit_test/<name>   # tree with someone else's unfinished includes
```

A focused run skips some waits that only matter for the full suite. None of
them can hide a failure in the full suite, which still does all of them:

| Skipped in focused runs | Full suite | Why it is safe |
|---|---|---|
| Round-start settle before the first test: 2 s instead of 10 s (`HandleTestRun`, `code/game/world.dm`) | 10 s | Nothing is skipped, only started sooner. A test that fails only when focused depends on round-start settling and should wait for what it needs itself. |
| Round-end report delay: 0 s instead of 5 s (`declare_completion`, `code/_helpers/roundend.dm`) | 5 s | The delay lets players read the report; a test world has none. |
| Generating every asset and spritesheet at boot, about 2.3 s (`SSassets.Initialize`) | all generated | `get_asset_datum()` builds an asset on first use, and the `spritesheets` and `test_asset_smart_cache` tests call it, so focusing those still generates and checks every sheet. |

`unit_test_is_focused_run()` is the switch; add a row here if you add another.

Compile time is not reduced: `dm-test` never runs DreamChecker (only `dm` and
`lint` do), and the icon repack and Verdigris build are already skipped when
nothing they read has changed. Boot before `world/New` (about 19 s, DreamDaemon
loading the `.rsc` and the compiled-in test map) is outside our control.

### Writing fast tests

Drive the thing under test directly instead of sleeping for game time:

- Mob and belly behaviour: call `Life()` and `/obj/belly/process()` a fixed
  number of times (see `_vore_test_run_cycles` in `vore_tests.dm`). A mob Life
  tick is 2 s of real time, so ten sleeps cost 20 s.
- Atmosphere: the Rust worker simulates in wall-clock epochs, so atmos tests
  must still wait for real `SSair` fires. Use
  `dq_unit_test_wait_air_until_quiescent(max_fires)`: it returns once the
  worker has published nothing for a few fires, and a leak keeps it publishing,
  so a test looking for one still waits the full budget. On the test map the
  worker has not yet been seen to go idle, so today this saves nothing there;
  the real fix for slow atmos tests is a way to step the solver directly.
- Polling for a state change: `sleep(1)` in a loop with the same total budget,
  not `sleep(1 SECOND)`.

`dq_focus.dm` must be committed empty. CI (`tools/ci/check_misc.sh`) fails if it
contains a focus line, or if a `TEST_FOCUS` anywhere else is not inside an
`#if`/`#ifdef` block.

### Test records, flakes and baselines

Every `dm-test` run is saved to `data/test-runs/<timestamp>_<commit>.json`: pass,
fail and skip for each test, its duration, the runtimes it raised, and how many
MC ticks it overran (tick usage above 100%). After a run the console lists the
slowest tests, the tests that overran the tick, and the tests that raised
runtimes.

| Question | Command |
|---|---|
| Is a failure flaky? | `tools/build/build.sh test-repeat --runs=5` runs the suite 5 times on one build and lists consistent and intermittent failures. |
| Did my change cause it? | `tools/build/build.sh test-baseline` runs the suite on `HEAD` (without your uncommitted changes) in a reusable worktree and lists new, fixed and shared failures against your latest run. `--ref=<commit>` picks another base. |
| What changed between two runs? | `tools/build/build.sh test-compare` (defaults: previous against latest; `--base=` and `--head=` take `latest`, `previous`, a commit or a file). |

`test-baseline` leaves its worktree in the system temp folder so the next run is
fast; it prints the command to remove it.

### Working tree with someone else's unfinished work

If another branch of work has left the manifest pointing at deleted files, or
added files it hasn't included yet, set `DQ_WIP_TREE=1`. Test and benchmark
builds then drop includes of missing files and only warn about unreachable
ones. Never use it for a commit check: CI builds without it.

## Benchmarks

Benchmarks are scenarios in `code/modules/benchmarks/`, compiled only with
`-DBENCHMARK`. The `bench` target builds that world, boots it once per iteration,
runs the scenarios, and samples DreamDaemon's memory and CPU from outside the
process. `bin/bench.cmd` is the Windows shortcut.

```
tools/build/build.sh bench                                    # default scenarios, once
tools/build/build.sh bench --runs=3                           # 1 warm-up + 3 measured boots
tools/build/build.sh bench --scenario=atmos_large --arg=size=96
tools/build/build.sh bench --scenario=boot_memory -DCITESTING_FULL_MAP
tools/build/build.sh bench --scenario=idle --profile          # also dump BYOND proc profiles
tools/build/build.sh bench-compare                            # latest against previous
tools/build/build.sh bench-report                             # regenerate data/bench/report.html
```

Juke options take `=`: write `--scenario=a,b`, not `--scenario a,b`.

| Scenario | Measures | Options (`--arg=name=value`) |
|---|---|---|
| `boot_memory` (default) | Process and Rust heap memory after boot, gas mixtures, live instances by kind and top types, compiled type counts, init time. | `top` |
| `idle` (default) | Tick cost of a quiet round: average and p95/p99/max tick usage, overruns, TPS, per-subsystem cost. | `seconds` (60) |
| `atmos_idle` | Atmos cost of the mapped station at rest, with Rust worker maxima. | `cycles` (120) |
| `atmos_large` | Checkerboard gas equalization on a fresh floor. | `size` (48; 0 = whole level), `cycles` |
| `major_events` | Explosion, supermatter, mass fire and decompression on fresh fixtures. | `events` (comma list) |
| `generation` | Expedition station generation and release; `cycles` > 1 is a leak soak. | `cycles`, `seed` |
| `sm_soak` | Repeated supermatter-scale blasts plus five minutes of recovery. Use the full map. | `blasts` (4), `profile_types` |
| `rustg_dispatch` | Per-call cost of rust-g `hash_string`, `json_is_valid` and `log_write` through a cached `load_ext()` handle against by-name `call_ext`. On 2026-09-23 (loaded machine, three boots) the handle showed no consistent gain, so `code/__defines/rust_g.dm` still calls by name. | `calls` (20000), `rounds` (5) |

**What gets recorded.** Each invocation is one file in `data/bench/runs/`
holding the commit, map, defines, every iteration's raw results (metrics,
subsystem breakdowns, the ticks that overran, memory at each phase, the full
memory time series) and a summary: median, spread, minimum and maximum of every
metric over the measured iterations. The world also reports subsystem
initialization times and runtimes. With `--profile`, BYOND proc profiles for
each measurement window go to `data/bench/profiles/<run>/`.

**Comparing.** `bench` compares itself with the previous run on the same map
automatically; `bench-compare` does it on demand (`--base=`, `--head=`,
`--threshold=` percent, `--all` to list unchanged metrics,
`--fail-on-regression` for scripts). A metric changes only when it moves by more
than both the threshold (5% by default) and twice its run-to-run spread, so
use `--runs=3` or more for anything you want to trust. Memory is stable enough
for single runs; tick timings are not.

**Report.** `data/bench/report.html` is regenerated after every `bench`. It
shows the latest run against the previous one, a trend line per metric, the
memory timeline with scenario phases, the ticks that overran, and recent
unit-test runs. Open it in a browser; it needs no network.

**Writing a scenario.** Subtype `/datum/benchmark`, set `id` and `description`,
and implement `Run()`. The helpers are in `_benchmark.dm`:

| Helper | Use |
|---|---|
| `metric(name, value, unit, better)` | A compared number; `better` is `"lower"`, `"higher"` or `"none"`. |
| `detail(name, value)` | Context that isn't compared (tables, lists). |
| `begin_window()` / `end_window(prefix)` | Tick usage, overruns, TPS and per-subsystem cost between the two calls. |
| `mark(name)` | Process and Rust heap memory at this moment. |
| `param(name, default)` | A `--arg=name=value` option. |
| `wait_for_assets()`, `wait_fires(SS, n)`, `wait_seconds(n)` | Settle before measuring. |
| `benchmark_census()`, `benchmark_type_counts()` | Live instance and compiled type counts. |

Call `fail(reason)` to abort. A scenario that fails or runtimes still records
what it measured.

## Linting

`tools/build/build.sh lint` runs DreamChecker (SpacemanDMM) and the TGUI Biome and
TypeScript checks. DreamChecker is skipped with a notice if it is not installed;
install it with `tools/ci/install_spaceman_dmm.sh dreamchecker`, or put
`dreamchecker.exe` in `%USERPROFILE%/SpacemanDMM/`.

CI also runs these scripts, all from the repository root:

| Check | Command |
|---|---|
| Code and map grep checks | `bash tools/ci/check_grep.sh` |
| Committed test focus | `bash tools/ci/check_misc.sh` |
| No `world.time` deadline polling in `process()` (use `REACT_AT`; allowlist in `tools/ci/deadline_polling_allowlist.txt`) | `python3 tools/ci/check_deadline_polling.py` |
| Changelog stubs parse | `bash tools/ci/check_changelogs.sh` (compiles stubs; run on a scratch copy) |
| Local `#define`s are `#undef`'d | `tools/bootstrap/python -m define_sanity.check` |
| Maps are in TGM format and merge-clean | `tools/bootstrap/python -m mapmerge2.dmm_test` |
| Map lint rules (`tools/maplint/lints/`) | `tools/bootstrap/python -m tools.maplint.source` |
| Every `.dmi` parses | `tools/bootstrap/python -m dmi.test` |
| Rust format, lint and tests | `cd verdigris && cargo fmt --package verdigris --check && cargo clippy --package verdigris --all-targets -- -D warnings && cargo test --package verdigris` |

`check_grep.sh` uses ripgrep when it is installed. Without it, it falls back to
GNU grep in Perl-regex mode and skips the few multiline checks that need
ripgrep; CI always runs the full set.

## Continuous integration

`.github/workflows/ci.yml` runs on every push to `master`, on pull requests, in
the merge queue, and on demand from the Actions tab.

| Job | What it does |
|---|---|
| Run Linters | Everything in the linting section, plus OpenDream's compiler and the nanomap render check. |
| Unit Tests | Builds Verdigris from source and runs the full suite on the test map. |
| Compile Checks | Compiles the production build (Southern Cross, no test defines), checks the BYOND client version it needs, and compiles every map template under `MAP_TEST`. |
| Completion Gate | One required status that passes only if all of the above passed. |

Other workflows:

| Workflow | When | What |
|---|---|---|
| `full_map_tests.yml` | Weekly and on demand | The unit-test suite on Southern Cross. |
| `benchmarks.yml` | Pushes to master, pull requests, weekly (Southern Cross) and on demand | Runs the benchmarks three times, compares with the latest master run in the job summary, and uploads `data/bench/` as the `bench-runs` artifact. Regressions are reported, not enforced. |
| `compile_changelogs.yml` | Nightly | Rolls `html/changelogs/*.yml` into `html/changelogs/archive/`. |
| `autochangelog.yml` | On pull requests | Turns a `:cl:` block in the PR body into a changelog stub. |
| `tgs_test.yml`, `update_tgs_dmapi.yml` | On TGS changes / nightly | Keep the TGS deployment integration working and current. |
| `stale.yml` | Nightly | Marks stale issues and pull requests. |
