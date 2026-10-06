// The view has no health life of its own: it doesn't breathe, metabolise,
// feel the environment or take radiation. Its status comes from the brain
// tissue of its mind host (refresh_host_status()); what's left here is what a
// client in a container needs: EMP interference on an MMI's I/O, vision and HUD.

/mob/living/carbon/brain/life_breathing(datum/seq_frame/life/F)
	return

/mob/living/carbon/brain/life_radiation_due()
	return TRUE

/mob/living/carbon/brain/life_radiation_applies()
	return FALSE

/mob/living/carbon/brain/life_environment_due()
	return TRUE

/mob/living/carbon/brain/life_environment(datum/seq_frame/life/F)
	return

/mob/living/carbon/brain/life_chemicals_due()
	return TRUE

/mob/living/carbon/brain/life_chemicals(datum/seq_frame/life/F)
	return

/// A hosted view's status follows its tissue, which tells it through refresh_host_status()
/// (removal, insertion, injure, mend); a slow rewake covers drift. Awake while EMP interference
/// is wearing off.
/mob/living/carbon/brain/life_status_due()
	if(src.emp_damage)
		return TRUE
	if(src.host)
		return FALSE
	return src.stat != DEAD && src.body && !src.body.life_settled()

/mob/living/carbon/brain/life_status_rewake()
	return src.host ? 5 SECONDS : 0

/mob/living/carbon/brain/life_status_update_status()
	if(src.host)
		src.refresh_host_status()
	else if(src.stat != DEAD)
		src.body?.life_tick() // tissue-less views (souls) keep a simple body

	if(src.stat == DEAD)
		src.set_blinded(1)
		src.status_set(EFFECT_MUTED, 0)
		src.deaf_loop.stop()
		return 1

	src.handle_emp_interference()
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
			status_set(EFFECT_BLINDED, 1)
			set_blinded(1)
			status_set(EFFECT_DEAFENED, 1)
			status_set(EFFECT_MUTED, 1)
			if(!alert)//Sounds an alarm, but only once per 'level'
				emote("alarm")
				to_chat(src, span_red("Major electrical distruption detected: System rebooting."))
				alert = 1
			if(prob(75))
				emp_damage -= 1
		if(20)
			alert = 0
			set_blinded(0)
			status_set(EFFECT_BLINDED, 0)
			status_set(EFFECT_DEAFENED, 0)
			status_set(EFFECT_MUTED, 0)
			emp_damage -= 1
		if(11 to 19)//Moderate level of EMP damage, resulting in nearsightedness and ear damage
			status_set(EFFECT_BLURRY, 1)
			set_ear_damage(1)
			if(!alert)
				emote("alert")
				to_chat(src, span_red("Primary systems are now online."))
				alert = 1
			if(prob(50))
				emp_damage -= 1
		if(10)
			alert = 0
			status_set(EFFECT_BLURRY, 0)
			set_ear_damage(0)
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


/mob/living/carbon/brain/life_vision()
	if (src.stat == DEAD || (src.has_mutation(XRAY)))
		src.sight |= SEE_TURFS
		src.sight |= SEE_MOBS
		src.sight |= SEE_OBJS
		src.see_in_dark = 8
		src.see_invisible = SEE_INVISIBLE_LEVEL_TWO
	else if (src.stat != DEAD)
		src.sight &= ~SEE_TURFS
		src.sight &= ~SEE_MOBS
		src.sight &= ~SEE_OBJS
		src.see_in_dark = 2
		src.see_invisible = SEE_INVISIBLE_LIVING

	// Call parent to handle signals
	..()


/// Its own HUD stays awake (rerun every Life cycle while it has a client).
/mob/living/carbon/brain/life_hud_idle()
	return FALSE

/mob/living/carbon/brain/life_hud()
	. = ..()
	if(!.)
		return

	src.client.screen.Remove(GLOB.global_hud.blurry,GLOB.global_hud.druggy,GLOB.global_hud.vimpaired)

	if (src.stat != DEAD)
		if ((src.blinded))
			src.overlay_fullscreen("blind", /atom/movable/screen/fullscreen/blind)
		else
			src.clear_fullscreen("blind")
			src.set_fullscreen(src.is_nearsighted(), "impaired", /atom/movable/screen/fullscreen/impaired, 1)
			src.set_fullscreen(src.status_units(EFFECT_BLURRY), "blurry", /atom/movable/screen/fullscreen/blurry)
			src.set_fullscreen(src.status_units(EFFECT_DRUGGED), "high", /atom/movable/screen/fullscreen/high)

/mob/living/carbon/brain/life_hud_health_icons()
	. = ..()
	if(!. || !src.healths)
		return

	src.healths.icon_state = vitality_health_band(src)
