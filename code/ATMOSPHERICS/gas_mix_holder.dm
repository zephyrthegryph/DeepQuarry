/// The DM side of the GasMix component (verdigris/domains/gas/src/kind/gas_mix.rs):
/// a holder that owns one main-thread gas mixture row, through the generated
/// get_moles()/set_moles()/get_volume()/... procs. Tanks, canisters and lungs
/// move onto GasMix later; until then this is the only bound type, so the
/// generated accessors never shadow a live object's own procs
/// (/atom/proc/get_temperature on a tank).
/obj/item/gas_mix_holder
	name = "gas mixture holder"
	desc = "A sealed sample of a gas mixture."
