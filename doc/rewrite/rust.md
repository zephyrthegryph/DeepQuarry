# Rust: one frame, one outbox, no mirrors

Status: **[in progress]** on `rewrite/f-rust` (owner W4), on top of `rewrite/rust-integration`.
The library structure (vg-core, domains, macros) is described in
[rust_architecture.md](rust_architecture.md), [rust_core.md](rust_core.md),
[rust_bindings.md](rust_bindings.md) and [simulation.md](simulation.md). This chapter is the
DM-facing contract and overrides them on drivers, watches and mirrors (section 6). Overview:
[foundation.md](foundation.md).

## 1. One entry

`vg_frame(elapsed, budget)` is the only per-tick call into Rust. It steps the `World`, including
pipe devices as laws with a `Period`, heat, the entity tick, and Rust timers, rates and watches,
then returns **one outbox page** of records:

| Record | Meaning | DM delivery |
|---|---|---|
| `CHANGED(entity, key)` | A native value changed | `publish_change(E, key)` ([state_and_relations.md](state_and_relations.md)) |
| `NOTICE(entity, kind, args)` | A native occurrence | `PUBLISH(E, type, args...)` ([reactions.md](reactions.md)) |
| `CROSSED(watch, band)` | A watched value crossed a band edge | `on_cross` handlers, urgent when declared |

DM `/datum/system/native` (kernel phase N, [scheduling_and_kernel.md](scheduling_and_kernel.md))
calls `vg_frame` and dispatches the page. The old drivers and drains (SSvg world tick, SSair drains,
heat tick, `world_step`, gas observation drains) become internal or are deleted: there is exactly
one driver and one drain.

## 2. Reading native values

`native_read(E, key)` reads through to Rust with a **per-frame cache** cleared by the matching
`CHANGED`. A reaction declares a native read with `native(key...)`; the read spec is a
foundation type, so `on_change`, `drawn_from` and `ui_from` treat native and DM values alike.
Every call crosses the FFI, so hot loops cache the result in a local.

## 3. Watches

There is **one watch facility**: World watch ports with bands and hysteresis. The reactor
watch/token mechanism is deleted; heat uses the same facility. A native `CROSSED` record is the
only source for `on_cross` on native values. Movement rebinds the occupant's watch (a mob's air
source changes when it moves).

## 4. No mirrors

DM holds handles, not copies. Deleted mirrors and their replacements:

| Mirror | Replacement |
|---|---|
| `turf.temperature` | `initial_temperature` seed for mapping plus a lint; live value via the heat API ([temperature.md](temperature.md)) |
| APC `sync_cell_charge` | `native_read` of the cell charge |
| Grid view easing | Client/UI side |
| SSvg repair sweep | Test-only drift audit |
| Radiation shielding copies | `TRACKED` + generated `rust_push` |
| `update_rust_device` / power_sync hand pushes | Generated `rust_push` from declared reads ([reactions.md](reactions.md)) |

## 5. Gas and rates

All gas moves through Rust transfer binds. DM `pump_gas`, `scrub_gas`, `filter_gas(_multi)`,
`mix_gas` and `calculate_transfer_moles` maths are deleted; callers use thin wrappers over the
binds. `mingle_with_turf` and `temperature_interact` become batch mingle plus heat coupling. One
rate implementation per side (DM `om_rate_*` and `dq_rx_rate_*` merge into one). Gas **reactions**
remain in DM. `/datum/gas_mixture` remains an opaque handle (read with `return_temperature()` etc.).

Bindings are regenerated (`tools/build/build.sh verdigris-bindings`), `cargo test` runs in
`verdigris/`, and the ABI version is bumped. Worktree DM-only work sets `DQ_PREBUILT_VERDIGRIS=1`.

## 6. Where this overrides older docs

| Older text | Now |
|---|---|
| rust_architecture.md section 8: several drivers and drains | one `vg_frame`, one outbox |
| rust_core.md watches, tokens and reactor list | one World watch facility |
| kernel.md section on the native driver (`vg_world_tick + vg_heat_tick + ...`) | `vg_frame` |
| rust_bindings.md per-object pushes | generated `rust_push` and `native_read` |
