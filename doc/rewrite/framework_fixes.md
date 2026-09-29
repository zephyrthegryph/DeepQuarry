## 9. Framework fixes from review pass 2 (binding)

This section is binding. It records every fix from the second review: six Sonnet reviews plus the live-bug check. Where it disagrees with an earlier section or with the migration guide, **this section wins**. The guide gets updated to match it. The framework is not finished until every row in 9.3 is collapsed to its single form. The migration waves start only after 9.1–9.4 are built.

### 9.1 Waiting: prompts and I/O (decision: option A, owned suspension)

`ask_*` and `await_*` are the **only** suspension points in gameplay code. Raw `sleep`, `spawn`, `UNTIL`, `stoplag` in handlers, and direct `tgui_input_*`/`input()`/`alert()` are lint errors outside the ask layer and the kernel.

**The model**
- **Tasks:** a handler that asks or awaits runs as a kernel-tracked `/datum/om_task`. The task holds `holder`, `user` and `target` weakly and records what it's waiting for. BYOND can only suspend by sleeping, so the ask layer does sleep internally. That sleep is owned: the kernel can see it, count it and cancel it.
- **Cancellation:** a pending task is cancelled, and its `ask_*`/`await_*` returns null, in each of these cases:
  - the holder is qdel'd (this runs before the garbage check, so a waiting task never causes a hard delete);
  - the user disconnects;
  - the target is deleted or out of range.
- **Re-validation:** on resume, the task re-runs the entry's `needs` for `(user, holder, target)`. If they fail, the player is told why and the call returns null.
- **Who is asked:** `as = ASK_ACTOR` (the default) checks the actor, as today. `as = ASK_THIRD_PARTY` and `ASK_CONSENT` check only that the asked mob can answer: it has a client, and ghosts are allowed. They don't check reach or consciousness. `target` is truly optional.
- **Options:**
  - `timeout =` (a timeout returns null) and `default =`;
  - `yes = "Devour", no = "Cancel"` labels on `ask_yes_no`;
  - `validate = PROC_REF(x)`, which asks again with its message when the answer is invalid;
  - `optional = TRUE` on text and form fields, where `""` means skipped and null means cancelled.
- **Return values:**
  - `ask_number` returns null on cancel, so 0 is a valid answer. The guide says to use `isnull()`.
  - `task_why()` returns `ASK_CANCELLED`, `ASK_TIMED_OUT`, `ASK_INVALID` or `ASK_GONE`, for the rare caller that cares.
- **Forms:** `ask_form(who, list(text_field(...), number_field(...), yes_no_field(...), choice_field(...)))` returns an assoc list or null. `when = PROC_REF(...)` skips a field.
- **Concurrency:** one pending prompt per user + holder + entry. A second click answers "You're already doing that."
- **Admin verbs:** `ADMIN_VERB` binds the rights into the task, so there are no per-ask `needs`.
- **I/O:** `await_sql(sql, args, timeout = 10 SECONDS)`, `await_http(...)` and `await_job(...)` (rust-g jobs) return a `/datum/io_result` with `ok`, `rows`, `error`, `timed_out` and `gone`. A failed read is never mistaken for "no rows". Fire-and-forget writes are allowed only when nobody reports success.
- **Starting a task and timed actions:** `start_task(holder, PROC_REF(x), args...)` starts a task outside an entry; it replaces `after(src, 0, ...)` as the way to detach. `await_action(user, target, delay, cancel_if = MOVED_APART)` is the timed action (the progress bar): it returns TRUE when completed and null when cancelled, and the entry's `needs` are re-run when it completes. That deletes the "time has passed, re-verify everything" sanity procs.
- **Delays:** `await_delay(d)` is allowed only inside a task, for admin or scripted sequences. It is lint-banned in `periodic_step`, `should_run`, `draw`, `tgui_data` and signal handlers.
- **`on_shutdown`** never suspends. The kernel drains I/O itself.
- **Tests:** `test_answers(user, list("Bob", TRUE, 12))` scripts the answers. `test_pending_prompt(user)` inspects the open prompt. The harness uses `wait_ticks(n)` and `run_until(PROC_REF(cond), timeout)`; `kernel_await.dm` stops using `sleep`.
- **Deleted:** `om_ask`, `act_ask`/`rerun_ask`, `prompt_flow`/`flow_execute`, `/datum/om/flow`, `om_prompt_answer`/`test_prompts`, and every `rerun_ask` key. `om_io` callbacks stay only as the kernel's implementation of `await_*`.

