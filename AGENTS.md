# AGENTS.md — Working on DeepQuarry

DeepQuarry is a BYOND/DM Space Station 13 codebase. Lineage:

```
Baystation12 → Polaris → VOREStation (Virgo) → Yawn-wider → CHOMPStation2 → DeepQuarry
```

It is a **hard fork**: no upstream is tracked or merged. There are no edit markers
(`// CHOMPEdit`, `// DQEdit`, ...) and no modular folders; a stray one is a leftover, so
treat it as ordinary code and remove it when you touch the file. Edit or delete any file
freely. When you remove a file, delete it and its `#include` in `deepquarry.dme` (never
comment an include out); git history is the record.

**The codebase is mid-migration to the final design.** Read §3 before writing code; the short version is: write what exists on master today.

---

## 1. Repository layout

| Path | Purpose |
|---|---|
| `code/` | All DM code. Being reorganised into a new tree (§3c); the old directories are the remaining work. |
| `maps/` | `maps/southern_cross/` is the live map (station only: 3 decks, CentCom, Transit). `maps/virgo_minitest/` is the unit-test map (`-DCITESTING`). `maps/submaps/`, `maps/common*/`, `maps/overmap/`, `maps/~turfpacks/` hold dynamic content; `maps/expedition/` is the blank substrate the expedition generator carves. Other map dirs are dormant. |
| `icons/` | Edit `*.png` + `*.dmi.toml`; the build repacks into `icons/gen/`. Never hand-edit `icons/gen/`. |
| `sound/`, `interface/`, `html/`, `strings/` | Assets, skin, browser assets, lookup text. |
| `tgui/` | React/TypeScript front end (TypeScript only, Biome + Bun). |
| `verdigris/` | In-tree Rust extension (cave-gen, atmos, native kernel work) loaded over FFI. |
| `config/`, `SQL/` | Server config template, DB schema. |
| `doc/rewrite/` | The design. Start at `README.md`; the primary design is `final_api.html`. |
| `html/changelogs/` | One YAML stub per PR (§6). |
| `tools/`, `bin/` | Build, lint, map tooling, Windows entry points. |
| `deepquarry.dme` | Compile manifest. Every `.dm` is `#include`d here (§2). |
| `SpacemanDMM.toml`, `code/__odlint.dm`, `code/__pragmas.dm` | DreamChecker config. |

## 2. Wiring files into the build

DM has no auto-discovery. Add one line per file to `deepquarry.dme`, Windows separators:
`#include "code\modules\myfeature\myfile.dm"`. Keep `__defines/` includes near the top;
later definitions win in override chains. The design plans to generate the `.dme` from the
tree (defines, engine, library, domains, content, world); until that lands, edit it by hand.

---

## 3. Writing code: the migration

The approved design is `doc/rewrite/final_api.html` ("the doc"). It replaces the object model
(OM), the `sys` layer, interactions and every legacy declaration form. Section numbers below
are the doc's. Section 17 maps **every** old form to its replacement.

**The rule: write what exists on master today.** The doc's forms arrive in migration phases 1
and 2 (doc §19) and most are not on master yet.

- Until a form's replacement has landed, the legacy form is what you write. Don't stub, fake
  or invent a new form; `git grep` for its definition first. A form marked **new** below is
  not usable yet.
- A legacy form becomes banned only when its replacement has landed **and** its lint is
  switched on as a hard ban. The commit that does that also converts the callers. Until then
  the form is not deprecated for you.
- What binds today: the "hold under both" rules in §3a and every ratchet that is already on
  (§3d). A ratchet with a baseline rejects a new site of what it counts. If your change needs
  a site a live ratchet rejects, don't annotate it or touch the baseline; report it, because
  the replacement has to land first.

### 3a. Target forms (the design's end state)

"On master" says whether you can write the form now. Anything marked **new** does not exist
yet; write the legacy form in the last column until it does.

