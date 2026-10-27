# AGENTS.md — Working on DeepQuarry

DeepQuarry is a BYOND/DM Space Station 13 codebase. Lineage:

```
Baystation12 → Polaris → VOREStation (Virgo) → Yawn-wider → CHOMPStation2 → DeepQuarry
```

It is a **hard fork**: no upstream is tracked or merged. There are no edit markers
(`// CHOMPEdit`, `// DQEdit`, ...) and no modular folders; a stray one is a leftover, so
treat it as ordinary code and remove it when you touch the file. Edit or delete any file
freely. When you remove a file, delete it; the build regenerates `deepquarry.dme` (§2); git history is the record.

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
| `deepquarry.dme` | Compile manifest, generated from the files on disk (§2). Committed; never edited by hand. |
| `SpacemanDMM.toml`, `code/__odlint.dm`, `code/__pragmas.dm` | DreamChecker config. |

## 2. Wiring files into the build

`deepquarry.dme` is generated: `tools/build/gen_dme.py` includes every `.dm` under the scanned roots (`code/`, `interface/`, the
`maps/common*` trees) in path order, with the few rules that order genuinely depends on in `tools/build/dme_spec.txt` (macro files
first, a file that redefines another's type var or proc after it, the test trees and generated files last; each rule says why).
Add, move or delete a file and build (every target that compiles or lints DM regenerates the manifest), or run
`python3 tools/build/gen_dme.py`; commit the result. `bash tools/ci/check_ratchets.sh` fails on a stale manifest and on a macro used
before its `#define` in the generated order. A new order dependency (a macro in an ordinary file, a second definition of a type's var
or proc in another file) needs a `before` rule; `bash tools/ci/dme_order_equiv.sh` compiles a reference order against the generated
one and compares the worlds with dmb-equiv. Test files are listed in `code/modules/unit_tests/_unit_tests.dm` (still by hand).

---

## 3. Writing code: the migration

The approved design is `doc/rewrite/final_api.html` ("the doc"). It replaces the object model
(OM), the `sys` layer, interactions and every legacy declaration form. Section numbers below
are the doc's. Section 17 maps **every** old form to its replacement.

**The rule: write what exists on master today.** Most of the doc's forms are on master now (doc §19
"Where master stands"); a few are still open.

- Where a replacement has landed, write it. Where it has not, the legacy form is what you write.
  Don't stub, fake or invent a new form; `git grep` for its definition first. A form marked
  **new** below is not usable yet.
- A legacy form becomes banned only when its replacement has landed **and** its lint is
  switched on as a hard ban. The commit that does that also converts the callers. Until then
  the form is not deprecated for you.
- What binds today: the "hold under both" rules in §3a and every ratchet that is already on
  (§3d). A ratchet with a baseline rejects a new site of what it counts. If your change needs
  a site a live ratchet rejects, don't annotate it or touch the baseline; report it, because
  the replacement has to land first.

### 3a. Target forms (the design's end state)

"On master" says whether you can write the form now. Most rows are on master; the ones marked
**new** are not, so write the form in the last column until they land. `git grep` a form's
definition before using it.

