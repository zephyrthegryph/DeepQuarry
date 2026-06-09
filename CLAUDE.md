# CLAUDE.md — Working on DeepQuarry

DeepQuarry is a BYOND/DM Space Station 13 codebase. Its lineage is:

```
Baystation12 → Polaris → VOREStation (Virgo) → Yawn-wider → CHOMPStation2 → DeepQuarry
```

DeepQuarry is a **hard fork**: it no longer tracks or merges from any upstream.
The old merge-survival scaffolding **no longer applies** and has been removed:

- The modular folders (`modular_chomp/`, `modular_dq/`) were dissolved into one
  unified tree.
- The origin/edit markers (`// CHOMPEdit`, `// DQEdit`, `// CHOMPAdd`, `// DQRemoved:`,
  `// VOREStation Edit`, …) were stripped — they only existed to help a merge
  engineer locate fork edits, and there are no more merges.

Just put code where it belongs and **edit/delete any file freely**. When you remove
a file, delete it and drop its `#include` from `deepquarry.dme` — don't comment the
include out "in case." Git history is the record of what was removed.

> If you still find a stray `// CHOMPEdit` / `// DQEdit` / `modular_*` reference, it's
> a leftover; treat it as ordinary code/comment and remove it when you touch the file.

---

## 1. Repository layout

| Path | Purpose |
|---|---|
| `code/` | All DM game code (the entire codebase — base + everything the fork added). |
| `maps/` | Maps. The live map is `maps/deep_quarry/`. `maps/submaps/`, `maps/common*/`, `maps/overmap/`, `maps/~turfpacks/` hold dynamically-loaded submaps/turfpacks/overmap content. Other top-level map dirs are dormant upstream maps not in the build. |
| `icons/` | Art. Editable sources are `*.png` + `*.dmi.toml`; the build repacks them into `icons/gen/` (see §4). Never hand-edit files under `icons/gen/`. |
| `sound/`, `interface/`, `html/`, `strings/` | Assets, BYOND skin, browser assets, lookup text. |
| `tgui/` | React/TypeScript front-end (TypeScript only, Biome + Bun). |
| `verdigris/` | In-tree Rust extension (cave-gen + vendored auxmos atmos), loaded via FFI. Builds to `verdigris.dll` / `libverdigris.so` (see §4). |
| `config/`, `SQL/` | Server config template and DB schema. |
| `html/changelogs/` | One YAML changelog stub per PR (see §7). |
| `tools/`, `bin/` | Build/lint/map tooling and Windows entry points. |
| `deepquarry.dme` | The compile manifest — every `.dm` in the build is `#include`d here. |
| `SpacemanDMM.toml`, `code/__odlint.dm`, `code/__pragmas.dm` | DM linter / DreamChecker config. |

New code goes in the matching `code/` subfolder (mirrors the usual SS13 layout:
`code/modules/…`, `code/game/…`, `code/datums/…`, `code/__defines/…`). New art
goes in `icons/` as `png` + `dmi.toml`. New maps go in `maps/`.

---

## 2. Wiring new files into the build (`deepquarry.dme`)

DM has no auto-discovery — every `.dm` the compiler should see must be `#include`d
in `deepquarry.dme`. One line per file, Windows path separators:

```
#include "code\modules\myfeature\myfile.dm"
```

Order matters when files depend on `#define`s — keep `__defines/` includes near the
top. For proc/var override chains, the last-compiled definition wins; keep that in
mind when choosing where a file is included. Maps register through the glue in
`maps/~map_system/` (`_map_selection.dm`, `maps.dm`) — model new maps on those.

When you remove a feature, **delete the file and its `#include` outright** — there's
no upstream to merge against, so there's no reason to keep a disabled include around.

---

## 3. DM coding standards (enforced by SpacemanDMM / DreamChecker)

- **Absolute type/proc paths only** — `/obj/item/clothing/shoes/jackboots`, never
  relative. (`disallow_relative_type_definitions` / `disallow_relative_proc_definitions`.)
- **Use defined constants**, not string literals — job/faction/access/channel names,
  sounds. Defines live under `code/__defines/`.
- **Avoid `usr`** outside verb procs — plumb `user` through args, or use `src`.
- **Always chain `..()`** in lifecycle overrides (`Initialize`, `Destroy`,
  `MouseDrop_T`, …) unless you specifically need to suppress the parent.
- **Override via vars/subtypes**, not by editing an unrelated base — re-open the
  type and set `icon` / `name` / `desc`, or subtype it.
- **Run DreamChecker before pushing.** Upstream-style red builds get rejected.

### 3a. List allocation (`code/__defines/_lists.dm`)