### 9.2 Declared dependencies and derived values

Derived outputs re-run exactly when something they read changes, and never otherwise. The outputs are `should_run()`, `draw()`, `tgui_data()`, cached derived vars, and pushes to Rust. Authors declare what each output reads in a per-type cached block that follows the same rules as `capabilities()`:

```dm
/obj/machinery/sleeper/derived()
	. = ..()
	. += runs_while(nameof(occupant_count), nameof(power_state))
	. += drawn_from(nameof(occupant_count), nameof(power_state))
	. += ui_from(nameof(filtering), nameof(pumping), rel_each(nameof(occupants), nameof(/mob/living::stat)))
	. += derive(nameof(occupant_count), rel_count(nameof(occupants)))   // computed by derive_occupant_count()
```

**Rules**
1. **Read sources:**
   - `nameof(var)`: the var must be TRACKED, derived or a relation;
   - `rel(nameof(relation), nameof(/type::var))` and `rel_each(...)`: hops go only through declared relations or ownership. The reverse index is maintained by link and unlink, so there's no extra bookkeeping. A hop through a plain var is refused at init with a clear error;
   - `rel_count(...)`;
   - `factor_dep(BF_X)`: fires when the body's cached factors change;
   - `sys(/datum/system/x, nameof(/datum/system/x::var))`: a system field;
   - `rust(RUST_X)`: a Rust-published channel, delivered through the one adapter at most at its publish rate (for UI readouts);
   - `watch_gas(nameof(air), GAS_PRESSURE, above = X, hysteresis = Y)`: a threshold. High-rate Rust values that drive behaviour are read as thresholds, never raw.
2. **Derived vars:** `derive(var, reads...)` caches the var. It is recomputed by `derive_<var>()` only when a read changes, and it is itself change-tracked, so derived values chain into a DAG. This is how "power has four readers" becomes one `power_state`, and how vore's `unsaved_changes` becomes derived instead of being set at 126 sites.
3. **Rust inputs:** `rust_push(reads...)` calls `push_to_rust()`, coalesced, when any read changes. This replaces every hand-written `update_rust_device()` call.
4. **Capabilities contribute their own reads.** `cap_panel` contributes its state bits to `drawn_from`, `cap_occupant` provides `occupants`, and so on. Authors declare only what their own code reads.
5. **Coalescing:** a change sets a dirty bit per output, and the refresh phase (L1) recomputes each output at most once per tick. Outputs must not write state. Test builds assert this, and the existing per-type purity check becomes this assert.
6. **Cost:** zero for types with no declarations. A change costs one lookup, `(type, var)` to an outputs bitmask, and sets a bit. Relation fan-out uses lazy reverse lists.
7. **Lint:** `derived_reads_lint.py` checks that each output body reads only what is declared, and `--fix` rewrites the `derived()` block (a dev tool, not build generation). Declared vars written outside their setter are errors.
8. **One drift audit:** a sampled audit re-evaluates outputs against their caches. On a mismatch it names the likely undeclared read. It replaces the three existing missed-wake audits.
9. **Life uses the same mechanism.** Stages declare `runs_while(nameof(/mob/living::losebreath), ...)`. `wake_on`, `idle()`, `rewake_delay` and the `life_wake()` bits are deleted (see 9.5).
10. **Demand-driven:** an output listens only while something consumes it. `ui_from` is registered only while a UI is open, `runs_while` only while the holder has a cadence, and `drawn_from` only while the atom is on a z-level with players, with a catch-up draw on becoming relevant. That bounds `rel_each` fan-out.
11. **Intervals can be derived:** `periodic_interval()` with `interval_from(reads...)` changes the cadence when its reads change (belly turbo mode, fast gas).
12. **Explain view:** the debug verb `dx_explain(atom)` shows each output, what it reads, the last trigger, the sleep/wake state and the pending dirty bits.