| Need | Target form | Doc | On master | Write today |
|---|---|---|---|---|
| Declare a type | One inheriting block: `CAPABILITIES(T)` and indented entries | §1 | yes (the table procs are hard-banned) | `CAPABILITIES(T)` |
| Reusable behaviour | A capability (`cover()`, `powered()`) or a plain proc returning entries; one type groups its own entries with `section(name, "doc")` in its block (no `BUNDLE`) | §11 | yes | `CAPABILITIES`, `section()`; shared capabilities in `code/library/` and `code/datums/capabilities/` |
| Player/AI/admin choice | `op(key, name, parts...)`: input, select, `needs()`, `wait()`, `then()` | §9 | yes (interactions, the task engine, `DECLARE_INTERACTIONS`, `om_ask` are gone and banned) | `op(...)`; a window button is `op(key, ui_act(key, arg(...)), needs(...), asks(...), then(...))` |
| Refusals | A requirement returns null to allow or a reason; never a boolean, never side effects | §9 | `needs()` yes (the `REQ_*` predicate macros are gone and banned) | `needs(...)` with a native `req_*` part; a refusal that depends on what an `asks()` step was answered with is `req_answer(PROC_REF(x), step = "name")` (`x(A)` reads `A.step_value("name")`, holds while unanswered, asked again at commit) |
| Mouse and click input | One path: only `code/engine/kernel/entry.dm` overrides BYOND's `Click`/`DblClick`/`MouseDrop`/`MouseDrag`/`MouseDown`/`MouseUp`/`MouseEntered`/`MouseExited`/`MouseWheel` (it reads `usr` once, builds a typed `/datum/input_event`, calls `input_submit()`); the resolver finds the type's declared entry when the event resolves, on the spot or from the inbox | §2 | yes (the `mouse_override` lint hard-bans any other definition, generated code included) | `click_on(PROC_REF(x))`, `double_click_on()`, `drag_onto(PROC_REF(x), onto =)`, `drag_over()`, `hover()`, `tooltip()` in `CAPABILITIES`, handler `x(datum/act/input/A)` (`A.actor`, `A.over`, `A.entered`, `A.params`); `INPUT_FALLTHROUGH` sends the input on to its default handling; a subtype re-declaring the form replaces its parent's entry, so override the parent's handler proc and call `..()` to extend it |
| Typed world events | `/datum/act` contexts from `ACTION()`; refuse, take over or modify with `extend(/datum/act/x, needs(...))`, `instead(...)`, `adjusts(...)` under `ACT_ATTEMPT` (`intercept()` is retired) | §8, §10 | yes (all of them) | `ACTION()`, `ACT_ATTEMPT` with `act_done`/`act_cancel`, hooks in `CAPABILITIES` (`DAMAGE_REACTION`, `OM_EMIT`, `om_hook` are banned) |
| React after | `on_notice(/datum/notice/x, ...)`, `PUBLISH()` | §10 | yes (notices come from `ACTION()`; master's `NOTICE()` is an unrelated log macro) | `on_notice()`, `PUBLISH()` |
| React to a state key | `on_change(nameof(v), ...)` | §7, §10 | yes | `on_change()` |
| State | `TRACKED(T, var)` (two arguments); writes through setters; reads generated by the build | §4, §7 | yes (`OM_FIELD` and `changed()` channels are banned) | `TRACKED`, tracked setters; reads in `code/_generated/reads.dm` |
| Numbers/flags composed from sources | `STAT(...)`, `contributes(...)`, `hold(E, stat, value, source, lasts =)`, `hold_table()`, `release()`, `grant()`/`revoke()` | §5 | yes (`code/engine/stats/`, `grant()` in `code/engine/declare/activation.dm`); the `stat(...)` entry form in `CAPABILITIES` is **new** | `STAT` with a var of its own, `hold()`/`hold_table()`/`release()`/`grant()`; a source type's table is `factors(...)` in its CAPABILITIES block, held on the entity its relation names at a tracked scale (converted families are listed under `factors_converted` in `tools/ci/lint_scopes.toml`, where a raw `factors =` var is banned; a `factors = alist(...)` data var on a flyweight or prototype read by the type's one entry stays, stat_layer.md §8); a body factor is a `STAT` on `/mob/living` (`code/contracts/ids/body_stats.dm`) read as a var (`L.slowdown`); `BF_*` and `factor(` are banned |
| Delays and repeats | `after(owner, delay, then(...))`, `every(...)`, `after_init(delay, parts...)`, `STAMP`/`ELAPSED`, `COOLDOWN_*`, `wait()` on an op | §3 | `after()`, `every()`, `after_init()`, `COOLDOWN_*`, `wait()`/`then()`, `STAMP`/`ELAPSED` yes (`STAMP(D, var, clock)` records now in a var, `ELAPSED(D, var, clock)` reads it; `EXPIRY_STAMP`, `STAMP_ELAPSED`, `STAMP_AT`, `STAMP_POINT`, `STAMPED`, `STAMP_CLEAR`, `ELAPSED_SINCE` and `BEFORE` are gone and banned) | `after()`, `every()`, `after_init()`, `COOLDOWN_*`, `STAMP`/`ELAPSED` for a var; a time per row (a failure cache, a flow field, a respawn wait) is a small `/datum` record the holder owns with `owns_many()`/`owns_one()`, its var stamped with `STAMP` and read with `ELAPSED` (an end time is a `COOLDOWN_DECLARE` var: `COOLDOWN_START`/`COOLDOWN_EXTEND`/`COOLDOWN_RESET`, read with `COOLDOWN_RUNNING`/`COOLDOWN_LAPSED` (the strict pair) or `COOLDOWN_FINISHED`/`COOLDOWN_TIMELEFT`, and the `_OWN` family for a deadline on the datum's own clock; the `EXPIRY_DECLARE`/`SET`/`EXTEND`/`CLEAR`/`ACTIVE`/`EXPIRED`/`LEFT`/`ON_LAPSE` forms are gone and banned, and a start-time var is a plain var; `TIME_NOW(clock, owner)` is the one clock read the `STAMP`/`ELAPSED`/`COOLDOWN_*` macros are built on, and a payload or list slot that records "now" calls it directly; a data key (an ability id) is `COOLDOWN_KEYED_DECLARE`/`_START`/`_FINISHED`; `EXPIRY_AT`/`EXPIRY_NOW` are gone). A base type (`/atom`, `/mob`) holds no var: it declares `stamps(a)` in its block and writes the lazy table it shares with `cooldown_*`, as `COOLDOWN_*` is to `cooldown_*`: `stamp_now(D, a, clock)`, `stamp_elapsed(D, a, clock)`, `stamp_set`, `stamp_point`, `stamp_has`, `stamp_clear` (`code/__defines/engine/sparse_slots.dm`) |
| Instance values from place or params, phase 0, discard | `preset(nameof(v), PROC_REF(x), from =, when =)` (a value computed from the instance's own place or params at the root, before any code after `..()`; the generator reads, never writes; a claim on a resource stays a `setup()` effect); `param(..., apply = PROC_REF(x), early = TRUE)` (the setter runs in phase 0, after the early children and before the chain: only for a setter the chain reads, e.g. the human's species); `keeps_if(cond, warn =, instead = PROC_REF(x))` (`instead` runs once when the instance is discarded); an object that needs a body to copy takes it as a param (`make(/mob/observer/dead, at = T, from_body = M)`, no positional constructor argument) | init_phase0 N1-N3, D5 | yes (`code/engine/lifeforms/preset.dm`, `params.dm`, `keeps_if.dm`; `init_roots` in `tools/ci/lint_scopes.toml` is the closed list of the types that are the `Initialize()` chain: `/atom`, `/atom/movable`, `/obj`, `/turf`, `/datum/controller/global_vars`, adding one is a design change; there is no `preinit()`) | `preset()`, `param(early = TRUE)`, `keeps_if(instead =)`; a boot-time datum (persistent, asset transport, techweb node, instrument) has no `Initialize()`: its loader's system runs the boot step |
| Links and ownership | Relations declared in `CAPABILITIES`; lifecycle declared | §6 | yes (`OWN`/`REL`, `own_set` and the `relations()`/`ownership()` procs are banned) | `ref_one()`/`ref_many()`/`links()`/`owns_one()`/`owns_many()` in the block |
| World-level state/work | `SYSTEM_DEF(x)` plus `/datum/system/x` with `needs`, `lane`, `every()`; other folders call only its `api.dm` | §2 | yes (`world_service` is gone) | `SYSTEM_DEF(x)` |
| Construction ladders | `construction(start(...), step(...), dismantle(...))` | §12 | yes (`code/engine/declare/graph.dm`) | `construction(...)` |
| Database and HTTP reads | A `/datum/io/sql` request, or a read that carries on in its callback | §2 | yes (`prompt_flow()`, `flow_select()`, `flow_sql()`, `flow_http_get()` are gone and banned) | `sql_ask(owner, sql, params, PROC_REF(next), context...)` + `sql_answer_rows()`, `http_ask()`, `sql_write()` for a write nobody reads, `db_query_now()` only where BYOND itself waits |
| Appearance, UI, verbs, prompts | look parts, `ui_window()`/`ui_data(user)` outputs, granted verbs, `asks()` | §13 | look parts, `interface()`/`ui_data`, `ui_act`, `asks()`, granted verbs yes (`APPEARANCE_*` look forms, `update_icon(`, `DECLARE_UI`, `DECLARE_VERB` are banned); `flow_ask` is gone and banned) | `draw(datum/look/look)`, `interface("Window")` + `ui_data(datum/act/eval/A)`, `asks()` (a cancel that must still proceed: `optional = TRUE, default = v`); a tool that is not an op asks with an `ask_sequence` (`question_step()`, `ask_child()`) |

