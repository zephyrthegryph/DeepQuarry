/// The DM side of the DeviceFlow/DeviceValve components
/// (verdigris/domains/gas/src/kind/device.rs, rust_architecture.md §8.5
/// step 6): each pipe device's flow(s) and optional valve gate are their
/// own row, bound to one of these holders through the generated
/// vg_component_* procs, exactly as GasMix binds to /obj/item/gas_mix_holder
/// (gas_mix_holder.dm's own comment). Never placed on a turf: the holder
/// only exists to give a row's #[vg::component] a DM type that isn't a
/// pipe device's own (binding DeviceFlow to /obj/machinery/atmospherics
/// itself would make the generated set_deviceflow_rate() etc. shadow a
/// real device's own procs).
/obj/effect/device_flow_row
	name = "pipe device flow"
	invisibility = INVISIBILITY_ABSTRACT
	anchored = TRUE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/obj/effect/device_valve_row
	name = "pipe device valve"
	invisibility = INVISIBILITY_ABSTRACT
	anchored = TRUE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