### 9.3 One way to do each thing (the duplicate systems)

| Concern | Duplicates today | The one form | Deleted |
|---|---|---|---|
| Change notification | `om_changed` (98 sites, no refresh), `changed` (46), `life_wake` bits, hand-called `update_icon`/`update_uis`/`handle_belly_update` | `changed()` from SETTER/TRACKED vars, with outputs driven by `derived()` | `om_changed`, the `life_wake` bits, manual refresh calls |
| Waiting | sleeping `ask_*`, `om_ask`, `rerun_ask`/`prompt_flow`, `om_io` callbacks, `sleep`/`spawn`/`UNTIL` | `ask_*`/`await_*` in tasks (9.1) | the rest |
| Wake and sleep | stage `idle`/`wake_on`/`rewake_delay`, atom `should_run`, kernel `member_should_run`, `DECLARE_PERIODIC_WHILE*` | `should_run()` with declared reads; `STEP_AGAIN_IN(t)` from a step | the others |
| Missed-wake audits | 3 separate audits | one drift audit (9.2.8) | 2 |
| Membership rosters | `/datum/cap_system.members`, `/datum/system.members`, per-mob life pipelines | `/datum/system` members | `cap_system` |
| Latency class | `system.latency_class` (L1), `cadence.lane` (L2) | `system.latency_class` | `cadence.lane` |
| Yielding | `MC_TICK_CHECK`, `service_step` returning FALSE, `PROCESS_KILL` (26) | `STEP_DONE`/`STEP_YIELD`/`STEP_PARK`/`STEP_AGAIN_IN(t)` | the others (inside systems) |
| Cadence types | two `CADENCE_SLOW` types across branches | one set of cadence defines | the duplicate |
| Power reads | `operable()`, `powered()`, `has_stat(NOPOWER)`, `cap_powered()`, raw `use_power` reads | derived `power_state` (`POWER_BROKEN`/`POWER_UNPOWERED`/`POWER_OFF`/`POWER_IDLE`/`POWER_ACTIVE`); `use_power` is written only by `power_state`'s owner | the four readers |
| Rust to DM | 5 delivery patterns, generated `atom_break` pushes, the `anchored` reconciler, hand `power_change` | one adapter that calls `changed(src, RUST_*)`, plus the `on_state_changed(bits)` hook | the rest |
| DM to Rust | `update_rust_device()` from 6 call sites | `rust_push(...)` in `derived()` | the call sites |
| Temporary state | `expire_at`, `EXPIRY_*`, modifier and body-effect timers, self-re-arming reset procs | behaviour: `grant_for(GRANT_CAPABILITY)`; pure value: `timed_set`; throttle: `COOLDOWN_*`; body numbers: body effects with a duration (no end time stored) | `EXPIRY_*`, stored end times |
| Timers | `om_after`, `after`, `om_after_slot`/`unique`/`replace`, `OWN_TIMER`, `addtimer` | `after()` and `after_slot()` | the rest |
| Visual flashes | a timed var plus a `draw` branch, `flick_overlay` plus a reset timer | `flash_look(src, state, duration)` | the rest |
| Entry points | `cap_entry_point`, `cap_entry_setup`, `INTERACT_*`, `click_ctrl`/`click_alt` overrides | entry constructors with common args: `delay`, `cooldown`, `needs`, `blocked_by`, `key`, `priority` (`PRIORITY_*`), `requires_power`; alt/ctrl/drag entries | the rest |
| Bundle overrides | restating a whole part | `refine(key, args...)` | the restating |
| Grants | `om_grant_for` in two places (framework, livesim) | `grant_for()` / `grant()` | the duplicate |
| Public `om_*` names | `om_after`, `om_grant_for`, `om_changed`, … | unprefixed names, with the old names as deprecated aliases until the waves remove them | the aliases |
| Refusal text | `else_say = "%T% ..."`, raw `to_chat`, the `"__ui_refused"` leak | `refuse(user, text)`; a capability's `refusal(holder, user)` proc | the template language |
| Relations | `/datum/om/relation/*` types, `REL`/`REL_PAIR`/…, plain var copies | `relations()` with `rel_one`/`rel_many`; `rel_link(src, nameof(x), y)` | the rest |
| Ownership | 16 spellings | `ownership()`: `owns(nameof(v), policy, home =)`, `shares`, `proto`; `cap_slot` implies `owns` | the macros |
| UI refresh | `SStgui.update_uis`, SSair polling every 0.5 s, `ui_data` per tick | `ui_from` in `derived()`, with one coalesced push per UI per 0.2 s | the rest |
| UI gating | type-wide `ui_act_allowed`, `DECLARE_UI_STATE` | `ui_allowed(user, action)` returning a reason or null | the rest |
| Prompt test seams | `test_prompts`, `om_prompt_answer` | `test_answers` | the rest |
| Lifecycle ratchets | `lifecycle_counts_lint.py`, `qdel_src_lint.py` | one ratchet | one |
| Null helpers | livesim `null_safety.dm`, base-var helpers | one `null_safety.dm` | the duplicate |
| Metrics | flat, nested, a Rust-only recorder | one `metrics()` schema; a kernel step ring feeding the Rust recorder | the rest |
| Client identity | stored 3 times | `client_session` | 2 |

