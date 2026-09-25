/mob/living/silicon/decoy
	life_set = LIFE_SET_DECOY

/// Destroyed at DQ_MACHINE_LETHAL_MULT x endurance, decided by the machine body.
/datum/life_system/decoy_body
	name = "decoy body"
	wake_on = LIFE_WAKE_ON_BODY
	phase = LIFE_PHASE_BODY
	life_sets = LIFE_SET_DECOY
	mob_type = /mob/living/silicon/decoy

/datum/life_system/decoy_body/tick(mob/living/silicon/decoy/self, datum/life_context/ctx)
	if (self.stat == DEAD)
		return
	self.body?.life_tick()