Rules that hold under both old and new forms:

- Effects never sleep. No `spawn`, gameplay `sleep`, `INVOKE_ASYNC`, `do_after`; waiting is a
  timer, a task or an await (a `wait()` part on an op).
- A refusal is a requirement, not a message-and-return at the head of an effect proc.
- Avoid `usr` outside verb procs; absolute type and proc paths only; `istype()` then cast, never `:`.
- Use defined constants, not string literals; time defines (`1.5 SECONDS`), never raw deciseconds.
- Pass procs with `PROC_REF()` / `TYPE_PROC_REF()` / `GLOBAL_PROC_REF()`.
- Don't override `Destroy()`; use `qdel()` and put consequences in `on_destroy(force)`. Never `del()`.
- Prefer `Initialize(mapload, ...)`; always chain `..()` in lifecycle overrides. An `Initialize()` override sets per-instance
  state only and carries `// ALLOW(init/INSTANCE_STATE|CTOR_ARGS|FRAMEWORK): <reason>`; starting contents are `starts =`
  (`owns_one`/`owns_many`/`slot`), capability setup is `on_holder_init(A)`, an Initialize() tail that needs `mapload` or returns `INITIALIZE_HINT_QDEL` is `setup(PROC_REF(x), mapload = TRUE)` (`x(mapload)` returns the hint), an Initialize() head (code that ran before `..()`) is `setup(PROC_REF(x), early = TRUE)`, work after the map load or a timer from init is
  `after_init(delay, then(PROC_REF(x)))` in `CAPABILITIES`. `LateInitialize()` and `INITIALIZE_HINT_LATELOAD` are gone.
