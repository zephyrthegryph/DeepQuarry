/datum/matter_synth
	var/name = "Generic Synthesizer"
	var/max_energy = 60000
	var/recharge_rate = 2000
	var/energy

/datum/matter_synth/New(store = 0)
	if(store)
		max_energy = store
	set_energy(max_energy)
	return

/datum/matter_synth/proc/get_charge()
	return energy

/datum/matter_synth/proc/use_charge(amount)
	if (energy >= amount)
		set_energy(energy - amount)
		return 1
	return 0

/datum/matter_synth/proc/add_charge(amount)
	set_energy(min(energy + amount, max_energy))

/datum/matter_synth/proc/emp_act(severity, recursive)
	use_charge(max_energy * 0.1 / severity)

/datum/matter_synth/medicine
	name = "Medicine Synthesizer"

/datum/matter_synth/nanite
	name = "Nanite Synthesizer"

/datum/matter_synth/metal
	name = METAL_SYNTH

/datum/matter_synth/plasteel
	name = PLASTEEL_SYNTH
	max_energy = 10000

/datum/matter_synth/glass
	name = GLASS_SYNTH

/datum/matter_synth/wood
	name = WOOD_SYNTH

/datum/matter_synth/plastic
	name = PLASTIC_SYNTH

/datum/matter_synth/wire
	name = WIRE_SYNTH
	max_energy = 50
	recharge_rate = 2

/datum/matter_synth/bandage
	name = "Bandage Synthesizer"
	max_energy = 10
	recharge_rate = 1

/datum/matter_synth/cloth
	name = CLOTH_SYNTH

/datum/matter_synth/beacon
	name = "Beacon Synthesizer"

/datum/matter_synth/proc/set_energy(value)
	if(energy == value)
		return FALSE
	energy = value
	// Existing reverse REF index: only real stacks borrowing this synth need recosting.
	var/obj/item/stack/stack_shape
	for(var/datum/D as anything in rel_sources_via(src, nameof(stack_shape.synths)))
		if(!istype(D, /obj/item/stack))
			continue
		var/obj/item/stack/S = D
		if(!QDELETED(S) && S.synths && (src in S.synths))
			S.ledger_refresh_contribution()
	tracked_changed(src, nameof(energy))
	return TRUE
SETTER(/datum/matter_synth, energy)
