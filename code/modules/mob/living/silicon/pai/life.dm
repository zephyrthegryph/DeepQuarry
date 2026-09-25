/mob/living/silicon/pai
	life_set = LIFE_SET_PAI

/// Cable retraction and `if(stat == DEAD) return`.
/datum/life_system/pai_cable
	name = "pai cable"
	wake_on = LIFE_WAKE_ON_MACHINE
	phase = LIFE_PHASE_INPUT
	order = 0
	life_sets = LIFE_SET_PAI
	mob_type = /mob/living/silicon/pai

/datum/life_system/pai_cable/tick(mob/living/silicon/pai/self, datum/life_context/ctx)
	self.check_retract_cable()

	if(self.stat == DEAD)
		return LIFE_HALT

/// Death from injury is decided by the body (see death.dm for card damage); card faults.
/datum/life_system/pai_body
	name = "pai body"
	wake_on = LIFE_WAKE_ON_BODY
	phase = LIFE_PHASE_INPUT
	order = 10
	life_sets = LIFE_SET_PAI
	mob_type = /mob/living/silicon/pai

/datum/life_system/pai_body/tick(mob/living/silicon/pai/self, datum/life_context/ctx)
	self.body?.life_tick()
	if(self.stat == DEAD)
		return LIFE_HALT

	var/obj/item/paicard/card = self.card
	if(card.cell != PP_FUNCTIONAL|| card.processor != PP_FUNCTIONAL || card.board != PP_FUNCTIONAL || card.capacitor != PP_FUNCTIONAL)
		self.death()

	if(card.projector != PP_FUNCTIONAL && card.emitter != PP_FUNCTIONAL)
		if(self.loc != card)
			self.close_up()
			to_chat(self, span_warning("ERROR: System malfunction. Service required!"))
	else if(card.projector  != PP_FUNCTIONAL|| card.emitter != PP_FUNCTIONAL)
		if(prob(5))
			self.close_up()
			to_chat(self, span_warning("ERROR: System malfunction. Service recommended!"))

/// The communication circuit comes back after a silence.
/datum/life_system/pai_silence
	name = "pai silence"
	wake_on = LIFE_WAKE_ON_MACHINE
	phase = LIFE_PHASE_OUTPUT
	order = 40
	life_sets = LIFE_SET_PAI
	mob_type = /mob/living/silicon/pai

/datum/life_system/pai_silence/tick(mob/living/silicon/pai/self, datum/life_context/ctx)
	if(self.silence_time)
		if(world.timeofday >= self.silence_time)
			self.silence_time = null
			to_chat(self, span_green("Communication circuit reinitialized. Speech and messaging functionality restored."))

/datum/life_system/statuses/silicon/pai
	mob_type = /mob/living/silicon/pai
	phase = LIFE_PHASE_OUTPUT
	order = 50
	segment = NONE

/datum/life_system/statuses/silicon/pai/tick(mob/living/silicon/pai/self, datum/life_context/ctx)
	..()
	sleeping(self)

/// Folded into the card, the pAI slowly self-repairs.
/datum/life_system/pai_repair
	name = "pai repair"
	wake_on = LIFE_WAKE_ON_BODY
	phase = LIFE_PHASE_OUTPUT
	order = 60
	life_sets = LIFE_SET_PAI
	mob_type = /mob/living/silicon/pai

/datum/life_system/pai_repair/tick(mob/living/silicon/pai/self, datum/life_context/ctx)
	if(self.is_injured() && istype(self.loc, /obj/item/paicard))
		self.mend(TREAT_PLATING_REPAIR, 0.5)
		self.mend(TREAT_WIRING_REPAIR, 0.5)