- Tracking is automatic: don't declare `TRACKED(...)` (hard-banned outside the generated file). Write a var that reactive code reads through its generated `set_v(...)`; the `tracked` lint (hard error) rejects a raw write and `analyze fix --apply` rewrites it. A setter with side effects is a hand-written `set_v()` plus `SETTER(T, v)`. Construction (`Initialize()`/`New()` writing the instance's own var) is not a change and stays raw.
- Lists: constant shared tables are `var/static/list`; per-instance mutable lists are lazylists
  (`LAZYADD`/`LAZYLEN`), not `var/list/foo = list()` (`code/__defines/_lists.dm`).
  A `TRACKED` list var is mutated through its generated `add_<v>()`, `include_<v>()`, `remove_<v>()`, `set_<v>_at()`, `clear_<v>()`,
  `insert_<v>()`, `swap_<v>()`, `cut_<v>()` (`tracked_lists.dm`); `analyze fix` rewrites `LAZYADD`, `.Add()`, `v[i] = x` and the rest.
- Sounds are sets: `play_sfx(atom, SFX_ID)`; sparks are `fx_sparks(atom, amount)`.
- SQL is parameterized only; ask players with typed prompts, not raw `input()`/`alert()`.
- Cache appearances, not raw `/icon`. Don't add an `/atom` proc for something only one capability uses.
- Run DreamChecker before pushing.

### 3b. Legacy forms (what is left)

Most of the old layer is gone and hard-banned (`[lint.legacy_forms.lists] banned` in
`tools/ci/lint_scopes.toml`, baseline empty): `om_after`, `om_hook`, `om_ask`, `om_grant`, `OM_EMIT`,
`OM_FIELD` and its relatives, `TOPIC_ACTION`, `DECLARE_PERIODIC_WHILE`, `DECLARE_REPEAT`,
`DECLARE_VERB`, `DECLARE_EMAG`, `DECLARE_UI`, `DECLARE_INTERACTIONS` and interactions, the task
engine, `DAMAGE_REACTION`, the `OWN`/`REL` macros, the `relations()`/`ownership()`/`capabilities()`
table procs, `world_service`, `PERIODIC_*`, `update_icon(`, the `APPEARANCE_*` look forms and the
`CHANGE_*` channels outside the engine. Don't write them; the lint rejects them.

What is still open, and still correct to write where a file already uses it:

- The `BF_*` body factors themselves are done: they are stats on `/mob/living`. A `factors = alist(...)` var on a flyweight or prototype (a body effect, affliction, reagent, trait, perk or form type) is final data read by its type's one reader, not open work (`doc/rewrite/proposals/stat_layer.md` §8, end); `factors_converted` is only for types that move the table into the entry itself.
- `prompt_flow()`, `flow_select()`, `flow_sql()`, `flow_http_get()` (database and HTTP reads that re-ran their entry) are gone and hard-banned: a read that carries on from its answer is `sql_ask(owner, sql, params, PROC_REF(next), context...)` with `sql_answer_rows()` in the callback, an HTTP read is `http_ask()`, a typed read is a `/datum/io/sql` request, a write nobody reads is `sql_write()`. `rerun_ask`, `verb_ask`, `client_ask`, `cast_ask` and `flow_ask` are gone and hard-banned: an admin verb asks with `ask_steps()`, a spell with `target_questions()`, an admin tool with `ask_admin()` and its pickers (`code/modules/admin/view_variables/pickers.dm`).
- The init, `base_vars` and raw-overlay ratchets (baselines shrink as files convert).
- File moves into the new tree (§3c).

Run `bash tools/ci/legacy_form_counts.sh` for the current census. If you touch a file that still
uses an open form, leave it in place unless you are converting that file in a wave (§3c). The docs
under `doc/rewrite/archive/` describe the old forms; they are history now, not a guide to master.

The old `/datum/req` flyweights (`req.dm`, `op_ctx.dm`, `/datum/requirement`, `requirement_composer()`) are retired and hard-banned (`legacy_forms`): a requirement is a native
`/datum/entry/part/req` (`req_empty_hand()`, `req_access()`, `req_stance()`, ... in `code/library/requirements/`); the design is `doc/rewrite/proposals/admission.md`. The
condition-tree combinators `cond_not`/`cond_all`/`cond_any` are gone too (hard-banned): `not()`, `all_of()` and `any_of()` take conditions (a var name,
a stat id, a `PROC_REF`) as well as requirements and build the same tree.

