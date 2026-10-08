# Testing

Everything CI checks can be run locally. On Windows use the `bin/*.cmd` entry
points or `tools\build\build.bat`; on Linux (and in Git Bash) use
`tools/build/build.sh`. Both take the same targets and `-D` defines.

## Quick reference

| Goal | Command | Typical time |
|---|---|---|
| Unit-test suite, normal tier (every merge) | `bin/test.cmd` · `tools/build/build.sh dm-test` (sharded; `--shards=1` for one world) | 2–3 minutes plus compile (about 5 in one world) |
| Every tier, as CI and nightly run it | `tools/build/build.sh dm-test --tier=all` | 5–6 minutes plus compile, sharded |
| The E0 proofs (pending the engines, so not in any other tier) | `tools/build/build.sh dm-test --tier=e0` · `bash tools/dq_focused_test.sh 'dq_e0_proof/*'` | compile + about 25 s |
| Profile each test's procs | add `--profile-tests` to `dm-test` or `dq_focused_test.sh` | about twice as slow |
| A few tests only (use this while developing) | `bash tools/dq_focused_test.sh <name> [...]` (bare names, `/datum/unit_test/` paths or quoted `*` globs; `--repeat=N`) | compile + about 25 s |
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

Verdigris comes from a shared cache when it can: the build keys the DLL on the
git ids of its inputs at `HEAD` (the `verdigris/` tree, the generated bindings,
target, profile, `RUSTFLAGS`) and copies a cached build from
`DQ_VERDIGRIS_CACHE` (default `E:/dq-cache/verdigris`) instead of running cargo,
so a new worktree needs no `verdigris/target`. A miss builds and stores the DLL
(atomic temp-dir rename; the newest 10 entries and anything used in 14 days are
kept). Uncommitted edits to those inputs skip the cache. `DQ_VERDIGRIS_CACHE=off`
disables it. The runner still checks `VERDIGRIS_ABI` before booting.

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
only when you integrate** (before merging, or when asked to). An integration run
is the normal tier (`dm-test`); CI and nightly add the exhaustive tier (see
"Tiers" below). A full run costs about 3 minutes of compile plus the suite
(two to three minutes, sharded); a focused run costs the compile plus about 25 seconds.

`tools/dq_focused_test.sh` is that loop. It runs `dm-test --focus=<names>`:
the names reach the world as the `test-focus` param, so no source file is
edited and every focus set reuses the same compiled `.dmb`. Each run is
isolated from any other run on the machine: it claims a slot `data/runs/runN`,
boots its own copy of the `.dmb`/`.rsc`, on a free port, with its own log
directory (`data/logs/runN`) and results file. A focused run that has not
finished after `DQ_FOCUS_TIMEOUT_MINUTES` (default 15) is killed and reported
as a failure with the last lines of its logs. It works from any checkout,
including a git worktree. `TEST_FOCUS(...)` lines in `dq_focus.dm` with a plain
`bin/test.cmd` still work for manual runs.

```sh
bash tools/dq_focused_test.sh /datum/unit_test/belly_damage /datum/unit_test/spritesheets
bash tools/dq_focused_test.sh belly_damage spritesheets                 # bare names get /datum/unit_test/ prepended
bash tools/dq_focused_test.sh 'dq_expedition_*'                        # glob over every /datum/unit_test type (quote it)
bash tools/dq_focused_test.sh --repeat=5 belly_damage                  # N runs, per-run pass/FAIL summary, fails if any failed
bash tools/dq_focused_test.sh --list 'dq_e0_proof/*'                    # print what the names/globs expand to (about 1 s, runs nothing)
bash tools/dq_focused_test.sh --dm-version=516.1682 belly_damage        # any other --flag is forwarded to dm-test
DQ_WIP_TREE=1 bash tools/dq_focused_test.sh /datum/unit_test/<name>   # tree with someone else's unfinished includes
bash tools/dq_focused_test.sh --boot                                   # boot only (the boot gate below)
```

**The boot gate.** Every run, focused or full, fails when the world logged a runtime or a `WARNING()` (or a refused
`move_into()`) before its first test: `tests.log` says `Boot gate`, the build prints `BOOT GATE:` with the first
warnings, and `data/logs/runN/boot_report.json` holds the counts. It is the boot's fault, not your test's, unless
your change runs at boot. `doc/rewrite/boot_gate.md`.

