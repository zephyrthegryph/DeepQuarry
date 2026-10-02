/datum/om/proc/set_by_name(E, name, v)
	E.vars[name] = v
	vars["x"] = 1
	om_set_var(E, "x", 1)
	om_prompt(E)
	om_relation_of(E, 1)
	om_related(E)
	vg_world_at(E)
	TIMER_COOLDOWN_START(E, "k", 5)
