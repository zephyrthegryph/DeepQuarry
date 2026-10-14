/datum/om/proc/watch_it(E)
	vg_world_at(E)
	vg_world_step(E)
	vars["x"] = 1
	om_prompt(E)
	om_relation_of(E, 1)