| Need | Target form | Doc | On master | Write today |
|---|---|---|---|---|
| Declare a type | One inheriting block: `CAPABILITIES(T)` and indented entries | §1 | **new** | `capabilities()`/`reactions()`/`relations()` table procs |
| Reusable behaviour | A capability (`cover()`, `powered()`) or a plain proc returning entries; one type groups its own entries with `section(name, "doc")` in its block (no `BUNDLE`) | §11 | **new** | library capabilities in `code/datums/capabilities/` |
| Player/AI/admin choice | `op(key, name, parts...)`: input, select, `needs()`, `wait()`, `then()` | §9 | **new** | `DECLARE_INTERACTIONS`, `om_ask`; a window button is already `op(key, ui_act(key, arg(...)), needs(...), asks(...), then(...))` |
| Refusals | A requirement returns null to allow or a reason; never a boolean, never side effects | §9 | **new** | `REQ_*`, `needs = PROC_REF(x)` |
| Typed world events | `/datum/act` contexts from `ACTION()`; `intercept()` | §8, §10 | **new** | `DAMAGE_REACTION`, `OM_EMIT` |
| React after | `on_notice(/datum/notice/x, ...)`, `PUBLISH()` | §10 | exists; typed `NOTICE()` is **new** (master's `NOTICE()` is an unrelated log macro) | `on_notice()`, `PUBLISH()` |
| React to a state key | `on_change(nameof(v), ...)` | §7, §10 | exists | `on_change()` |
| State | `TRACKED(T, var)` (two arguments); writes through setters; reads generated by the build | §4, §7 | `TRACKED` exists; generated reads **new** | `TRACKED`, `OM_FIELD` |
| Numbers/flags composed from sources | `stat(...)`, `contributes(...)`, `hold(E, stat, value, source, lasts =)`, `release()`, `grant()`/`revoke()` | §5 | **new** | `BF_*` body factors, `om_grant` |
| Delays and repeats | `after(owner, delay, then(...))`, `every(...)`, `after_init(delay, parts...)`, `STAMP`/`ELAPSED`, `COOLDOWN_*`, `wait()` on an op | §3 | `after()`, `every()`, `after_init()`, `COOLDOWN_*` exist; `STAMP`, `then()`, `wait()` **new** | `om_after`, `DECLARE_PERIODIC_WHILE`, `COOLDOWN_*` |
| Links and ownership | Relations declared in `CAPABILITIES`; lifecycle declared | §6 | **new** | `OWN`/`REL` macros, `own_set`/`rel_set` |
| World-level state/work | `SYSTEM_DEF(x)` plus `/datum/system/x` with `needs`, `lane`, `every()`; other folders call only its `api.dm` | §2 | **new** | `/datum/world_service`, world lanes |
| Construction ladders | `construction(start(...), step(...), dismantle(...))` | §12 | **new** | `code/datums/interactions/construction.dm` |
| Appearance, UI, verbs, prompts | look parts, `ui_window()`/`ui_data(user)` outputs, granted verbs, `asks()` | §13 | **new** | `APPEARANCE_*`, `DECLARE_VERB`, `om_ask`; a window is already `interface("Window")` + `ui_data(datum/act/eval/A)` |

Rules that hold under both old and new forms:

- Effects never sleep. No `spawn`, gameplay `sleep`, `INVOKE_ASYNC`, `do_after`; waiting is a
  timer, a task or an await (a `wait()` part once ops land).
- A refusal is a requirement, not a message-and-return at the head of an effect proc.
- Avoid `usr` outside verb procs; absolute type and proc paths only; `istype()` then cast, never `:`.
- Use defined constants, not string literals; time defines (`1.5 SECONDS`), never raw deciseconds.
- Pass procs with `PROC_REF()` / `TYPE_PROC_REF()` / `GLOBAL_PROC_REF()`.
- Don't override `Destroy()`; use `qdel()` and put consequences in `on_destroy(force)`. Never `del()`.
- Prefer `Initialize(mapload, ...)`; always chain `..()` in lifecycle overrides. An `Initialize()` override sets per-instance
  state only and carries `// ALLOW(init/INSTANCE_STATE|CTOR_ARGS|FRAMEWORK): <reason>`; starting contents are `starts =`
  (`owns_one`/`owns_many`/`slot`), capability setup is `on_holder_init(A)`, work after the map load or a timer from init is
  `after_init(delay, then(PROC_REF(x)))` in `CAPABILITIES`. `LateInitialize()` and `INITIALIZE_HINT_LATELOAD` are gone.
- Lists: constant shared tables are `var/static/list`; per-instance mutable lists are lazylists
  (`LAZYADD`/`LAZYLEN`), not `var/list/foo = list()` (`code/__defines/_lists.dm`).
- Sounds are sets: `play_sfx(atom, SFX_ID)`; sparks are `fx_sparks(atom, amount)`.
- SQL is parameterized only; ask players with typed prompts, not raw `input()`/`alert()`.
- Cache appearances, not raw `/icon`. Don't add an `/atom` proc for something only one capability uses.
- Run DreamChecker before pushing.

### 3b. Legacy forms (still what you write until replaced)

Everything built on the OM and the sys layer is legacy and will be removed: `om_after`,
`om_hook`, `om_ask`, `om_grant`, `OM_EMIT`, `OM_FIELD` and its relatives,
`TOPIC_ACTION`, `DECLARE_PERIODIC_WHILE`,
`DECLARE_REPEAT`, `DECLARE_VERB`, `DECLARE_EMAG`, `DAMAGE_REACTION`, `REQ_*`, the `OWN`/`REL`
macros, `capabilities()`/`reactions()`/`relations()` table procs, `PERIODIC_*` lanes,
`world_service` and the `CHANGE_*` channels with `changed(E, channel)`. They remain the correct
thing to write until the replacement in the §3a table lands. When it does, the same commit
converts the callers and switches on a lint that bans the legacy form (baseline empty, hard
ban); from that commit, don't write it. If you touch a file that still uses them, leave
existing uses in place unless you are converting that file in a wave (§3c). The docs under
`doc/rewrite/archive/` describe the old forms; they are still accurate for what is on master.

Corrections to older notes: there is no `om_changed()`; the real procs are `changed()` and
`om_raise_change()` (both legacy, replaced by tracked setters and generated reads). `SSbehaviours`
no longer fires; its work was folded into the kernel (`code/controllers/kernel/kernel.dm`).

### 3c. Source layout and the migration rule

Target tree (doc §22):

| Path | Holds |
|---|---|
| `code/engine/{kernel,time,state,stats,refs,change,actions,parts,hooks,present,io,_generated}` | The framework, one folder per doc section. `_generated` is build output, never hand-edited. |
| `code/library/` | Shared capabilities and bundles (machine, access, containers, reagents, items, structures, construction, providers, mobs). |
| `code/domains/{body,damage,atmos,power,life,ai,verdigris}` | Large systems with their own model. |
| `code/content/<domain>/` | Ordinary content: one type, one file (its capabilities, procs, messages, tests beside it). |
| `code/world/` | Systems, map glue, round flow. |
| `code/defines/` | Defines, split per module; replaces `__defines/`. |

Layering: engine may not reference library or content; library may not reference content;
nothing in the new tree may use an old form.

**A file moves into the new tree only when it is fully migrated** (zero old forms). The old
directories (`code/game`, `code/modules`, `code/datums`, ...) are the remaining-work list.
Each wave: convert the files, prove them (per-file ratchet, tests, construction round-trip,
bench), move them in a pure `git mv` commit with no edits, merge. Old APIs are deleted in the
commit their last caller goes. Plan, phases and gates: doc §19.

### 3d. Ratchets and justified keeps

`tools/ci/check_ratchets.sh` runs the rewrite lints, all in one process: the `analyze` engine
(`tools/analyze/`, see its README; `tools/ci/check_grep.sh` is its `check_grep` lint). It loads the
tree once and caches per file: about 17 s cold (the semantic model parse), under a second warm or after a one-file edit that leaves the declarations alone;
`analyze gen` returns at once when nothing it reads changed and parses the model once when declarations did. `analyze check --lint NAME`
runs one lint, `analyze check --changed-only` judges only the files you changed. A ratcheted lint's
`tools/ci/*_baseline.txt` lists legacy sites as fingerprints (rule, file, normalized line text). A
failure prints only **new** sites. After a sweep run `analyze baseline --update [--lint NAME]`: it
drops fixed sites and never adds one. Path exemptions, per-rule ceilings and named lists live in
`tools/ci/lint_scopes.toml`, not in the lints.

There are no allowlist files. A site that is right as it is carries an inline annotation, on
its line or a comment-only line above, with a required reason:

```dm
spawn(0) // ALLOW(scheduler): world.Export() is a blocking external call
```

Several lints go comma-separated; inside a multi-line macro use `/* ALLOW(x): reason */`.
The `allow_annotations` lint rejects a missing reason or unknown lint name, a reason under 20
characters or 3 words, "see above", allowlist talk and plan-phase labels, and (on a full run) an annotation no lint used: when its site stops triggering the lint, delete
it. Don't annotate new debt to get under a ceiling; use the form the lint points to. Unit tests, benchmarks and
the vendored TGS DMAPI are exempt by path from the lints whose `lint_scopes.toml` section lists them (instance_list,
ownership, silent_catch, spatial, lifecycle_counts, tracked, cache, scheduler, ...): don't annotate there.

The declared UI model (`DECLARE_UI`, `UI_ACT`, `UI_DATA`, `UI_SUBACT`, `act_ask`, `ui_act_allowed()`, ...) is deleted and hard-banned
(`[lint.legacy_forms.lists] banned`): a window is `interface()` in `CAPABILITIES`, its buttons are `op(..., ui_act(...))`, its data is
`ui_data(datum/act/eval/A)`, its questions are `asks()`. The old `dx_old_forms` sys rules were deleted because each named a replacement
that had not landed. The commit that lands a replacement adds its ban and converts the callers (§3b).

### 3e. Debugging and tracing

Never remove existing debug or AI tracing without explicit permission, and add thorough
logging when you add behaviour that is hard to observe.

---

## 4. Build pipeline

Windows is the supported dev OS. Entry points in `bin/`: `build.cmd` (DM + TGUI),
`server.cmd` (build and host on 1337), `test.cmd` (unit-test world), `tgui-build.cmd`,
`tgui-dev.cmd`, `tgui-fix.cmd`, `bench.cmd`, `clean.cmd`. `tools/build/build.ts` (Juke)
orchestrates; `tools/build/build.sh <target>` is the POSIX front end.
Always enter through `build.sh`/`build.bat`: they pin `DQ_BUILD_ROOT` to their own checkout and set
`BUN_RUNTIME_TRANSPILER_CACHE_PATH=0` (Bun's shared cache once built a sibling worktree);
`build.ts` refuses to run if its root differs from the invoking worktree's toplevel.

- **Icon repack** (`tools/dq_icons/`): `png` + `dmi.toml` into `icons/gen/`, dirty-checked.
  A fresh worktree seeds `icons/gen/` from the main checkout's copy (or `DQ_ICON_SEED`), so only
  changed icons repack. The repack pool is 4 workers (`DQ_ICON_WORKERS`), and the repack exits with
  its workers when the build that started it dies.
  Runtime DMI reads resolve the `icons/gen/` copy automatically.
- **verdigris** (`VerdigrisTarget`): builds `verdigris.dll` / `libverdigris.so` when source is
  stale; or run `verdigris/build-windows.sh` / `build-linux.sh`. It is a gitignored
  per-platform artifact; DM calls it through generated `vg_*` procs
  (`code/__defines/verdigris/_bindings.dm`, regenerate with
  `tools/build/build.sh verdigris-bindings`). If `cargo` is absent the build warns and skips
  it, and atmospherics and cave-gen then fail at runtime.
- **Worktrees: shared DLL cache.** VerdigrisTarget keeps a content-addressed cache of built
  libraries outside the worktrees (`DQ_VERDIGRIS_CACHE`, default `E:/dq-cache/verdigris`, else
  `~/.cache/dq/verdigris`; `off` disables it). The key is the git ids at `HEAD` of `verdigris/`
  plus the generated bindings and other Rust inputs, the target triple, profile and `RUSTFLAGS`.
  On a hit the build copies the DLL in and runs no cargo, so a fresh worktree needs no
  `verdigris/target`. A miss builds and stores it. Uncommitted changes to those inputs bypass
  the cache and build normally. The runner's `VERDIGRIS_ABI` check still applies. Do not copy
  another checkout's `verdigris.dll` by hand (`DQ_PREBUILT_VERDIGRIS=1`); a DLL built from other
  sources fails that check and loses every shard. If you do build Rust in a worktree, its
  target is about 1.3 GB: delete your own `verdigris/target` when you remove the worktree.
- **Worktrees and caches live on E: only.** Create worktrees only under `E:/projects/dq-wt/<name>`
  and build caches only under `E:/dq-cache/`; never on `D:` or `C:`. When E: runs low, prune
  merged worktrees: unlink their junctions first (e.g. `node_modules`), then
  `git worktree remove`, then `git worktree prune`.
- **Git safety.** Never delete `.git/index.lock` or any other lock file; another process holds
  it. Never run `git checkout` (any form), `git stash`, `git reset`, `git restore` or
  `git cherry-pick`; they discard or move other agents' work.
- **Production build:** `tools/build/build.sh dm` compiles without `UNIT_TESTS` (CI's Compile Checks job
  runs it). Test-only code (`code/tests/`, `code/modules/unit_tests/`) must stay behind
  `#if defined(UNIT_TESTS)`; generators do this via `sem::gen::test_only`, and `analyze gen`
  fails on a generated line naming a test-only type outside the guard.
- **Generated files are build output, not committed.** `code/engine/_generated/`, `code/_generated/reads.dm`
  and `tgui/packages/tgui/interfaces/generated/` are gitignored; every build target that compiles or lints DM
  (and `check_ratchets.sh`) runs `analyze gen` first (`tools/build/build.sh gen` by hand). Commit the
  declarations, never the output. Merge master with `bash tools/dq_merge_master.sh`; it settles a branch
  that still tracks them. `deepquarry.dme` and `_unit_tests.dm` merge by union. `doc/rewrite/agent_workflow.md`.
- Heed every DreamChecker warning. If another agent's unfinished work breaks the build,
  `DQ_WIP_TREE=1` lets test and bench builds skip dangling includes.
- **Shared build caches** (`doc/testing.md` "Shared build caches"): the analyzer binary is cached by source hash
  but built in each worktree's own target (never share a cargo target between worktrees), Bun lives in a shared
  per-version dir (`DQ_BUN_CACHE`), and any step over 60 s prints `still running: <step> (<elapsed>)` every
  minute; a silent long step is not a hang.
- **Machine-wide slots** (`tools/dq_machine_slots.sh`, `doc/rewrite/agent_workflow.md` section 10): at most 2 DM compiles, 3
  test worlds, 1 cargo build and 2 look-pin runs at once on the machine (`DQ_SLOTS_DM_COMPILE`, `DQ_SLOTS_TEST_WORLD`,
  `DQ_SLOTS_CARGO`, `DQ_SLOTS_LOOK_STATE_PIN`); a waiter prints who holds them, the merge worktree goes first, a crashed
  holder is reclaimed. `bash tools/dq_machine_slots.sh status` shows the table.
- **A finished lane runs `bash tools/dq_lane_ready.sh --tests "<its tests>"`** (section 11 of the same document): it merges
  master, proves the lane once and stamps it, so the merge agent tests only the combination.

### 4a. Testing (full reference: `doc/testing.md`)

- **While developing, run only the tests you touch:**
  `bash tools/dq_focused_test.sh /datum/unit_test/<name> [...]` (works from a worktree; the
  compile plus about 25 s). `--full-map` runs on Southern Cross. Every run fails when the world logged a
  runtime or a `WARNING()` before its first test (the boot gate, `doc/rewrite/boot_gate.md`; `--boot` checks
  boot alone).
- **Agents never run `tools/build/build.sh dm-test`:** it compiles AND runs the full sharded suite.
  Use `tools/dq_focused_test.sh` for every run. The full suite runs only at integration or when the
  user asks: `tools/build/build.sh dm-test` (normal tier, sharded; `--shards=1` for one world). CI and nightly add the exhaustive tier
  (`dm-test --tier=all`). Exhaustive tests are whole-type sweeps with a small normal-tier
  `.../representative`.
- Lint: `tools/build/build.sh lint`. TGUI tests: `tools/build/build.sh tgui-test`. Rust:
  `cd verdigris && cargo test --package verdigris`.
- Flaky or caused by me: `tools/build/build.sh test-repeat --runs=5`, `test-baseline`.
- **Diagnose before re-running.** `dq_focused_test.sh` refuses the same arguments on the same tree twice in two hours (a pass
  reports the earlier result; a failure points at the log): read the log and the code first. `--rerun-failed` runs only what
  failed, `--force` runs the list anyway, and any edit lets a run through (`doc/rewrite/agent_workflow.md` section 12).
- Performance and memory: measure with `bin/bench.cmd` / `build.sh bench` then `bench-compare`;
  add scenarios under `code/modules/benchmarks/`, not one-off profiling. `--profile-tests`
  gives per-test proc profiles.
- The design replaces `om_test_begin`/`om_test_end` with `kernel_test_begin()`/`kernel_test_end()`
  (**new**, doc §15). Never commit a `TEST_FOCUS(...)` line in `code/modules/unit_tests/dq_focus.dm`.

## 5. TGUI

`tgui/` is TypeScript-only with Biome and Bun. `bin/tgui-fix.cmd` auto-fixes;
`tools/build/build.sh lint` checks Biome and TypeScript. Interfaces live in
`tgui/packages/tgui/interfaces/`. A UI is an `interface()` in the type's `CAPABILITIES` block, a
`ui_data(datum/act/eval/A)` output and ops with `ui_act()`; each op keeps its old action name so TSX does
not change (doc §13, §19).

## 6. Changelogs

Every user-visible PR adds one `html/changelogs/<author>-<branch>.yml`:

```yaml
author: "yourkey"
delete-after: true
changes:
  - rscadd: "Added X"
```

Prefixes: `rscadd`, `rscdel`, `bugfix`, `qol`, `balance`, `soundadd`, `sounddel`, `imageadd`,
`imagedel`, `maptweak`, `spellcheck`, `experiment`, `refactor`, `code_imp`, `config`, `admin`,
`server`, `wip`. The nightly workflow rolls stubs into `html/changelogs/archive/`.

## 7. PR checklist

- [ ] New `.dm` files are in `deepquarry.dme`.
- [ ] Only forms that exist on master (§3a "On master"); no use of a legacy form whose ban lint is on (§3b).
- [ ] Absolute paths; no `:` subtype access; no `Destroy()`; time defines used.
- [ ] DreamChecker passes; `bash tools/ci/check_ratchets.sh` passes; any kept site has `// ALLOW(<lint>): <reason>`.
- [ ] Touched tests pass; `dq_focus.dm` is empty.
- [ ] TGUI, if changed: `tools/build/build.sh lint tgui-test` clean.
- [ ] One changelog stub; squash-able history; commit subject at most 72 characters.

## 8. Where to look

- `doc/rewrite/final_api.html`: the design (forms §1-§16, old to new §17, kept forms §18, migration §19, decisions §21, layout §22).
- `doc/rewrite/README.md`: index of the rest of the rewrite docs; `doc/rewrite/archive/`: old OM docs (history only).
- `doc/testing.md`, `doc/body_architecture.md`, `code/ATMOSPHERICS/README.md`, `verdigris/README.md`.
- Linter rules: `SpacemanDMM.toml`, `code/__odlint.dm`, `code/__pragmas.dm`. Icons: `tools/dq_icons/`. Changelog format: `html/changelogs/example.yml`.

---

## 9. Current state (deployment-independent)

- **Scheduling: one kernel, no Master Controller, no subsystems.** The `Kernel` global
  (`code/controllers/kernel/`) is the one loop. Each tick runs phases K S N U D P R G (host work and the
  input inbox, simulation sync, native frame, urgent, deadlines, lanes, presentation, garbage). What it hosts
  is `/datum/system`s declared with `SYSTEM_DEF(x)` (the `SSx` global): `needs`, `phase`, `roles`, and
  `every()` items in `reactions()`. A system's periodic handler is `x(dt)`, gated by
  `when = PROC_REF(work_ready)`; one that walks a list saves its cursor and returns `STEP_YIELD` when
  `KERNEL_OVER_BUDGET`. There is no `SUBSYSTEM_DEF`, `fire()`, `SS_*` flag, `Recover()` or `PreInit()` (a
  system's `preinit()` runs from `New()`). A new world-level periodic is a system.
- **Input, requests, jobs.** Every client entry point builds a typed `/datum/input_event` and calls
  `input_submit()` (`code/engine/kernel/inbox.dm`): it resolves on the spot while the tick has room, else
  queues in the client's bounded inbox and drains in phase K, round-robin. Things that wait for an answer
  are requests (`open_request()`, `request_answer()`, `requests.dm`); long work that must yield is `job()`
  (`jobs.dm`); a call that may fail by design is `safe_call()` (`safe.dm`). Tests make time pass with
  `test_driver_begin()` and `test_time()` (doc/testing.md "The kernel clock").
- **Atmospherics: LINDA on a Rust backend.** `code/ATMOSPHERICS/` is the only engine (ZAS/XGM
  are gone); gas math, diffusion, decompression and heat conduction run in the auxmos arena in
  Verdigris, driven from SSair's atmos step (phase N). `/datum/gas_mixture` is an opaque handle: read with
  `return_temperature()`/`return_volume()`, write with `set_temperature()`/`set_volume()`, and
  cache reads in hot loops (each call crosses the FFI). Atoms use `get_temperature()` /
  `add_heat()` (`code/modules/heat/heat.dm`). Requires BYOND 516.1682+. Gas reactions stay in
  DM. `xgm_compat.dm` and `tg_infra_compat.dm` are stable compatibility API, not temporary shims.
- **Expeditions and Flight Operations.** `GLOB.expedition_service` generates sites on demand
  (`load_new_z()`, cave automata or generated stations, POIs, loot, missions) and recycles
  z-levels; `GLOB.flight_service` owns vessels, destinations and flight plans. The old quarry
  mode is gone. Risks: `doc/generated_site_lifecycle_audit.md`.
- **Material science.** `code/modules/material_science/`: crucibles, alloys, composites,
  baths, coatings and exotic feedstocks; engineered materials change assembly behaviour.
  See `doc/material_engineering_implementation.md`. Lathe designs can set
  `material_selectable` for a material picker.
- **Damage.** Damageable `/obj` use the TG integrity model (`code/game/atom/atom_defense.dm`,
  `damage_packet.dm`): set `max_integrity`, route hits through `receive_damage()`/`take_damage()`.
  The old `health`/`maxhealth` model is gone. Final shape: doc §14.
- **Health.** Every `/mob/living` has a `/datum/body`; there are no health pools. Harm is
  `injure()`, healing `mend()`, numeric mob stats are `BF_*` body factors read with `L.factor()`.
  Read `doc/body_architecture.md`.
- **Overmap and POIs.** The overmap subsystem compiles and is exercised by `virgo_minitest`;
  the live map does not use sectors. The dynamic overmap POI system and the ATC subsystem are
  deleted; restore from git only if asked.
- **Variants.** Subtypes that differ only in data are collapsed into one type plus a registry
  (`code/datums/variants/README.md`).
- **Loot and map resolvers.** Spawn tables are `DECLARE_LOOT` rolled by `loot_spawn()`; load-time
  map atoms use `MAP_RESOLVER`. Both are slated to move under capability entries; don't add new
  hand-rolled spawn code in the meantime.
- **Server metrics and the admin viewer.** `GLOB.metrics_service` (`code/modules/metrics/`) samples
  every `/datum/metrics_source` every 10 s and flushes through `om_io` into the `metric_*` tables
  (`SQL/metrics_schema.sql`, `METRICS_ENABLED`). Events come from single framework points through
  `METRICS_EVENT()`; overruns are attributed to the tick meter's systems and to time outside the MC,
  and tick spikes capture a short profile. To measure something new, add a `/datum/metrics_source`;
  don't write metrics SQL elsewhere. `tools/admin-viewer/` (Bun + React) is the staff UI, opened with
  the signed-link **Admin Viewer** verbs; see its README.
- **Hardening already landed.** Parameterized SQL, panic-safe declared Verdigris binds, tgui
  Rules-of-Hooks/XSS fixes, and a falsifiable unit-test suite.

## TL;DR

> The codebase is mid-migration to the design in `doc/rewrite/final_api.html`. Write the forms
> that exist on master today (a legacy form stays correct until its replacement has landed and
> its lint is on; a form marked **new** is not usable yet), obey the ratchets that are already
> on, and move a file into the new tree only when it is fully migrated. Register every `.dm` in `deepquarry.dme`, run only the
> tests you touch, keep debug tracing, drop a changelog, and squash before merge.
