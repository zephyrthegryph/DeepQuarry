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

### Sharded sweeps

A handful of tests sweep every subtype of some root (every latent-safe
`/atom/movable`, every clothing item, every property-provider type, ...) and
dominate the suite's wall time. `/datum/unit_test/proc/sweep_types(list/types)`
splits such a list by round-robin index across `GLOB.dq_test_shard_count`
worlds, keyed by `GLOB.dq_test_shard_index` -- pass it whatever you'd
otherwise iterate:

```dm
for(var/atom/movable/path as anything in sweep_types(subtypesof(/atom/movable)))
```

With no sharding configured (a plain `dm-test` or focused run, the default)
`sweep_types()` returns its input unchanged, so adopting it costs nothing.
Under a sharded run, each world reads its position from world params
(`-params shard-index=K&shard-count=N`, read once by `dq_test_shard_init()` in
`world/proc/HandleTestRun()`) and every shard ends up with a similar-cost
slice of each sweep automatically -- round-robin, not a contiguous range, so a
slice stays representative even when `types` is clustered (e.g. many cheap
subtypes of one branch followed by a few costly ones from another).

Tests already using it: `dq_lifecycle_sandbox`, `dq_state_latent_round_trip`,
`dq_property_type_values_valid`, `all_clothing_shall_be_valid`, and (via
`dq_constraint_parity/run_holders()`) `dq_constraint_parity/equip`,
`dq_constraint_parity/storage` and `dq_constraint_parity/suit_storage`.

### `dm-test --shards=N`

`tools/build/build.sh dm-test --shards=N` compiles once, then boots N
DreamDaemon worlds in parallel and merges their results into one
`data/test-runs/` record:

- Every sweep test runs in **every** shard, each doing its own slice via
  `sweep_types()` (see above) -- `is_sweep_test = TRUE` on the test type
  marks it as one, so the shard test-selection filter below never excludes
  it.
- The other ~1000 non-sweep tests are greedy bin-packed across shards by
  historical duration (from the latest `data/test-runs/` record; tests with
  no history get a small default weight), heaviest first onto the lightest
  shard. Each shard gets a `data/test-shards/shard-<i>-of-<N>.txt` list (one
  test type path per line) passed via `-params shard-tests=<path>`, read by
  `dq_test_shard_init()` into `GLOB.dq_test_shard_names`; `RunUnitTests()`
  keeps a test only if it's in that list or is a sweep test.
- Each shard world is fully isolated: its own `data/logs/shard<i>/`
  (`-params log-directory=shard<i>`), its own results file
  (`data/unit_tests-shard<i>.json`, `-params unit-tests-file=<path>` --
  `TEST_RESULTS_FILE_PARAMETER`, defaulting to `data/unit_tests.json`
  unchanged when unset) and its own process/CPU sampler file, so N worlds in
  one worktree never clobber each other.
- Each shard's DreamDaemon boot acquires its own slot from the same
  machine-wide `dd-slot.sh` budget everything else on the machine uses
  (`tools/build/lib/dd_slot.ts`: a TypeScript-native port of the same
  mkdir-lock-directory protocol, same lock paths, same priority lane), and
  releases it the moment that shard exits -- shards run concurrently up to
  however many slots are actually free; the rest queue.
- `--shards=0` picks the shard count automatically from a snapshot of
  currently-free dd-slots (clamped to 2-6), instead of a fixed number you
  have to guess -- `dm-test --shards=0`. This is opt-in: omitting `--shards`
  entirely still means one world, unchanged, for every existing caller (CI,
  the merge-to-master run, dq_focused_test.sh).
- The merged summary reports wall time (when every shard finished) and
  summed CPU (each shard's `ProcessSampler` total, added up) side by side,
  plus the slowest 20 tests suite-wide (`testHotspots(..., 20)`) -- a sweep
  test's entries across shards are summed into one duration, matching what a
  single unsharded world would have reported for it.

Non-sharded (`dm-test`, no `--shards`) is unaffected: `GLOB.dq_test_shard_count`
defaults to 1, `sweep_types()` returns its input unchanged, and no shard-tests
file is ever written or read.

### Domains, tiers and `--affected`

`dm-test --domains=atmos,heat`, `--tier=fast|sweep|full` and `--affected`
narrow which tests run, for fast local iteration -- **CI and the
merge-to-master run always use the full, unfiltered suite** (no flags), since
this filter is a best-effort keyword classifier, not an authoritative
per-test registry:

- Every test is tagged with a domain inferred from the unit-test source file
  it's declared in (a path/filename keyword table in `build.ts`,
  `DOMAIN_PATTERNS` -- `atmos`, `heat`, `power`, `medical`, `mobs`, `rules`,
  ..., falling back to `misc`). The same table classifies a changed *source*
  file for `--affected`.
