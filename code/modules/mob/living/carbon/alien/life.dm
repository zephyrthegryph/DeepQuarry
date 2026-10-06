// Alien larva are quite simple.
/mob/living/carbon/alien/life_type_pre_due()
	return TRUE

/mob/living/carbon/alien/life_type_pre(datum/seq_frame/life/F)
	if (src.transforming)	return F.abort()
	if(!src.loc)			return F.abort()
	return ..()

/// Growth, blindness reset and icons after the living core (the old alien Life() tail).
/mob/living/carbon/alien/proc/life_alien_growth(datum/seq_frame/life/F)
	if (src.stat != DEAD) //still breathing
		// GROW!
		src.update_progression()

	src.set_blinded(null)

	//Status updates, death etc.
	src.update_icons()

/mob/living/carbon/alien/life_radiation_due()
	return TRUE

/mob/living/carbon/alien/life_radiation(datum/seq_frame/life/F)
	. = ..()
	if(.)
		return

	// Currently both Dionaea and larvae like to eat radiation, so I'm defining the
	// rad absorbtion here. This will need to be changed if other baby aliens are added.

	if(!src.radiation)
		return

	var/rads = src.radiation/25
	src.decay_radiation(rads)
	//adjust_nutrition(rads) //Commented out to prevent alien obesity.
	src.mend(TREAT_TISSUE_REPAIR, rads)
	src.mend(TREAT_BURN_CARE, rads)
	src.mend(TREAT_OXYGENATION, rads)
	src.mend(TREAT_ANTITOXIN, rads)
	return

/mob/living/carbon/alien/life_status_due()
	return TRUE

/mob/living/carbon/alien/life_status_update_status()

	if(om_has(src, EFFECT_GODMODE)) //I don't want to go in and do HUD stuff imediately, so... no.
		return 0	// Cancelled by a component

	// Death from injury is decided by the (simple) body.
	if(src.stat != DEAD)
		src.body?.life_tick()

	if(src.stat == DEAD)
		src.set_blinded(1)
		src.status_set(EFFECT_MUTED, 0)
		src.deaf_loop.stop() // Ear Ringing/Deafness - Not sure if we need this, but, safety.
	else
		if(src.has_status(EFFECT_PARALYZED))
			src.set_blinded(1)
			src.set_stat(UNCONSCIOUS)

		if(src.has_status(EFFECT_SLEEPING))
			// Sleep wears off only while a player is home; an empty body stays asleep.
			if(!src.mind?.active || !src.client)
				src.status_at_least(EFFECT_SLEEPING, 1)
			src.set_blinded(1)
			src.set_stat(UNCONSCIOUS)
		else if(!src.resting)
			src.set_stat(CONSCIOUS)

		// Eyes and blindness. Temporary blindness and blur wear off on their own.
		if(!src.has_eyes())
			src.status_set(EFFECT_BLINDED, 1)
			src.set_blinded(1)
			src.status_set(EFFECT_BLURRY, 1)
		else if(src.has_status(EFFECT_BLINDED))
			src.set_blinded(1)

		src.update_icons()

	return 1


/mob/living/carbon/alien/life_vision()
	if (src.stat == 2 || (src.has_mutation(XRAY)))
		src.sight |= SEE_TURFS
		src.sight |= SEE_MOBS
		src.sight |= SEE_OBJS
		src.see_in_dark = 8
		src.see_invisible = SEE_INVISIBLE_LEVEL_TWO
	else if (src.stat != 2)
		src.sight &= ~SEE_TURFS
		src.sight &= ~SEE_MOBS
		src.sight &= ~SEE_OBJS
		src.see_in_dark = 2
		src.see_invisible = SEE_INVISIBLE_LIVING

	// Call parent to handle signals
	..()


/// Its own HUD stays awake (rerun every Life cycle while it has a client).
/mob/living/carbon/alien/life_hud_idle()
	return FALSE

/mob/living/carbon/alien/life_hud()
	. = ..()
	if(!.)
		return

	src.client.screen.Remove(GLOB.global_hud.blurry,GLOB.global_hud.druggy,GLOB.global_hud.vimpaired)

	if ( src.stat != 2)
		if ((src.blinded))
			src.overlay_fullscreen("blind", /atom/movable/screen/fullscreen/blind)
		else
			src.clear_fullscreen("blind")
			src.set_fullscreen(src.is_nearsighted(), "impaired", /atom/movable/screen/fullscreen/impaired, 1)
			src.set_fullscreen(src.status_units(EFFECT_BLURRY), "blurry", /atom/movable/screen/fullscreen/blurry)
			src.set_fullscreen(src.status_units(EFFECT_DRUGGED), "high", /atom/movable/screen/fullscreen/high)

/mob/living/carbon/alien/life_hud_health_icons()
	. = ..()
	if(!. || !src.healths)
		return

	src.healths.icon_state = vitality_health_band(src)

/mob/living/carbon/alien/life_environment_due()
	return TRUE

/mob/living/carbon/alien/life_environment_exchange(datum/gas_mixture/environment)
	// Both alien subtypes survive in vaccum and suffer in high temperatures,
	// so I'll just define this once, for both (see radiation comment above)
	if(!environment) return

	var/environment_temp = environment.return_temperature()
	if(environment_temp > (T0C+66))
		src.injure(INJURY_BURN, (environment_temp - (T0C+66)) / 5, null, null, 0, null, INJURE_SILENT | INJURE_CONTINUOUS) // Might be too high, check in testing.
		src.throw_alert("alien_fire", /atom/movable/screen/alert/alien_fire)
		if(prob(20))
			to_chat(src, span_red("You feel a searing heat!"))
	else
		src.clear_alert("alien_fire")

/mob/living/carbon/alien/on_fire_stack(seconds_per_tick, datum/status_effect/fire_handler/fire_stacks/fire_handler)
	adjust_bodytemperature(BODYTEMP_HEATING_MAX)
