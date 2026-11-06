GLOBAL_ALIST_EMPTY(stored_shock_by_ref)

/mob/living/proc/apply_stored_shock_to(mob/living/target)
	if(GLOB.stored_shock_by_ref[handle_of(src)])
		target.electrocute_act(GLOB.stored_shock_by_ref[handle_of(src)]*0.9, src)
		GLOB.stored_shock_by_ref[handle_of(src)] = 0