- `--tier=fast` (the default whenever any of these flags is used) runs every
  non-sweep test; `--tier=sweep` runs only the sweep tests; `--tier=full`
  runs both (still subject to `--domains` if also given).
- `--domains=a,b` keeps only tests in those domains (any tier).
- `--affected` maps files changed since `git merge-base master HEAD` (falling
  back to the working tree's own uncommitted changes if there's no `master`
  ref) through the same domain table and unions those domains in; combine it
  with explicit `--domains` to union both.
- With none of these flags, nothing is filtered -- the exact behavior of
  today's plain `dm-test`.

The selection is written to `data/test-shards/select.txt` and passed via
`-params test-select=<path>` (`TEST_SELECT_FILE_PARAMETER`), read into
`GLOB.dq_test_select_names`. Unlike shard-tests, this filter applies to sweep
tests too -- a domain filter can legitimately exclude a sweep that has
nothing to do with the requested domains. It composes with `--shards=N`: the
domain/tier selection narrows the pool bin-packing draws from, and the same
selection file is passed to every shard so sweeps are filtered there too.

### `dm-test --incremental`

Skips an eligible sweep test entirely when its inputs are byte-identical to
its last *passing* run (`data/dmb-cache/sweep-hashes.json`, keyed per test,
updated after any run -- sharded or not -- where that sweep ran and passed).
Composes with `--domains`/`--tier`/`--shards` via the same selection
mechanism as those.

**Currently skips nothing**, by design: eligibility (`SWEEP_INCREMENTAL_SCOPE`
in `build.ts`) requires a trustworthy list of the source paths that determine
a sweep's outcome, and every sweep here iterates `subtypesof()`/`typesof()`
of some root, so its true input set is "every file that declares a subtype
of that root, anywhere in the tree" -- not a tidy folder. A first attempt at
scoping `all_clothing_shall_be_valid` to `code/modules/clothing/` and
`dq_property_type_values_valid` to `code/datums/properties/` was exactly
this mistake (clothing subtypes, and the vars property providers read, are
declared all over the tree -- cult items, changeling powers, holiday
events, ...), which would have produced false skips: a change outside those
folders, silently not re-tested. Getting this right needs a real type ->
declaring-file map (a source-level index, or a boot-time dump from the
world itself), which doesn't exist yet. `--incremental` is safe to use
today -- it just doesn't save anything until `SWEEP_INCREMENTAL_SCOPE` gets
real, verified entries.

### Watchdog timeout

DreamDaemon sometimes fails to exit after `-close` finishes (a known Windows
zombie-process issue), so every test/bench boot runs under a watchdog: once
the results file appears, it gets `watchdogGraceMs` (30s) to self-close, then
is force-killed. Separately, a **hard timeout** (default 45 minutes,
`DQ_DD_WATCHDOG_MINUTES=<n>` overrides it, taking precedence over everything
including a caller's own estimate) force-kills a world that's still running
at all -- genuinely stuck, or just slower than expected under load. Only the
hard-timeout kill is logged as an explicit error (`killedByWatchdog` in the
run record) and called out by name in the summary; the routine post-completion
zombie cleanup is just an info line. `dm-test --shards=N` scales each shard's
hard timeout down from the 45-minute default by `1/sqrt(N)`, floored at 12
minutes, since each shard does roughly `1/N` of the suite's work.

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

### Compile caching

`dm-test`/`test-repeat` skip the DreamMaker compile when nothing that would
change its output has changed: a content hash of the derived `.dme` text,
every `.dm` file it transitively includes, the define list and the DM
compiler version is compared against the record from the last successful
compile (`data/dmb-cache/<dme>.hash.json`, per worktree like everything else
under `data/`). A flake recheck or a focused rerun on an otherwise-unchanged
tree reuses `deepquarry.test.dmb`/`.rsc` straight away instead of
recompiling; any change to the tracked inputs (or a missing/corrupt cache
record) recompiles as before. This is why `deepquarry.test.dmb`/`.rsc` are no
longer deleted after a run — only the derived `.dme` text is, since it's
cheap to regenerate.

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