A long list of names (a broad glob) reaches `dm-test` as `--focus=@file`, since a Windows command line stops at
8191 characters.

A glob (a name with `*`, `?` or `[`) is matched against the `/datum/unit_test/...`
type definitions under `code/` and fails if nothing matches. `--repeat=N` reruns the
same focus set N times against the one compiled `.dmb`, a quick flake check for the
tests you touched (`test-repeat` is the full-suite version).

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

### Isolation: restoring shared state

**The state guard.** After every test the harness compares the scalar `GLOB` vars with their values before it
(`unit_test_globals_guard()`). A flag a test left changed is logged as `STATE LEAK: <test> left GLOB.x = ...`
in `tests.log` (text and paths as `STATE LEAK?`), and a run that fails prints them. A test that fails in a long
focused run but passes alone is almost always one of these: find the leak before it and make that test use
`set_global()`. The guard only flags; it never restores (a lazy-init flag put back would rebuild what it guards).

Every test shares one world, and a failing `TEST_ASSERT` returns from `Run()`
at once, so a restore line after it never runs. Anything a test changes outside
its own block goes through a harness helper, which undoes it in teardown even
when the test fails or runtimes:

- `set_global("name", value)`, `set_var(datum, "name", value)` and
  `set_config(/datum/config_entry/..., value)` record the original on the first
  change and put it back afterwards. Setting a flag back later in the same test
  is fine; teardown still restores the value the test started with.
- `defer_cleanup(target, PROC_REF(x), args...)` runs cleanup that isn't a
  `qdel()` (releasing a site, unregistering from a global list), last queued
  first, before `allocate()`d objects are deleted.
- Put objects on the test's own block (`run_loc_floor_bottom_left`), not at a
  fixed map coordinate: the leak check only sees the block.