### 9.4 Core defects (fix before any wave)

1. **The type-derive record is sticky** (`refresh.dm:218-224`). Record it only when the result is type-pure.
2. **Two change APIs:** see 9.3. Timed reverts must call `changed()`.
3. **`after()` drops callbacks when a datum argument is gone** (`timer.dm:741`). By default the callback now runs with the gone args nulled, which is master's `SStimer` behaviour; the counter and log stay. `drop_if_gone = TRUE` opts pure effects out. This fixes stuck vending, suit cyclers and clone pods.
4. **`ask_*` context:** see 9.1.
5. **`SHOULD_CALL_PARENT`** on `capabilities()`, `derived()`, `settings()`, `relations()`, `ownership()`, `type_verbs()`, `hidden_verbs()`, `tgui_data()` and `examine_lines()`.
6. **A runtime in a block proc** is reported and not cached.
7. **`timed_set`** refuses a null or zero duration, and reverts only if the var still holds the value it set, so it never clobbers a change made in the meantime.
8. **`cap_set`** requires `on`.
9. **`om_apply`** refuses a null duration.
10. **`cap_of`** sees capabilities attached at runtime.
11. **Colliding entry keys** are an init error unless `key =` names the replacement.
12. **A periodic step** refreshes only its dirty outputs.
13. **`TRACKED`** chains base setters.
14. **The purity assert** runs in every test build.
15. **Bit budgets:** `cap_state` gets per-family bit spaces, e.g. `CAP_STATE_MACHINE_*` or `CAP_STATE_ITEM_*`, overlapping across families that can't share a holder. Rare states go in `cap_data`. Change channels get the same split.

### 9.5 New framework pieces

**Machines**
- `machine_board` and `machine_wires` type vars, read by `machine_basics()` (convention H1). Subtypes set vars and never override `capabilities()` just to change a board.
- `refine(CAP_PANEL, blocked_by = MACHINE_OCCUPIED)` adjusts one part of a bundle.
- `service_panel(access)`: panel, wires and emag without a cover.
- `power_state` (see 9.3). Machines write `use_power` through `power_state` rules only: `power_active_while()` is a derived predicate.
- `cap_occupant(max, types, enter_delay, eject_on)`, `occupants(src)` (never null) and `occupant_count` (derived).
- `cap_access(req_access)` for access-gated use without lock state.
- Parts: `cap_parts(list(/obj/item/stock_parts/x = n))` with a `derive_part_rating()` derived value. It replaces `RefreshParts` and `default_part_replacement`; the RPED goes through the same entry.
- Ambient loops: `look.loop(sound)` in `draw`.

