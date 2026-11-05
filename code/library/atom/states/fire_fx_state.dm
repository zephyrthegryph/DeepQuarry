// fire_fx: lazy state of /obj (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, fire_fx, field), write with STATE_SET(A, fire_fx, field, value), end it with fire_fx_clear(A).

/datum/fire_fx_state
	parent_type = /datum/lazy_state
	var/burn_ended_by
	var/burn_fuel = 0
	var/burn_overlay
	var/burn_particle_type
	var/burning_particles
	var/custom_fire_overlay