Corrections to older notes: there is no `om_changed()`, `changed()` channels or `om_raise_change()`
any more; state is tracked setters and generated reads. `SSbehaviours` no longer fires; its work
was folded into the kernel (`code/controllers/kernel/kernel.dm`).

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

A hot per-tick base var that must stay on its base type is a `"<type>/<var>" = "<justification>"` row in `[lint.base_vars.tables.base_var_home_hot]` of `tools/ci/lint_scopes.toml` (the justification names the .dm file and proc that read it every tick, move or turf update; the `base_vars` lint fails a row whose var is gone or whose justification is under 40 characters).

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

- **Native compiler (default).** `build.sh dm`, `dm-test`, `dq_focused_test.sh`, the merge gates and `dq_lane_ready.sh` compile with
  the in-tree Rust compiler `tools/dmb` through a resident daemon; the targets build `dmbc` first (cargo machine slot, skipped when
  current). `DQ_COMPILER=dreammaker` (alias `byond`) is the other compiler. A native compiler failure fails the build: the automatic
  DreamMaker fallback on a native internal error is opt-in (`DQ_COMPILER_FALLBACK=1`), so no gate passes on DreamMaker's output by accident. And `DQ_COMPILER=shadow` compares the two. **CI compiles with the native compiler too**
  (`tools/ci/compile_and_run.sh`, the benchmark workflow; `DQ_COMPILER=dreammaker` still selects DreamMaker), and a DreamMaker cross-check job
  (`dreammaker_cross_check` in `run_compile_checks.yml`, part of the completion gate) runs `bash tools/ci/dm_equiv.sh`: it compiles the production
  dme and the unit-test dme both ways and runs `dmb-equiv` (every difference listed). 2026-10-22 the production dme reports zero differences, including the order the global initializers run in; the unit-test dme reports one open
  cause (an untyped receiver naming a member declared on several types, `doc/rewrite/native_compiler_issues.md`). Without cargo or a `dmbc` binary an unset `DQ_COMPILER` fails the build instead of falling back to DreamMaker (set `DQ_COMPILER=dreammaker` on purpose). The local land/merge/push gates no longer run a DreamMaker compile; the CI cross-check above is the DreamMaker check. See
  `doc/testing.md` "Native compiler (incremental)" and `doc/rewrite/native_compiler_issues.md`.
- **One shared dmbc daemon per compiler version.** Every native compile uses the one shared compiler binary
  (`tools/build/lib/dmbc_cache.ts`), so every worktree talks to the same daemon (`tools/build/lib/dmbc_daemons.ts`), which keeps one
  retained session per project root and bounds them itself (`DMB_DAEMON_MEMORY_BUDGET_GB`, least recently used evicted,
  `DMB_DAEMON_IDLE_EXIT_SECS` idle exit). Daemons never replace each other: the endpoint is keyed by the compiler image, and a
  development build (a binary not under `<bin>/v/<current>`) gets a private namespace from dmbc. The old per-worktree namespace
  default is gone. Only a `DMB_DAEMON_NAMESPACE` you set yourself isolates a caller (a benchmark or experiment build); such
  namespaces are registered under `DQ_DMBC_DAEMON_DIR`, and `DQ_DMBC_MAX_DAEMONS` (default 2, `0` = off) caps only those: starting a
  compile asks the least recently used ones with no live compile and idle over 10 minutes to retire (`dmbc --daemon-retire`, which
  drains builds first). Never kill a daemon process by hand; an evicted session just pays one full compile.
  **Sessions share their values in memory.** One daemon-wide store (`tools/dmb/crates/dmbc/src/shared_store.rs`) holds the decoded memo
  records and the artifact cores that every `PublicationStore` uses, content-keyed and validated by each consumer against its own inputs, so
  a second worktree session or the test variant claims what the first one built instead of decoding a private copy. `DMB_SHARED_STORE=0`
  turns it off, `DMB_SHARED_STORE_PRIVATE=<names>` keeps named owners private (bisection), `DMB_MEM_MARKS=1` logs what it holds. Design,
  measurements and the rule for adding an owner: `tools/dmb/doc/retained_frontend.md` "Shared store".
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
- **Lanes get worktrees from the pool, nowhere else.** `bash tools/dq_lane_pool.sh lease <branch>` hands out one of
  `DQ_LANE_POOL_SIZE` (3) fixed worktrees, `E:/projects/dq-wt/pool-N`, started on `origin/master` with `git switch -c` (it refuses a
  dirty slot and never discards anything); a lane beyond the pool size is refused ("POOL FULL"). To wait for a slot, run
  `... lease <branch> --wait` once in the background (a first-come-first-served queue); never write a retry or `until` loop. `... release <branch>` retires the dmbc
  daemon, deletes the build outputs and detaches the slot at `origin/master`, keeping `icons/gen`, `node_modules` links, the analyzer
  binary and `data/analyze-cache` warm; a merged lane's slot is also reclaimed by the next lease. Do not `git worktree add` a lane
  worktree by hand and do not delete pool worktrees. The merge worktree (`merge-base`) is separate and permanent.
  Worktrees and caches live on E: only: worktrees under `E:/projects/dq-wt/`, build caches under `E:/dq-cache/`; never on `D:` or `C:`.
  Details and the gate flow: `doc/rewrite/agent_workflow.md` sections 19-23.
