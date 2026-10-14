/// Conductance (W/K) of this atom's heat body to its holder's interior, from
/// its own conductance `base`. On a turf, or in a holder without slots, the
/// path doesn't apply and `base` stands.
/atom/proc/heat_path_conductance(base)
	var/atom/holder = loc
	if(!holder || isturf(holder) || !dq_slot_defs_for(holder))
		return base
	return base * dq_path_step(holder, src, PATH_EFFECT_HEAT)
