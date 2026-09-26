// Marker types for `verdigris/domains/heat/src/components.rs`'s
// `#[vg::component(dm = ...)]` declarations (`doc/rewrite/rust_bindings.md`).
//
// HeatBody's couplings (`SolidCoupling`/`BodyCoupling`/`GasCoupling`) and a
// regulator are their own entities, created and bound directly by
// `verdigris/ffi/src/heat.rs` (`vg_heat_body_create`/`heat_body_couple`),
// never through the generic per-atom `on_materialize()`/`vg_bind()` flow --
// so nothing ever instantiates these types. They exist only so the
// generated accessors (`get_*`/`set_*`, `vg_bind_heat()`) have a real,
// otherwise-untouched DM type to attach to, one each, so two components'
// same-named fields (`conductance`, `slot`, ...) never collide with each
// other or with an unrelated type's own proc of the same name -- exactly
// what putting them all on a shared broad type like `/atom/movable` or
// `/mob` risked (a real conflict this file's addition fixed: `HeatBody`'s
// `power`/`temperature` fields collided with `/obj/machinery/power/gravity_generator`'s
// and `/atom`'s own existing procs before this).
/atom/movable/vg_heat_body

/atom/movable/vg_heat_solid_coupling

/atom/movable/vg_heat_body_coupling

/atom/movable/vg_heat_gas_coupling

/atom/movable/vg_heat_regulator

/atom/movable/vg_heat_mob
