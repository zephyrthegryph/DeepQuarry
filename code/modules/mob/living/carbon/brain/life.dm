// The view has no health life of its own: it doesn't breathe, metabolise,
// feel the environment or take radiation. Its status comes from the brain
// tissue of its mind host (refresh_host_status()); what's left here is what a
// client in a container needs: EMP interference on an MMI's I/O, vision and HUD.

/datum/life_system/breathing/carbon/brain
	mob_type = /mob/living/carbon/brain

/datum/life_system/breathing/carbon/brain/tick(mob/living/carbon/brain/self, datum/life_context/ctx)
	return

/datum/life_system/radiation/carbon/brain
	mob_type = /mob/living/carbon/brain

/datum/life_system/radiation/carbon/brain/applies(mob/living/carbon/brain/self)
	return FALSE

/datum/life_system/environment/carbon/brain
	mob_type = /mob/living/carbon/brain

/datum/life_system/environment/carbon/brain/tick(mob/living/carbon/brain/self, datum/life_context/ctx)
	return

/datum/life_system/chemicals/carbon/brain
	mob_type = /mob/living/carbon/brain

/datum/life_system/chemicals/carbon/brain/tick(mob/living/carbon/brain/self, datum/life_context/ctx)
	return

/datum/life_system/status/carbon/brain
	mob_type = /mob/living/carbon/brain

/datum/life_system/status/carbon/brain/update_status(mob/living/carbon/brain/self)
	if(self.host)
		self.refresh_host_status()
	else if(self.stat != DEAD)
		self.body?.life_tick() // tissue-less views (souls) keep a simple body

	if(self.stat == DEAD)
		self.blinded = 1
		self.silent = 0
		self.deaf_loop.stop()
		return 1

	self.handle_emp_interference()
	return 1

/// EMP interference with an MMI's sensors and speech. Not damage: the MMI's
/// I/O reboots over a few ticks.
/mob/living/carbon/brain/proc/handle_emp_interference()
	if(!emp_damage)
		return
	if(!istype(container, /obj/item/mmi))
		emp_damage = 0
		return
	emp_damage = round(emp_damage, 1)
	switch(emp_damage)
		if(31 to INFINITY)
			emp_damage = 30//Let's not overdo it
		if(21 to 30)//High level of EMP damage, unable to see, hear, or speak
			SetBlinded(1)
			blinded = 1
			ear_deaf = 1
			deaf_loop.start()
			silent = 1
			if(!alert)//Sounds an alarm, but only once per 'level'
				emote("alarm")
				to_chat(src, span_red("Major electrical distruption detected: System rebooting."))
				alert = 1
			if(prob(75))
				emp_damage -= 1
		if(20)
			alert = 0
			blinded = 0
			SetBlinded(0)
			ear_deaf = 0
			deaf_loop.stop()
			silent = 0
			emp_damage -= 1
		if(11 to 19)//Moderate level of EMP damage, resulting in nearsightedness and ear damage
			eye_blurry = 1
			ear_damage = 1
			if(!alert)
				emote("alert")
				to_chat(src, span_red("Primary systems are now online."))
				alert = 1
			if(prob(50))
				emp_damage -= 1
		if(10)
			alert = 0
			eye_blurry = 0
			ear_damage = 0
			emp_damage -= 1
		if(2 to 9)//Low level of EMP damage, has few effects(handled elsewhere)
			if(!alert)
				emote("notice")
				to_chat(src, span_red("System reboot nearly complete."))
				alert = 1
			if(prob(25))
				emp_damage -= 1
		if(1)
			alert = 0
			to_chat(src, span_red("All systems restored."))
			emp_damage -= 1

/datum/life_system/vision/carbon/brain
	mob_type = /mob/living/carbon/brain

/datum/life_system/vision/carbon/brain/tick(mob/living/carbon/brain/self, datum/life_context/ctx)
	if (self.stat == DEAD || (self.has_mutation(XRAY)))
		self.sight |= SEE_TURFS
		self.sight |= SEE_MOBS
		self.sight |= SEE_OBJS
		self.see_in_dark = 8
		self.see_invisible = SEE_INVISIBLE_LEVEL_TWO
	else if (self.stat != DEAD)
		self.sight &= ~SEE_TURFS
		self.sight &= ~SEE_MOBS
		self.sight &= ~SEE_OBJS
		self.see_in_dark = 2
		self.see_invisible = SEE_INVISIBLE_LIVING

	// Call parent to handle signals
	..()

/datum/life_system/hud/carbon/brain
	mob_type = /mob/living/carbon/brain

/datum/life_system/hud/carbon/brain/tick(mob/living/carbon/brain/self, datum/life_context/ctx)
	. = ..()
	if(!.)
		return

	self.client.screen.Remove(GLOB.global_hud.blurry,GLOB.global_hud.druggy,GLOB.global_hud.vimpaired)

	if (self.stat != DEAD)
		if ((self.blinded))
			self.overlay_fullscreen("blind", /atom/movable/screen/fullscreen/blind)
		else
			self.clear_fullscreen("blind")
			self.set_fullscreen(self.disabilities & NEARSIGHTED, "impaired", /atom/movable/screen/fullscreen/impaired, 1)
			self.set_fullscreen(self.eye_blurry, "blurry", /atom/movable/screen/fullscreen/blurry)
			self.set_fullscreen(self.druggy, "high", /atom/movable/screen/fullscreen/high)

/datum/life_system/hud/carbon/brain/health_icons(mob/living/carbon/brain/self)
	. = ..()
	if(!. || !self.healths)
		return

	if(self.stat == DEAD || (self.status_flags & FAKEDEATH))
		self.healths.icon_state = "health7"
		return

	switch(self.vitality() * 100)
		if(100 to INFINITY)
			self.healths.icon_state = "health0"
		if(80 to 100)
			self.healths.icon_state = "health1"
		if(60 to 80)
			self.healths.icon_state = "health2"
		if(40 to 60)
			self.healths.icon_state = "health3"
		if(20 to 40)
			self.healths.icon_state = "health4"
		if(0 to 20)
			self.healths.icon_state = "health5"
		else
			self.healths.icon_state = "health6"