Teardown (the deferred cleanups, then deleting `allocate()`d objects) runs in
the tick `Run()` returns, so a timer or task still pending on a test's entities
(a mob's telegraphed attack, say) dies with them instead of landing after the
test. It then fails a test that leaves objects on its block or an expedition
site live; the site is released so later tests start clean.

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

### Tiers

Every test has a `tier` (`code/modules/unit_tests/_unit_tests.dm`):

| Tier | Runs in | What it holds |
|---|---|---|
| `TEST_TIER_NORMAL` (the default) | every integration merge: `tools/build/build.sh dm-test`, `bin/test.cmd` | every ordinary test, plus a small representative of each exhaustive sweep |
| `TEST_TIER_EXHAUSTIVE` | CI (`run_integration_tests.yml`, including the weekly full-map run) and nightly: `dm-test --tier=all` | the whole-type sweeps (see below) |
| `TEST_TIER_E0` | only `dm-test --tier=e0`, or a focused run by name | the ten E0 proofs, which cannot pass until engines E1-E6 land (see "The E0 proofs") |

**Integration merges run the normal tier; CI and nightly run the exhaustive
tier as well.** A plain `dm-test` runs the normal tier. `--tier=all` (or
`--exhaustive`) runs both, `--tier=exhaustive` runs only the sweeps. The older
names still work: `fast` = normal, `full` = all, `sweep` = exhaustive. The
world does the filtering: the runner passes `-params test-tier=<tier>` and
`RunUnitTests()` checks each test's `tier` var. CI launches DreamDaemon itself
(`tools/ci/compile_and_run.sh`) with `test-tier=all` (the `TEST_TIER`
environment variable, default `all`).

**A focused run ignores the tier.** `bash tools/dq_focused_test.sh
dq_lifecycle_sandbox` runs the exhaustive sweep by name, as does
`dm-test --focus=...`.

The exhaustive tier holds the tests that check every subtype of a root, or
every cell of a large matrix:

- `dq_constraint_parity/equip`, `/storage` and `/suit_storage`, and
  `dq_constraint_declarations_compile`;
- `dq_property_type_values_valid`;
- `dq_lifecycle_sandbox` and `dq_state_latent_round_trip`;
- `dq_rule_thresholds` and `dq_balance_harness`;
- `all_clothing_shall_be_valid` and `dq_containment_conservation_fuzz`;
- `dq_all_species_handle_breath_safely` and `dq_latent_closet_types`.

Each one has a normal-tier representative, a `.../representative` subtype that
sets `tier = TEST_TIER_NORMAL`. It runs the same code over a fixed, curated
subset, so a merge still catches an obviously broken path. A sweep that goes
through `sweep_types()` names its subset by overriding `curated_types()`. The
harness then filters the sweep to those entries and fails the representative
if any curated entry is missing from the sweep, for example after a rename.
The others override a small hook: `equip_species()`/`item_stride()` for equip,
`scenario_ids()` for the balance harness, and `steps` for the containment fuzz.

To add a sweep, write it exhaustive with a representative. Put it in the
normal tier only if it is cheap: `dq_constraint_parity/holster` has seventeen
holders and stays whole in the normal tier.

### The E0 proofs

Phase 1 of the rewrite (`doc/rewrite/final_api.html` section 19) starts with ten executable proofs of the
semantic contracts that would be expensive to get wrong after content conversion begins. They live in
`code/modules/unit_tests/dq_e0_proofs_tests.dm` as `/datum/unit_test/dq_e0_proof/p01_...` to `p10_...`, are written with the test driver
(`code/tests/driver/`) and the test-only fixtures (`code/tests/engine/`), and are all green only when engines E1-E6 have landed.
Until then each one fails, on purpose, with `E1-E6 not implemented: <what>` naming every engine piece it reached.

They have a tier of their own, `TEST_TIER_E0`, so the normal suite stays green:

| Command | Runs the proofs? |
|---|---|
| `dm-test` (normal), `dm-test --tier=all`, `dm-test --tier=exhaustive` | no |
| `dm-test --tier=e0` | yes, and only them |
| `bash tools/dq_focused_test.sh 'dq_e0_proof/*'` or `... dq_e0_proof/p05_refused_insert_loses_nothing` | yes (a focused run ignores the tier) |

A tier-e0 run reports them separately from the rest of the run: each failing proof prints a `E0 PENDING` line with its reasons
(when the failure is only a missing engine), and the log ends with `E0 proofs: N green, N pending an engine, N failed for another
reason`. A proof that fails for any other reason, such as an assertion, counts as failed. The tier-e0 run exits non-zero until all ten
are green, which is the gate: the ten must pass before any content conversion starts, and again before every phase 3 step.

A proof reads what it needs into locals as it drives the fixture, then calls `E0_GATE` once and asserts. `E0_GATE` fails the
proof with the "not implemented" message if a driver form or a stub it called reached an engine piece that does not exist yet, so a
proof never asserts on a null. When an engine replaces its stubs the gate goes quiet for that piece and the assertions run unchanged.
`doc/rewrite/engine_contracts.md` lists, per proof, which engine it waits for.

### The kernel clock (test_time) and the input inbox

A test that makes time pass or sends an input starts with `test_driver_begin()` (code/tests/driver/driver.dm) and ends with
`test_driver_end()`. Begin gives the kernel an injected clock (`kernel().test_now`, in deciseconds, from 0) and makes a fresh test
OM scheduler current, so every entity the test creates afterwards reads that clock. `test_time(t)` then steps it one slot (one
decisecond) at a time, running the phases K, S, N, D, P, R, G of each slot in order through the same phase procs the live tick
calls, with a drain at the start of S, D, P and R; `test_phase(P)` runs one phase at the current time and moves nothing;
`test_drain()` is one marked drain. Native frames and the host services (tgui transport, dbcore, assets) are not stepped.

Which work a test steps: the items registered while the test owned the clock (a fixture system's `every()`, an entity type's first
`every()` table) and the kernel's own plumbing (the input inbox, requests, jobs). Live items keep their world.time due dates and
never run inside a test; test items never run on the live loop. An item no run has seen is armed one interval after the clock it
first meets, so `every(1 SECOND)` runs exactly five times in `test_time(5 SECONDS)`. A fixture system that must not boot with the
live kernel sets `lazy_only = TRUE` and is made by `system(path)`.

`end_test_world()` calls `test_driver_end()`, so a failed assertion or a runtime cannot leave later tests on the injected clock.
The recorder (`test_record` / `test_recorded`) stamps each row with its position (`seq`) and the kernel time (`at`) and holds at
most `TEST_RECORD_MAX` rows.

The input inbox (code/engine/kernel/inbox.dm) is tested with `/datum/input_event` fixtures: `SSinput.room_override` (TRUE or FALSE)
decides whether an input resolves in place or queues, and `test_phase(KERNEL_PHASE_K)` drains. In a test build the tick always has
room unless the override says otherwise (a test world boots through ticks far past 100%).

### Sharded runs

`dm-test` runs sharded by default. It compiles once, then boots N DreamDaemon
worlds in parallel on the same `.dmb`, merges their results into one
`data/test-runs/` record, and prints one summary line (with each shard's wall
time) and the failures.

- `--shards=N` sets the count. The default is the core count minus one,
  capped at 4 (`DQ_TEST_SHARDS` overrides it). `--shards=1` is the
  single-world mode. `--shards=0` sizes the count from free dd-slots. A
  `--focus` run is always one world.
- Each shard gets its own world through the same isolation as a focused run:
  a run slot `data/runs/runN` (an atomic mkdir lock, reclaimed when its owner
  pid is gone), its own copy of the `.dmb`/`.rsc`, a free TCP port, and its
  own log directory (`data/logs/runN`) and results file. Shards never share a
  path or port with each other or with any other test world on the machine.
- A machine-wide dd-slot (`tools/build/lib/dd_slot.ts`, the `dd-slot.sh`
  protocol) is also taken per shard when `DQ_DD_SLOT_BASE` configures a shared
  DreamDaemon budget. Without that variable the dd-slot fallback is
  per-worktree with two non-priority slots, which would serialize the shards.
- **Sweep tests** (`is_sweep_test = TRUE`) run in every shard, each doing its
  own slice. `sweep_types(list)` returns a round-robin slice of a type list,
  and `sweep_owns(index)` tells a sweep whether this shard owns work unit
  `index` (the equip parity test slices by item index this way, so each shard
  also builds only its own probe items). Round-robin keeps every slice
  representative when a list is clustered. A test that isn't a sweep gets its
  whole list from `sweep_types()`, wherever it runs.
- **Every other test** runs in exactly one shard. The runner greedy
  bin-packs the tests it knows onto shards by duration (heaviest first onto
  the lightest shard), taken from the newest `data/test-runs/` record that
  covered most of the suite. Tests without a duration weigh 0.5 s. It only
  packs tests in the chosen tier. Every shard gets the same assignment file
  (`-params shard-tests=<file>`, one `path<TAB>shard` line per test). A world
  runs what is assigned to it. A test the file doesn't name (added since
  those durations, or missed by the source scan) goes to the shard a hash of
  its path picks (`dq_test_shard_of_unlisted()`), so no test is skipped.
  Sweep and tier status come from a source scan of each test's
  `is_sweep_test` and `tier` vars (nearest declaration up the type path, like
  DM inheritance), over the files `_unit_tests.dm` includes. So there is no
  list to keep in sync.