| Use case | Pattern |
|---|---|
| Constant table shared across all instances of a type | `var/static/list/foo = list(...)` |
| Per-instance mutable, often empty | `var/list/foo` + `LAZYADD`/`LAZYLEN`/`LAZYREMOVE` |
| Per-instance mutable, always non-empty | `var/list/foo = list(...)` (rare) |
| Local working list inside a proc | `var/list/foo = list()` |

Anti-pattern: `var/list/foo = list()` on an *instance* var — allocates one list per
instance even when empty, and subtype overrides inherit the empty alloc. Use a
lazylist instead. For per-subtype constant tables (which DM can't express as a
`static` var), use a getter proc that returns a proc-local `var/static/list`.

### 3b. Type safety

- `istype()` to narrow before reading a subtype member is fine. **Never** use the
  `:` operator to reach a subtype member — `istype()` → cast → access.
- In a typed `for(var/obj/item/foo/F in list)` the `istype` is implicit; use
  `as anything` when the list is known-clean so stray nulls surface as runtimes.
- Never use type paths as strings.

### 3c. Lifecycle / hard-delete prevention

- Prefer `Initialize(mapload, ...)` over `New()` for atoms; `return ..()`.
- `Destroy()` must null held refs, `UnregisterSignal`, cancel timers/callbacks,
  remove from global tracking, then `return ..()`. Return the right `QDEL_HINT_*`.
- Always `qdel()`, never `del()`.

### 3d. Signals & callbacks

- Every signal handler's first line is `SIGNAL_HANDLER`; it must not sleep — hand
  slow work to `INVOKE_ASYNC`.
- Pass procs via `PROC_REF()` / `TYPE_PROC_REF()` / `GLOBAL_PROC_REF()`, never a
  bare string proc name.

### 3e. Performance

- Cache appearances (`/image` / `/mutable_appearance`), not raw `/icon` objects.
- Prefer flat lists indexed by `#define`d ints over assoc lists keyed by strings
  when the keys are a fixed enum (~8 B vs ~24 B/entry).
- Scale `process()` effects by the subsystem `wait` (or a `seconds_per_tick` arg).

### 3f. Magic numbers, input, SQL

- Use the time defines (`1.5 SECONDS`, `5 MINUTES`) — never raw deciseconds.
- `#define` flag/ID/threshold constants.
- Sanitize/`stripped_input()` free text and **re-validate** user/target/state after
  any `input()` / `tgui_input_*` returns. Validate `Topic()` hrefs (`locate(ref) in …`).
- Parameterized SQL only; `format_table_name()` for table names.

---

## 4. Build pipeline

Windows is the supported dev OS. Entry points (`bin/`):

- `bin/build.cmd` — DM + TGUI build → `deepquarry.dmb` + `deepquarry.rsc`.
- `bin/server.cmd` — build then host on port 1337.
- `bin/test.cmd` — unit-test boot (CI verification).
- `bin/tgui-build.cmd` / `bin/tgui-dev.cmd` / `bin/tgui-fix.cmd`.
- `bin/clean.cmd`.

`tools/build/build.ts` (Juke) orchestrates the DM build. Two fork-specific steps:

- **Icon repack** (`tools/dq_icons/`): regenerates `.dmi` from `png` + `dmi.toml`
  into `icons/gen/` before the DM compile (dirty-checked; no-ops when clean).
- **verdigris** (`tools/build/build.ts` `VerdigrisTarget`): builds the Rust FFI
  library (`verdigris.dll` on Windows, `libverdigris.so` on Linux) when its source
  is stale. You can also build it directly with `verdigris/build-windows.sh` /
  `verdigris/build-linux.sh`. The compiled library is a gitignored per-platform
  artifact; the DM game loads it at runtime via `VERDIGRIS_CALL(...)`.

Runtime DMI note: because repacked `.dmi` live only in `icons/gen/`, code that reads
DMI metadata at runtime via rust-g resolves the `icons/gen/` copy automatically
(`icon_metadata()`, `universal_icon.to_list()`).

The DM linter (`SpacemanDMM`) runs as part of the build and in CI — heed every
warning.

---

## 5. TGUI

- `tgui/` is TypeScript-only with Biome (formatter/linter) and Bun (runtime).
- `npm run tgui:lint` to check, `npm run tgui:fix` to auto-fix.
- Interfaces live in `tgui/packages/tgui/interfaces/`. New fork UIs go there.

---

## 6. Changelogs

Every user-visible PR drops one YAML in `html/changelogs/` (`<author>-<branch>.yml`):

```yaml
author: "yourkey"
delete-after: true
changes:
  - rscadd: "Added X"
  - bugfix: "Fixed Y"
  - balance: "Tuned Z"
```

Valid prefixes: `rscadd`, `rscdel`, `bugfix`, `qol`, `balance`, `soundadd`,
`sounddel`, `imageadd`, `imagedel`, `maptweak`, `spellcheck`, `experiment`,
`refactor`, `code_imp`, `config`, `admin`, `server`, `wip`. The merge bot rolls the
YAML into the master changelog and deletes the stub.

