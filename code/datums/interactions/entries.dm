/// Requirement clause: the actor is alive, conscious and not incapacitated (the old verbs' usr checks).
/proc/dq_actor_can_act(mob/actor, atom/target, obj/item/held)
	READS_FROM(actor)
	if(!isliving(actor))
		return FALSE
	return !actor.incapacitated()