- Each run's assignment file is kept in `data/test-shards/<run id>/`, so a
  failure that depends on what else ran in its world can be rerun with the
  same set (`dm-test --focus=` that shard's tests).
- Worlds sharing a worktree also get their own spritesheet directory
  (`-params spritesheet-dir=data/spritesheets/runN/`, `SPRITESHEET_DIR`), and
  their own `<world>.dyn.rsc` is cleared per run. Otherwise they write the
  same generated files at once.
- A sweep test's per-shard entries are merged into one: durations and
  runtimes summed, worst status kept.

`GLOB.dq_test_shard_count` defaults to 1, so a world booted without shard
params (CI, `test-repeat`, `test-baseline`) runs every test in its tier, and
`sweep_types()` returns its input unchanged.

### Profiling a slow test

`dm-test --profile-tests` (works with `--focus` and through
`dq_focused_test.sh --profile-tests`) wraps every test in BYOND's proc profiler
and writes `data/logs/<run>/profile/<test>.json` (self/total/real time and
calls per proc). Profiling roughly doubles test time, so read the proportions,
not the absolute times. Use it before optimising a test, instead of a one-off
timing script.

### Domains and `--affected`

`dm-test --domains=atmos,heat` and `--affected` narrow which tests run, for
fast local iteration. They are a best-effort keyword classifier, not an
authoritative per-test registry, so integration merges and CI never pass
them:

- Every test is tagged with a domain inferred from the unit-test source file
  it's declared in (a path/filename keyword table in `build.ts`,
  `DOMAIN_PATTERNS` -- `atmos`, `heat`, `power`, `medical`, `mobs`, `rules`,
  ..., falling back to `misc`). The same table classifies a changed *source*
  file for `--affected`.
