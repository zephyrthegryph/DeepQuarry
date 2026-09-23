/mob/living/silicon/decoy/Life()
	if (src.stat == DEAD)
		return
	// Destroyed at DQ_MACHINE_LETHAL_MULT x endurance, decided by the machine body.
	body?.life_tick()
