/mob/living/silicon/decoy
	life_set = LIFE_SET_DECOY

/// Destroyed at DQ_MACHINE_LETHAL_MULT x endurance, decided by the machine body.
/datum/om/stage/life/decoy_body
	order = LIFE_PHASE_BODY + 0
	name = "decoy body"
	wake_on = CHANGE_MOB_HEALTH
	life_sets = LIFE_SET_DECOY
	of = /mob/living/silicon/decoy

/datum/om/stage/life/decoy_body/perform(mob/living/silicon/decoy/self, datum/om/frame/life/ctx)
	if (self.stat == DEAD)
		return
	self.body?.life_tick()