- `--domains=a,b` keeps only tests in those domains, within the chosen tier.
- `--affected` maps files changed since `git merge-base master HEAD` (falling
  back to the working tree's own uncommitted changes if there's no `master`
  ref) through the same domain table and unions those domains in; combine it
  with explicit `--domains` to union both.

The selection goes to the world as `-params test-select=<file>`
(`TEST_SELECT_FILE_PARAMETER`), read into `GLOB.dq_test_select_names`. Unlike
shard-tests, it applies to sweep tests too.

### `dm-test --incremental`

Skips an eligible sweep test entirely when its inputs are byte-identical to
its last *passing* run (`data/dmb-cache/sweep-hashes.json`, keyed per test,
updated after any run -- sharded or not -- where that sweep ran and passed).
Composes with `--domains`/`--tier`/`--shards`.

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

### DLL approval dialog (Windows)

Our worlds load DLLs (verdigris, rust_g). The first time DreamDaemon runs a
`.dmb` path it has not approved, it shows a modal "Security Alert: This game
uses one or more external libraries" dialog, in `-safe` mode as well as
`-trusted`, and waits for a click. Headless runs never get one, so a test or
bench boot in a new worktree used to sit at "loading" until the watchdog killed
it. `DreamDaemon()` in `tools/build/lib/byond.ts` now records the `.dmb` in the
user's approval list (`<BYOND userpath>/cfg/trusted.txt`, the same thing the
dialog's "Host Game" button does) before launching. Only that path is added;
the world still runs with `-safe`, and BYOND's default security setting is left
alone. If a boot still shows no `data/logs/ci/` after a minute, look for a
dreamdaemon window titled "Security Alert".

### Watchdog timeout

