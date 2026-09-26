/// Nominal-only DM types for the DeviceFlow/DeviceValve components
/// (verdigris/domains/gas/src/kind/device.rs, rust_architecture.md §8.5
/// step 6). A pipe device's flow(s) and optional valve gate are bare
/// entities the Rust side allocates directly (`vg_pipe_flow_set()`/
/// `vg_pipe_valve_set()`, `ffi/src/pipes.rs`, no per-field DM accessors,
/// no `vg_bind_gas()` call) -- never instantiated, so never placed as an
/// `/obj` on a turf the way a real map atom would be. `#[vg::component]`
/// requires a real DM type under `/atom/movable` for its per-field
/// accessor codegen to have somewhere to declare `vg_entity`/`vg_bind_gas`
/// (plain `/datum` doesn't carry that plumbing, `rust_architecture.md`
/// §1/§13); these two exist solely to satisfy that, as dead, unused code.
/obj/effect/device_flow_row
	name = "pipe device flow (never instantiated)"
	invisibility = INVISIBILITY_ABSTRACT
	anchored = TRUE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/obj/effect/device_valve_row
	name = "pipe device valve (never instantiated)"
	invisibility = INVISIBILITY_ABSTRACT
	anchored = TRUE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
