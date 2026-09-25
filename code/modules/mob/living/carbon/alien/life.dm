// Alien larva are quite simple.
/datum/om/stage/life/type_pre/carbon/alien
	of = /mob/living/carbon/alien

/datum/om/stage/life/type_pre/carbon/alien/perform(mob/living/carbon/alien/self, datum/om/frame/life/ctx)
	if (self.transforming)	return ctx.abort()
	if(!self.loc)			return ctx.abort()
	return ..()

/// Growth, blindness reset and icons after the living core (the old alien Life() tail).
/datum/om/stage/life/alien_growth
	order = LIFE_PHASE_TAIL + 100
	name = "alien growth"
	wake_on = CHANGE_MOB_HEALTH
	of = /mob/living/carbon/alien

/datum/om/stage/life/alien_growth/perform(mob/living/carbon/alien/self, datum/om/frame/life/ctx)
	if (self.stat != DEAD) //still breathing
		// GROW!
		self.update_progression()

	self.blinded = null

	//Status updates, death etc.
	self.update_icons()

/datum/om/stage/life/radiation/carbon/alien
	of = /mob/living/carbon/alien

/datum/om/stage/life/radiation/carbon/alien/perform(mob/living/carbon/alien/self, datum/om/frame/life/ctx)
	. = ..()
	if(.)
		return

	// Currently both Dionaea and larvae like to eat radiation, so I'm defining the
	// rad absorbtion here. This will need to be changed if other baby aliens are added.

	if(!self.radiation)
		return

	var/rads = self.radiation/25
	self.radiation -= rads
	//adjust_nutrition(rads) //Commented out to prevent alien obesity.
	self.mend(TREAT_TISSUE_REPAIR, rads)
	self.mend(TREAT_BURN_CARE, rads)
	self.mend(TREAT_OXYGENATION, rads)
	self.mend(TREAT_ANTITOXIN, rads)
	return

/datum/om/stage/life/status/carbon/alien
	of = /mob/living/carbon/alien

/datum/om/stage/life/status/carbon/alien/update_status(mob/living/carbon/alien/self)

	if(om_has(self, EFFECT_GODMODE)) //I don't want to go in and do HUD stuff imediately, so... no.
		return 0	// Cancelled by a component

	// Death from injury is decided by the (simple) body.
	if(self.stat != DEAD)
		self.body?.life_tick()

	if(self.stat == DEAD)
		self.blinded = 1
		self.status_set(EFFECT_MUTED, 0)
		self.deaf_loop.stop() // Ear Ringing/Deafness - Not sure if we need this, but, safety.
	else
		if(self.has_status(EFFECT_PARALYZED))
			self.blinded = 1
			self.set_stat(UNCONSCIOUS)

		if(self.has_status(EFFECT_SLEEPING))
			// Sleep wears off only while a player is home; an empty body stays asleep.
			if(!self.mind?.active || !self.client)
				self.status_at_least(EFFECT_SLEEPING, 1)
			self.blinded = 1
			self.set_stat(UNCONSCIOUS)
		else if(!self.resting)
			self.set_stat(CONSCIOUS)

		// Eyes and blindness. Temporary blindness and blur wear off on their own.
		if(!self.has_eyes())
			self.status_set(EFFECT_BLINDED, 1)
			self.blinded =    1
			self.status_set(EFFECT_BLURRY, 1)
		else if(self.has_status(EFFECT_BLINDED))
			self.blinded =    1

		self.update_icons()

	return 1

/datum/om/stage/life/vision/carbon/alien
	of = /mob/living/carbon/alien

/datum/om/stage/life/vision/carbon/alien/perform(mob/living/carbon/alien/self, datum/om/frame/life/ctx)
	if (self.stat == 2 || (self.has_mutation(XRAY)))
		self.sight |= SEE_TURFS
		self.sight |= SEE_MOBS
		self.sight |= SEE_OBJS
		self.see_in_dark = 8
		self.see_invisible = SEE_INVISIBLE_LEVEL_TWO
	else if (self.stat != 2)
		self.sight &= ~SEE_TURFS
		self.sight &= ~SEE_MOBS
		self.sight &= ~SEE_OBJS
		self.see_in_dark = 2
		self.see_invisible = SEE_INVISIBLE_LIVING

	// Call parent to handle signals
	..()

/datum/om/stage/life/hud/carbon/alien
	of = /mob/living/carbon/alien

/datum/om/stage/life/hud/carbon/alien/perform(mob/living/carbon/alien/self, datum/om/frame/life/ctx)
	. = ..()
	if(!.)
		return

	self.client.screen.Remove(GLOB.global_hud.blurry,GLOB.global_hud.druggy,GLOB.global_hud.vimpaired)

	if ( self.stat != 2)
		if ((self.blinded))
			self.overlay_fullscreen("blind", /atom/movable/screen/fullscreen/blind)
		else
			self.clear_fullscreen("blind")
			self.set_fullscreen(self.disabilities & NEARSIGHTED, "impaired", /atom/movable/screen/fullscreen/impaired, 1)
			self.set_fullscreen(self.status_units(EFFECT_BLURRY), "blurry", /atom/movable/screen/fullscreen/blurry)
			self.set_fullscreen(self.status_units(EFFECT_DRUGGED), "high", /atom/movable/screen/fullscreen/high)

/datum/om/stage/life/hud/carbon/alien/health_icons(mob/living/carbon/alien/self)
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

/datum/om/stage/life/environment/carbon/alien
	of = /mob/living/carbon/alien

/datum/om/stage/life/environment/carbon/alien/exchange(mob/living/carbon/alien/self, datum/gas_mixture/environment)
	// Both alien subtypes survive in vaccum and suffer in high temperatures,
	// so I'll just define this once, for both (see radiation comment above)
	if(!environment) return

	var/environment_temp = environment.return_temperature()
	if(environment_temp > (T0C+66))
		self.injure(INJURY_BURN, (environment_temp - (T0C+66))/5, null, null, 0, null, INJURE_SILENT) // Might be too high, check in testing.
		self.throw_alert("alien_fire", /atom/movable/screen/alert/alien_fire)
		if(prob(20))
			to_chat(self, span_red("You feel a searing heat!"))
	else
		self.clear_alert("alien_fire")

/mob/living/carbon/alien/on_fire_stack(seconds_per_tick, datum/status_effect/fire_handler/fire_stacks/fire_handler)
	bodytemperature += BODYTEMP_HEATING_MAX