DreamDaemon sometimes fails to exit after `-close` finishes (a known Windows
zombie-process issue), so every test/bench boot runs under a watchdog: once
the results file appears, it gets `watchdogGraceMs` (30s) to self-close, then
is force-killed. Separately, a **hard timeout** (default 120 minutes,
`DQ_DD_WATCHDOG_MINUTES=<n>` overrides it, taking precedence over everything
including a caller's own estimate) force-kills a world that's still running
at all -- genuinely stuck, or just slower than expected under load. Only the
hard-timeout kill is logged as an explicit error (`killedByWatchdog` in the
run record) and called out by name in the summary; the routine post-completion
zombie cleanup is just an info line. `dm-test --shards=N` scales each shard's
hard timeout by `1/sqrt(N)`, floored at 12 minutes, since each shard does
roughly `1/N` of the suite's work: from a 120-minute base for a whole-tier run
(60 minutes per shard on the default 4 shards; the normal tier took up to 34
minutes per shard on 2026-10-04) and a 45-minute base when `--select` or
`--affected` narrows it.

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

### History in the admin viewer

`cd tools/admin-viewer && bun run ingest` loads every `data/test-runs/*.json` and
`data/bench/runs/*.json` not loaded yet into the database the admin viewer reads, which
shows suite pass rate and duration over time, flaky tests (passed and failed on one commit),
per-test history and benchmark metrics per run. CI can run it as a last step with
`DATABASE_URL` set. See `tools/admin-viewer/README.md`.

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

### Shared build caches

Fresh worktrees should not pay cold build costs:

- **Analyzer.** `analyze-build` runs cargo with `CARGO_TARGET_DIR` set to a shared dir
  (`DQ_ANALYZE_TARGET`; default `E:/dq-cache/analyze-target` on Windows when `E:` exists, else
  `~/.cache/dq/analyze-target`; `off` builds in the worktree) and copies the binary to the worktree's
  own `tools/analyze/target/release/` path with its `.key` file. Dependencies compile once; cargo's lock
  serialises concurrent worktrees (cargo prints `Blocking waiting for file lock`). Editing
  `tools/analyze/src` still recompiles the analyzer crate itself (about 2.5 minutes). The content-keyed
  binary cache (`DQ_ANALYZE_CACHE`) still serves unchanged sources instantly.
- **Bun.** `tools/bootstrap/javascript_.ps1` downloads Bun into `DQ_BUN_CACHE` (default
  `E:\dq-cache\bun` when `E:` exists; `off` or an unwritable dir falls back to `tools/bootstrap/.cache`),
  keyed by version. It downloads into a temp dir and renames it into place, so concurrent bootstraps are safe.
- **Heartbeat.** `Juke.exec` prints `still running: <command> (<m>s)` to stderr every 60 s while a child
  process runs (cargo, the DM compile, DreamDaemon, icon repack), so a long step is not mistaken for a hang.

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
tools/build/build.sh bench --exclusive                        # wait for a quiet machine, time it that way
tools/build/build.sh bench-baseline                            # store a master baseline for other worktrees
tools/build/build.sh bench-baseline --ref=<commit>              # ... for a specific commit instead
tools/build/build.sh bench-compare                            # head vs. this branch's stored master baseline
tools/build/build.sh bench-report                             # regenerate data/bench/report.html
```

### Shared store (agents, worktrees)

`data/` is per-worktree and gitignored, so by default a branch worktree has no
access to a run from `master` and every worktree must re-run its own control.
Set `DQ_BENCH_STORE` to a directory that's **outside every worktree** (a
sibling of your checkouts, not inside one) to turn bench runs, the exclusive
lock and the DreamDaemon slot directory into shared, machine-wide state that
every worktree on the machine reads and writes:

```
export DQ_BENCH_STORE=/e/projects/.dq-bench      # bash / worktree agents
$env:DQ_BENCH_STORE = 'E:\projects\.dq-bench'     # PowerShell
```

With it set: `bench` writes runs to `$DQ_BENCH_STORE/runs/` instead of
`data/bench/runs/`; the exclusive-bench lock lives at
`$DQ_BENCH_STORE/.dq-bench-exclusive`; and `tools/ci/dd-slot.sh` /
`dd-slot-exclusive.sh` (the DreamDaemon concurrency limiter agents wrap test
and bench runs with) look for their slot directories at
`$(dirname $DQ_BENCH_STORE)/.dq-dd-slot-N` — i.e. `/e/projects/.dq-dd-slot-N`
for the `DQ_BENCH_STORE` above. Override any one of these individually with
`DQ_BENCH_EXCLUSIVE_LOCK` / `DQ_DD_SLOT_BASE` if your layout differs. With
`DQ_BENCH_STORE` unset, everything falls back to the old per-worktree
`data/bench/runs/` and a `.dq-dd-slot-N` next to that worktree's checkout —
nothing in the committed tooling hardcodes a path.

**One baseline, shared by every branch.** `bench-baseline` runs the bench for
`master` (or `--ref=<commit>`) in a disposable temp worktree — exclusively, so
its TIMING metrics are trustworthy — and stores the result. `bench` and
`bench-compare` then default to comparing against the stored run for
`git merge-base HEAD master`, falling back to the nearest master ancestor
that has one, and both print which baseline commit they used. Re-run
`bench-baseline` after `master` moves meaningfully; stale baselines still
compare (you just get a bigger diff to read through, same as `test-baseline`).

### Exclusive runs and load noise

This machine typically runs several agents' builds, tests and benchmarks
concurrently, and DreamDaemon's tick/wall-clock numbers move 70-140% with
that load — a benchmark taken next to three other compiles is not comparable
to one taken alone. Every stored run therefore also records a `load` block:
how many other `dreamdaemon.exe`/`dm.exe`/`cargo`/`rustc` processes were
running (averaged over the run) and system CPU%.

Every metric is tagged COUNT or TIMING (see `_benchmark.dm`'s `metric()`
`metric_class` argument / `count_metric()`): COUNT metrics (FFI calls,
reactor wakes, subsystem fire/work-item counts, census and list counts, Rust
heap bytes) reflect the same work regardless of speed, so they always compare
against the baseline, with a tight threshold. TIMING metrics (tick
percentages, overruns, TPS, wall-clock windows, RSS) only compare when both
runs were taken under similar load — both `--exclusive`, or close CPU% and
process counts — otherwise `bench-compare` reports that row as
`not comparable (load)` rather than a false regression or a silently missing
number.

`bench --exclusive` acquires a machine-wide lock (so only one exclusive bench
runs at a time), waits up to 5 minutes for already-running DreamDaemons to
drain, then benchmarks; `tools/ci/dd-slot.sh` makes ordinary test/bench runs
wait while that lock is held, so an exclusive run gets an actually quiet
machine. The lock self-expires after 20 minutes even if its holder died, so it
can't starve other agents. `bench-baseline` always benchmarks exclusively for
this reason — a baseline with noisy TIMING numbers isn't useful to compare
against.

`tools/ci/dd-slot.sh` also has a priority lane: `DQ_DD_PRIORITY=1 dd-slot.sh
<command>` can use every DreamDaemon slot, while ordinary (non-priority)
invocations are capped at `DQ_DD_SLOT_COUNT` minus `DQ_DD_PRIORITY_RESERVED`
(2 by default), so test/bench-infrastructure work other agents are waiting on
doesn't queue behind the general pool. Use it for exactly that kind of
work, not routinely.

Juke options take `=`: write `--scenario=a,b`, not `--scenario a,b`.

| Scenario | Measures | Options (`--arg=name=value`) |
|---|---|---|
| `boot_memory` (default) | Process and Rust heap memory after boot, gas mixtures, live instances by kind and top types, compiled type counts, init time. | `top` |
| `idle` (default) | Tick cost of a quiet round: average and p95/p99/max tick usage, overruns, TPS and per-subsystem cost. A pure wait (no synthetic input), so it compares like for like across builds. | `seconds` (60) |
| `input` (default) | Input latency on a quiet round from a synthetic load of real clicks and queued verbs every tick (`input_p99`, click and verb waits). | `seconds` (30), `clicks` (2), `verbs` (2) |
| `atmos_idle` | Atmos cost of the mapped station at rest, with Rust worker maxima. | `cycles` (120) |
| `atmos_large` | Checkerboard gas equalization on a fresh floor. | `size` (48; 0 = whole level), `cycles` |
| `major_events` | Explosion, supermatter, mass fire and decompression on fresh fixtures. | `events` (comma list) |
| `generation` | Expedition station generation and release; `cycles` > 1 is a leak soak. | `cycles`, `seed` |
| `sm_soak` | Repeated supermatter-scale blasts plus five minutes of recovery. Use the full map. | `blasts` (4), `profile_types` |
| `kernel_overhead` | What the kernel measurement itself costs: a charge, a tick usage read pair, a histogram add, and a closed tick with every registered system charged. | `calls` (200000) |
| `rustg_dispatch` | Per-call cost of rust-g `hash_string`, `json_is_valid` and `log_write` through a cached `load_ext()` handle against by-name `call_ext`. On 2026-09-23 (loaded machine, three boots) the handle showed no consistent gain, so `code/__defines/rust_g.dm` still calls by name. | `calls` (20000), `rounds` (5) |

**What gets recorded.** Each invocation is one file in `data/bench/runs/`
holding the commit, map, defines, every iteration's raw results (metrics,
subsystem breakdowns, the ticks that overran, memory at each phase, the full
memory time series) and a summary: median, spread, minimum and maximum of every
metric over the measured iterations. The world also reports subsystem
initialization times and runtimes. With `--profile`, BYOND proc profiles for
each measurement window go to `data/bench/profiles/<run>/`.

**Comparing.** `bench` compares itself against the stored baseline for this
branch's merge-base with master automatically (see "Shared store" above; it
falls back to the previous local run, with a warning, if no baseline is
stored yet). `bench-compare` does the same on demand (`--base=baseline`, the
default, or `--base=<run>` for anything else; `--head=`, `--threshold=`
percent, `--all` to list unchanged and not-comparable metrics too,
`--fail-on-regression` for scripts). A metric changes only when it moves by
more than both the threshold (5% by default, 1% for COUNT metrics) and twice
its run-to-run spread, so use `--runs=3` or more for anything you want to
trust — and remember TIMING metrics also need `loadSimilar()` load
conditions between the two runs, or they show as `not comparable (load)`
instead of a change.

**Kernel metrics (every scenario).** Whatever a scenario measures, `bench` also
reports these over its whole run (`code/modules/benchmarks/kernel_metrics.dm`),
so the same numbers exist everywhere and a change can be judged by the system it
moved:

| Metric | Meaning |
|---|---|
| `tick_p50`, `tick_p95`, `tick_p99`, `overruns`, `overrun_ratio` | Whole-tick usage (%) and the ticks over 100%. |
| `system.<id>.ms_per_s`, `.p99_ms`, `.late_max`, `.breaches` | Per system (OM behaviour families such as `life` and `machines`, and `mc_<subsystem>`): ms of work per second, p99 of ms per tick over the ticks it ran, worst slot lateness in deciseconds, and slots that started past their max interval. Ids are `code/controllers/measure/systems.dm` keys. |
| `input_p99`, `input_p99_ticks`, `input_p50`, `click_wait_p99_ms`, `verb_queue_p99_ms`, `input_queue_hwm`, `input_run_depth_p95` | How long clicks and queued verbs waited before being handled (ms and ticks), how deep the verb queue got, and how far into the tick input ran. |

`bench-compare` gates on these regardless of the generic threshold: `input_p99`
and every `.breaches` may not rise (beyond the runs' own noise, and beyond the
metric's resolution for input), and a system's `.p99_ms` rising over 20% is named.
A gated row reads `regression (gate: ...)`. The same records are in the stat
panel's Kernel view, the "Tick Report" admin verb (the flight recorder of the last
minute) and `om_diagnostics()["kernel"]`; each `bench` also keeps the per-tick
series of every scenario under `data/bench/profiles/<run>/`.

**Report.** `data/bench/report.html` is regenerated after every `bench`. It
shows the latest run against the previous one, a trend line per metric, the
memory timeline with scenario phases, the ticks that overran, and recent
unit-test runs. Open it in a browser; it needs no network.

**Writing a scenario.** Subtype `/datum/benchmark`, set `id` and `description`,
and implement `Run()`. The helpers are in `_benchmark.dm`:

| Helper | Use |
|---|---|
| `metric(name, value, unit, better, metric_class)` | A compared number; `better` is `"lower"`, `"higher"` or `"none"`. `metric_class` is `"timing"` (default) or `"count"` — see "Exclusive runs and load noise" above. |
| `count_metric(name, value, unit, better)` | Shorthand for `metric(..., metric_class = "count")`: use it for anything load-independent (a call count, a list length, a byte count), not a wall-clock or tick number. |
| `detail(name, value)` | Context that isn't compared (tables, lists). |
| `begin_window()` / `end_window(prefix)` | Tick usage, overruns, TPS and per-subsystem cost between the two calls. |
| `mark(name)` | Process and Rust heap memory at this moment. |
| `param(name, default)` | A `--arg=name=value` option. |
| `wait_for_assets()`, `wait_fires(SS, n)`, `wait_seconds(n)` | Settle before measuring. |
| `wait_seconds_with_input(n, clicks, verbs)` | `wait_seconds()` that also sends real synthetic clicks and queued verbs every tick, for scenarios that should report input latency. |
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
| Code and map grep checks (the engine's `check_grep` lint) | `bash tools/ci/check_grep.sh` |
| Committed test focus | `bash tools/ci/check_misc.sh` |
| Every rewrite lint (ratchets, ALLOW annotations, deadline polling, ...; `tools/analyze`) | `bash tools/ci/check_ratchets.sh` or `tools/build/build.sh analyze` |
| The engine's own tests (per-lint fixtures) | `cargo test --manifest-path tools/analyze/Cargo.toml` |
| Changelog stubs parse | `bash tools/ci/check_changelogs.sh` (compiles stubs; run on a scratch copy) |
| Local `#define`s are `#undef`'d | `tools/bootstrap/python -m define_sanity.check` |
| Maps are in TGM format and merge-clean | `tools/bootstrap/python -m mapmerge2.dmm_test` |
| Map lint rules (`tools/maplint/lints/`) | `tools/bootstrap/python -m tools.maplint.source` |
| Every `.dmi` parses | `tools/bootstrap/python -m dmi.test` |
| Rust format, lint and tests | `cd verdigris && cargo fmt --package verdigris --check && cargo clippy --package verdigris --all-targets -- -D warnings && cargo test --package verdigris` |

`check_grep.sh` no longer needs ripgrep: its checks run inside the analyze engine
(PCRE-style patterns included), so every part always runs.

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