---

## 7. PR checklist

- [ ] New `.dm` files `#include`d in `deepquarry.dme`.
- [ ] Absolute type/proc paths only; no `:` operator on subtype access.
- [ ] `Destroy()` nulls refs / unregisters signals / returns the right `QDEL_HINT_*`.
- [ ] Signal handlers start with `SIGNAL_HANDLER`; callbacks use the `*_PROC_REF` macros.
- [ ] Time args use `SECONDS`/`MINUTES`/`HOURS`.
- [ ] DreamChecker (`SpacemanDMM`) passes locally.
- [ ] TGUI (if changed): `npm run tgui:lint` clean, `npm run tgui:fix` leaves no diff.
- [ ] One YAML changelog stub.
- [ ] Squash-able history; commit subject ≤ 72 chars.

---

## 8. Where to look when stuck

- DM linter rules: `SpacemanDMM.toml`, `code/__odlint.dm`, `code/__pragmas.dm`.
- Build entry: `bin/build.cmd` → `tools/build/build.ts`.
- Icon pipeline: `tools/dq_icons/`.
- verdigris (Rust FFI): `verdigris/README.md`.
- Changelog format: `html/changelogs/example.yml`.
- PR template: `.github/PULL_REQUEST_TEMPLATE.md`.

---

## 9. Current status / known state

Things that are deliberately mid-flight or disabled, so you don't "fix" them by
accident or assume they work:

- **Atmospherics — LINDA-only.** LINDA (the vendored /tg/ atmos: `/datum/gas_mixture`,
  `gas_types`, `SSair`, environmental/pipes/components under `code/ATMOSPHERICS/`) is
  the **live and only** engine. The old CHOMP/ZAS/XGM engine is **deleted**; there is no
  `USE_LINDA_ATMOS` gate anymore. Gas reactions are the CHOMP roster ported onto LINDA
  (`gasmixtures/reactions.dm`). Multi-z atmos is wired (`SSair.build_multiz_atmos_levels()`
  bridges `GLOB.z_levels` → `SSmapping.multiz_levels`; re-run when z-levels are added).
  Known remaining gaps (not bugs): (a) the **Rust auxmos** gas-math backend is **not wired** —
  `auxmos_bindings.dm` isn't compiled and `auxtools_atmos_init()` isn't called; gas math runs
  in pure DM. Wiring it is a future perf project. (b) Legacy XGM-style callers are still bridged
  by load-bearing shims (`xgm_compat.dm` ~67 callers of `assume_gas`/`update_nearby_tiles`/etc.,
  `tg_infra_compat.dm`, `machine_shim.dm` ~39 `set_machine()` callers) rather than migrated to
  native LINDA APIs. See `doc/atmos_migration.md`, `code/ATMOSPHERICS/README.md`.
- **Overmap — subsystem on, surface map ground-only, live map still multi-z at runtime.**
  `code/modules/overmap/` compiles and runs; `maps/deep_quarry/` sets `use_overmap = FALSE`
  (no overmap sectors). But the live map is **not** single-z: `SSquarry` digs the map into
  procedurally-generated quarry layers, each loaded as a new z-level via `load_new_z()`, so
  vertical multi-z atmos applies to them at runtime. The overmap proper is exercised by
  `virgo_minitest`.
- **Dynamic overmap POI system — deleted.** The spawn hook in `code/modules/overmap/sectors.dm`
  and the POI templates/loot were removed. Reviving requires restoring that content from git
  history. Leave it removed unless explicitly asked to revive it.
- **ATC (Air Traffic Control) — removed.** The `SSatc` subsystem and its radio-chatter module
  (`busy_space/atc_chatter*`, `chatter_*`) are deleted. The `loremaster`/`organizations` lore
  datums that lived alongside it in `busy_space/` are kept (used codebase-wide).
- **verdigris (Rust FFI)** is a build artifact, gitignored per-platform. If `cargo` is absent
  the build warns and skips it; cave-gen FFI then fails at runtime. (Atmos does **not** depend
  on it — gas math is pure DM until the auxmos backend is wired.)

Recent hardening (already landed): ban/admin/stats SQL is fully parameterized; all verdigris
`#[byond_fn]` entry points are wrapped in `panic_safe!`; the tgui Rules-of-Hooks / XSS audit
findings are fixed; the unit-test suite was audited for fake-passes and made genuinely
falsifiable.

## TL;DR

> One unified tree — put code in the matching `code/`/`maps/`/`icons/` location and
> edit any file freely (no modular folders, no edit markers, no upstream merges).
> Register every new `.dm` in `deepquarry.dme`, use absolute type paths, follow the
> DM standards in §3, drop a changelog YAML, and squash before merge.
