/mob/living/silicon/pai
	life_set = LIFE_SET_PAI

/// Cable retraction and `if(stat == DEAD) return`.
/datum/om/stage/life/pai_cable
	order = LIFE_PHASE_INPUT + 0
	name = "pai cable"
	wake_on = 0
	life_sets = LIFE_SET_PAI
	of = /mob/living/silicon/pai

/datum/om/stage/life/pai_cable/perform(mob/living/silicon/pai/self, datum/om/frame/life/ctx)
	self.check_retract_cable()

	if(self.stat == DEAD)
		return ctx.abort()

/// Death from injury is decided by the body (see death.dm for card damage); card faults.
/datum/om/stage/life/pai_body
	order = LIFE_PHASE_INPUT + 10
	name = "pai body"
	wake_on = CHANGE_MOB_HEALTH
	life_sets = LIFE_SET_PAI
	of = /mob/living/silicon/pai

/datum/om/stage/life/pai_body/perform(mob/living/silicon/pai/self, datum/om/frame/life/ctx)
	self.body?.life_tick()
	if(self.stat == DEAD)
		return ctx.abort()

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
/datum/om/stage/life/pai_silence
	order = LIFE_PHASE_OUTPUT + 40
	name = "pai silence"
	wake_on = 0
	life_sets = LIFE_SET_PAI
	of = /mob/living/silicon/pai

/datum/om/stage/life/pai_silence/perform(mob/living/silicon/pai/self, datum/om/frame/life/ctx)
	if(self.silence_time)
		if(world.timeofday >= self.silence_time)
			self.silence_time = null
			to_chat(self, span_green("Communication circuit reinitialized. Speech and messaging functionality restored."))

/// Folded into the card, the pAI slowly self-repairs.
/datum/om/stage/life/pai_repair
	order = LIFE_PHASE_OUTPUT + 60
	name = "pai repair"
	wake_on = CHANGE_MOB_HEALTH
	life_sets = LIFE_SET_PAI
	of = /mob/living/silicon/pai

/datum/om/stage/life/pai_repair/perform(mob/living/silicon/pai/self, datum/om/frame/life/ctx)
	if(self.is_injured() && istype(self.loc, /obj/item/paicard))
		self.mend(TREAT_PLATING_REPAIR, 0.5)
		self.mend(TREAT_WIRING_REPAIR, 0.5)
