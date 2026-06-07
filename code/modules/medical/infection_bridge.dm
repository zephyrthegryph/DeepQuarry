// germ_level → condition bridge.
//
// The upstream germ_level system models *infection physics*: dirty
// wounds accumulate germs, antibiotics reduce them, bandages and
// disinfectant gate the rate. We keep all of that — it's a solid
// simulation. What we replace is the *player-facing effect*: instead
// of opaque germ numbers and "Cellulitis detected" scanner lines, we
// surface infection through a condition with symptoms.
//
// Rules now live as /datum/dq_cause/germ_level records. This proc
// walks them and idempotently spawns the produced condition on the
// organ when its germ_level meets the threshold.
//
// Called from /obj/item/organ/process() after handle_germ_effects().

/obj/item/organ/proc/dq_bridge_germ_to_condition()
	if(!owner || !ishuman(owner))
		return
	if(robotic >= ORGAN_ROBOT)
		return
	for(var/datum/dq_cause/germ_level/c as anything in dq_causes_of_kind("/datum/dq_cause/germ_level"))
		// A null organ on the cause means "any organ".
		if(c.organ && c.organ != organ_tag)
			continue
		if(germ_level < c.threshold_level)
			continue
		for(var/datum/dq_cause_outcome/o as anything in c.produces)
			if(!o.preconditions_met(src))
				continue
			dq_spawn_condition(o.condition_type)