**Vore**
- `cap_interior(transmit = list(TRANSMIT_SOUND = TRANSMIT_MUFFLED, ...), escape_delay, on_enter, on_exit)` replaces `/datum/om/relation/slot/belly_interior`.
- `settings()` rows (`setting_choice`, `setting_number`, `setting_text`, `setting_bool`, `setting_color`) plus one validated `act_set_setting(user, key, value)` and `settings_data()`. `unsaved_changes` is derived.
- `needs` checks receive `(user, held, target)`. `chk_consent(pref)`. A public `why_not(user, holder, entry, target)` for per-cycle checks.
- `owns(nameof(v), policy, home = PROC_REF(x))` for owned things that don't live inside their owner (the AI hologram's belly).
- `vore/api.dm` plus `relations()` for prey, belly and predator.

**Periodic**
- `dt` is the real elapsed time.
- A step can `return STEP_AGAIN_IN(t)`.
- The interval can be a proc (`periodic_interval()`) with declared reads.

**Life**
- One `/datum/system/life` with an ordered stage plan; not one system per stage.
- Stages declare reads in `derived()`. `should_run(mob)` is positive, the old `idle()` inverted.
- `step(mob, dt)` returns `STEP_*`.
- Vars that stages read become TRACKED: `losebreath`, `internal` and the rest. Every direct write goes through its setter.
- Gating booleans go in capabilities and numbers in factors, with factors read through `factor_dep`.

**Kernel**
- **The design doc** is committed as `doc/rewrite/kernel.md`.
- **Stepping:**
  - one step protocol; the kernel calls a system's `periodic_step` on its cadence and drives members through `member_should_run`/`member_step`;
  - `step_priority`, `step_timing` (`STEP_TIMING_KEEP`/`STEP_TIMING_AFTER`), `defer_next_step(t)` for `postpone`, `resuming` for `fire(resumed)`, and `periodic_ticks` for tick-counted waits.
- **Latency and shedding:** the class is set only on the system, and each system gets its own L3 shedding floor.
- **Run control:**
  - `periodic_runlevels` on each system;
  - `wake_periodic()` and `park_periodic()`;
  - `on_recover(old)` for an admin restart of one system.
- **Boot order:**
  - a subsystem can list a system in its `dependencies`;
  - `needed_by` and `boot_stage`.
- **Visibility:**
  - `metrics()` carries the MC cost fields;
  - a DM step ring (start, dt, ms, yields, shed/late) is dumped on a runtime or an overrun and mirrored into the Rust recorder.

### 9.6 Guide corrections

- **B5:** there is no `is_powered()`. Use `power_state`.
- **B8:** re-runs do still exist. It becomes: they are deleted by 9.1.
- **B9, B14, B15:** add the temporary-state table (9.3). Correct `om_after_slot` to `after_slot`.
- **B17:** `rel_link` takes `nameof()`.
- **B30:** rewrite it against 9.5 Life. Remove `rewake_in`, stage `periodic_step` and `life_wake`.
- **The `cap_slot(..., eject_tool =)` examples:** the argument is added.
- **New rows:** parts, `on_state_changed`, `rust_push`, `derived()`, `settings()`, `cap_occupant`, `cap_interior`, and reserved UI argument names.

### 9.7 Live bugs found (fixed with the framework)

1. **Slime cube** (framework branch): a second clientless human appears, and the cube is never consumed. Fix: act first, then ask the name as the new human's own prompt.
2. **`losebreath`** (framework branch): a choked, parked mob breathes normally for up to 30 s. Fix: TRACKED plus `runs_while`.
3. **Ban records** (both branches): "Ban saved" is shown even when the INSERT fails. Fix: `await_sql` and `r.ok`.
4. **`after()` drops** (framework branch): vending, suit cyclers and clone pods get stuck. Fix: 9.4.3.
