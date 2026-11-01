/mob/living/silicon/decoy

/// Destroyed at DQ_MACHINE_LETHAL_MULT x endurance, decided by the machine body.
/mob/living/silicon/decoy/proc/life_decoy_body(datum/seq_frame/life/F)
	if (src.stat == DEAD)
		return
	src.body?.life_tick()