- **Disk hygiene.** Nothing a build, compile or probe writes may live in `.git`: compiler caches go to `E:/dq-cache/` (the native
  compiler's `DM_COMPILER_CACHE_ROOT`; never `<git-common-dir>/dm-compiled-cache`), and `tools/dq_push_stamp.sh` runs its
  `git merge-tree --write-tree` probes in a throwaway object dir so they leave no loose trees. Lane worktrees come from the pool:
  `bash tools/dq_worktree.sh lease <branch>` / `release <branch>` (the entry point of `tools/dq_lane_pool.sh`, at most 3 lanes at once);
  `dq_worktree.sh new` is only for non-lane worktrees and refuses past 8 worktrees or under 60 GB free on E:. `tools/dq_push_master.sh` runs
  `bash tools/dq_worktree.sh gc` after a successful push (removes clean non-pool worktrees merged into origin/master (`pool-N` slots are never removed), build targets deleted
  first, `DQ_WT_KEEP="a b"` protects names); run it by hand any time. Remove your own worktree when your lane is merged.
- **Disk use is bounded by construction.** `tools/ci/disk_budget.toml` lists EVERY directory under `E:/dq-cache` and every per-worktree growth dir
  (`data/test-runs`, `merge-gates`, `merge-batch`, `bench`, test-world logs in the checkout root, worktree-local cargo targets, ...) with a size cap,
  an age cap and an eviction policy, plus a whole-cache total (`DQ_CACHE_BUDGET_GB`, default 60). `bash tools/dq_disk_budget.sh enforce` applies it
  (least recently modified first; never a unit modified in the last 30 min, a leased slot's own cargo target, the `dmb-bin/current` version or a file
  a running process holds open; stat listings, never `du`; `--dry-run`, `status`). It runs at every lease, release, train cycle start and dmbc daemon
  start (throttled to once per 10 min). A directory under `E:/dq-cache` that the manifest does not name is unknown: it is reported, and removed once idle only when clearly a cache
  (`*.log`, `dmb-*`, ...); `train`, `lane-pool`, `slots`, `dmb-bin`, `flakes.tsv` are never removed. A file git tracks is never deleted in a worktree. Add the
  `[cache.<name>]` table first. Below `DQ_DISK_FLOOR_GB` (default 50) free on E:, caps are halved, and if it is still under the floor `lease` (exit 6)
  and the train's heavy cycles refuse to start with a REFUSED message instead of filling the disk. Never delete under `E:/dq-cache` by hand.
  `tools/ci/test_disk_budget.sh` (part of `check_ratchets.sh`) proves eviction, protection, unknown-dir removal and the floor.
- **Stuck lanes and waiting.** `bash tools/dq_lane_pool.sh stuck` lists leases with no live process and no activity for 30 min (exit 1 if any; `status` flags them, with
  idle time and machine-slot waits). A dirty or unpushed one is only reported, never wiped; a clean pushed one is reclaimed. `... cancel <branch>` withdraws a queued
  `lease --wait`. A full suite takes at most `DQ_SLOTS_SUITE_MAX_WORLDS` test worlds (default 1 while others wait) so focused runs are not starved.
- **Everything important lives in the repo; `E:/dq-cache` holds only disposable caches.** Never install a script, wrapper or config under
  `E:/dq-cache` (the old `E:/dq-cache/bin/dq_lane_pool` is gone for this reason): call `bash tools/dq_lane_pool.sh` from your worktree. It
  runs origin/master's copy when its own differs (extracted with `git archive` under `E:/dq-cache/lane-pool/self`), so any worktree's copy is safe.
- **Tests clean their scratch; caches are capped.** A Rust test that needs a store or scratch directory takes it from
  `tools/dmb/shared/test_scratch.rs` (`crate::test_scratch::root()` / `dir(label)`: a per-process `run-<pid>-<ms>` directory removed at process
  exit, pass or fail); never `create_dir_all` a path of your own under `E:/dq-cache` (`tools/ci/check_test_scratch.sh`, part of
  `check_ratchets.sh`, rejects it). Every file cache a daemon or tool writes needs a size cap and an age cap with eviction that actually runs
  (the dmbc file cache: `DMB_CACHE_BUDGET_GB` / `DMB_CACHE_MAX_AGE_DAYS`; published pair stores: `DMB_PAIR_BUDGET_GB` (8) /
  `DMB_PAIR_MAX_AGE_DAYS` (7), `PairStore::evict_to_budget`; the dmbc cache spares only its newest segment by age, so the budget holds); the
  manifest above lists every one, `tools/dq_cache_prune.sh` is now a wrapper for `dq_disk_budget.sh enforce`, and abandoned test-run directories idle for a day are
  its `test-scratch` table. Don't measure with `du`; count entries.
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
  that still tracks them. `deepquarry.dme` merges by its include sets (the `dq-dme` driver) and is regenerated after every merge;
  `_unit_tests.dm` merges by union (`.gitattributes`).
  `doc/rewrite/agent_workflow.md`. There are no look pins (deleted 2026-10-17; playtesting finds visual issues): don't add a snapshot
  of how types look; test a draw's behaviour instead (`dq_fresh_look_default`, `dq_human_draw_deterministic`, the staleness checker).
- Heed every DreamChecker warning. If another agent's unfinished work breaks the build,
  `DQ_WIP_TREE=1` lets test and bench builds skip dangling includes.
- **Shared build caches** (`doc/testing.md` "Shared build caches"): the analyzer binary is cached by source hash
  but built in each worktree's own target (never share a cargo target between worktrees), Bun lives in a shared
  per-version dir (`DQ_BUN_CACHE`), and any step over 60 s prints `still running: <step> (<elapsed>)` every
  minute; a silent long step is not a hang.
- **Machine-wide slots** (`tools/dq_machine_slots.sh`, `doc/rewrite/agent_workflow.md` section 10): at most 1 DM compile, 2
  test worlds and 1 cargo build at once on the machine (the machine is also the user's desktop), everything we start
  runs below normal priority (test worlds idle, `DQ_PRIORITY=normal` for neither), and the dmbc daemon keeps at most 8 GB of sessions and
  12 GB of RAM free (`DQ_SLOTS_DM_COMPILE`, `DQ_SLOTS_TEST_WORLD`,
  `DQ_SLOTS_CARGO`); a waiter prints who holds them, the merge worktree goes first, a crashed
  holder is reclaimed. `bash tools/dq_machine_slots.sh status` shows the table.
- **A lane lands only through the batch train** (`tools/dq_train.sh`, `doc/rewrite/agent_workflow.md` section 29): after its focused
  tests and `bash tools/ci/check_ratchets.sh --changed-only`, it runs `bash tools/dq_merge_master.sh`, then
  `bash tools/dq_train.sh enqueue --tests "<its tests>"` (`--light` for a change with no DM), and releases its slot. One integrator
  merges the ready lanes, runs one gate (test build only; CI keeps the production compile cross-check), pushes, and bisects to bounce
  only a culprit. `dq_land.sh` and `dq_lane_ready.sh` are retired (they refuse): per-lane proofs re-ran on every master move and took
  lanes hours. At most 3 general lanes run at once (`DQ_LANE_POOL_SIZE`): one DM compile slot serves about three lanes plus the train,
  and the train's dmbc session is kept resident (`DQ_DMBC_KEEP_ROOTS`) so its gate compiles stay incremental.

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
  `.../representative`; `dq_focused_test.sh` refuses an exhaustive test (or one with exhaustive subtypes) unless `--allow-exhaustive`,
  and names the `/representative` to run instead.
- **A focused or lane run compiles only the test build** (`deepquarry.test.dme`: the game plus `UNIT_TESTS` code, a superset), never `deepquarry.dme` as well; `dq_lane_ready.sh` runs the gates with `--no-dm`. The production compile + DreamChecker (`build.sh dm`, unchanged for explicit use) runs at integration (`dq_push_master.sh`, the batch train) and in CI.
- **Every focused run is capped.** Hard wall-clock limit `DQ_FOCUSED_MAX_MIN` (default 10, clamped to 10 without `--allow-exhaustive`; testing never runs past 10 minutes, and every agent shell has a hard 30-minute limit);
  at the cap, or when the run's shell dies or is killed, `tools/dq_run_guard.js` kills the run's own DreamDaemon worlds and frees
  their test-world slots. The cap counts run time, not time queued for a slot (reported as "queued N min"): never wrap the tool in
  `timeout`. A native compile refused with exit 75 (daemon capacity) queues again up to 30 min instead of failing. Never start a long run; test: `bash tools/ci/test_focused_caps.sh`.
- Lint: `tools/build/build.sh lint`. TGUI tests: `tools/build/build.sh tgui-test`. Rust:
  `cd verdigris && cargo test --package verdigris`.
- Flaky or caused by me: `tools/build/build.sh test-repeat --runs=5`, `test-baseline`.
- **Diagnose before re-running.** `dq_focused_test.sh` refuses the same arguments on the same tree twice in two hours (a pass
  reports the earlier result; a failure points at the log): read the log and the code first. `--rerun-failed` runs only what
  failed, `--force` runs the list anyway, and any edit lets a run through (`doc/rewrite/agent_workflow.md` section 12).
- Performance and memory: measure with `bin/bench.cmd` / `build.sh bench` then `bench-compare`;
  add scenarios under `code/modules/benchmarks/`, not one-off profiling. `--profile-tests`
  gives per-test proc profiles.
- `om_test_begin`/`om_test_end` are gone; use `kernel_test_begin()`/`kernel_test_end()`
  (`code/tests/driver/kernel_clock.dm`, doc §15). Never commit a `TEST_FOCUS(...)` line in `code/modules/unit_tests/dq_focus.dm`.

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

- [ ] `deepquarry.dme` regenerated and committed (the build does it; `check_ratchets.sh` checks it); new `.dm` test files in `_unit_tests.dm`.
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
  queues in the client's bounded inbox and drains in phase K, round-robin. There is one input path: BYOND's mouse procs are
  overridden only in `code/engine/kernel/entry.dm`, and an event's `resolve()` (the same code on the spot or from the inbox) runs the
  type's declared `click_on()`/`drag_onto()`/`hover()`/... entry through `input_dispatch()`, then the default handling. Nothing generates or
  hand-writes a native mouse override. Things that wait for an answer
  are requests (`open_request()`, `request_answer()`, `requests.dm`); long work that must yield is `job()`
  (`jobs.dm`); a call that may fail by design is `safe_call()` (`safe.dm`). A database or HTTP read whose answer the caller
  carries on from (a chain of reads, the login checks, a chat command) is `sql_ask()` / `http_ask()` with a callback on the owner and
  `sql_answer_rows()` for the rows (`code/engine/io/db.dm`); a typed read is a `/datum/io/sql` request. Tests make time pass with
  `test_driver_begin()` and `test_time()` (doc/testing.md "The kernel clock").
  BYOND's own callbacks (`atom/Click`, `DblClick`, `MouseWheel`, `MouseDrop`, `MouseEntered`, `MouseDown`, the client's mouse procs,
  `/datum/Topic`, `world.Reboot`) are in `code/engine/kernel/entry.dm`: each reads `usr` there once, builds the event with the actor, and
  handlers read the actor from the event (the hooks in `input_hooks.dm` take it as `src`).
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
  `injure()`, healing `mend()`, numeric mob stats are stats on `/mob/living` read as vars (`L.slowdown`).
  Read `doc/body_architecture.md`.
- **Declaration forms.** Master writes types as `CAPABILITIES(T)` blocks with `op()`, `needs()`, `after()`/`every()`,
  relations (`ref_one()`, `owns_many()`, `links()`), look parts (`draw(datum/look/look)`), `interface()`/`ui_data`
  and tracked setters with generated reads. §3b lists what is left.
- **Overmap and POIs.** The overmap subsystem compiles and is exercised by `virgo_minitest`;
  the live map does not use sectors. The dynamic overmap POI system and the ATC subsystem are
  deleted; restore from git only if asked.
- **Variants.** Subtypes that differ only in data are collapsed into one type plus a registry
  (`code/datums/variants/README.md`).
- **Loot and map resolvers.** A spawn table is a `loot(table = list(...), ...)` entry in the spawner's
  CAPABILITIES block (a pure table is an abstract `/loot/...` type with its own block; a subtype writes
  `configure(loot(...))`), rolled by `loot_spawn()`; a searchable pile names its table with
  `loot_search(table =)` and searches through an op (`code/library/loot/`). A load-time map atom declares
  `map_resolver(GLOBAL_PROC_REF(x), vars = list(...))`. These are static entries (`STATIC_ENTRY`): read
  without an instance, compiled once at world setup by the `static_entries` system
  (`code/engine/declare/static_entries.dm`), looked up with `loot_decl_for()` / `map_resolver_proc()`.
  `DECLARE_LOOT`, the `LOOT_*` rows, `MAP_RESOLVER` and `MAP_RESOLVER_VARS` are hard-banned. Don't add
  hand-rolled spawn code. Pins: `dq_loot_roll_pin`, `dq_loot_search_pin`, `dq_resolver_table_pin`,
  `dq_resolver_reader_pin` (`code/modules/unit_tests/snapshots/loot/`).
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
> on, and move a file into the new tree only when it is fully migrated. Commit the regenerated `deepquarry.dme`, run only the
> tests you touch, keep debug tracing, drop a changelog, and squash before merge.
