// The view has no health life of its own: it doesn't breathe, metabolise,
// feel the environment or take radiation. Its status comes from the brain
// tissue of its mind host (refresh_host_status()); what's left here is what a
// client in a container needs: EMP interference on an MMI's I/O, vision and HUD.

/mob/living/carbon/brain/handle_breathing()
	return

/mob/living/carbon/brain/handle_radiation()
	return

/mob/living/carbon/brain/handle_environment(datum/gas_mixture/environment)
	return

/mob/living/carbon/brain/handle_chemicals_in_body()
	return

/mob/living/carbon/brain/handle_regular_status_updates()
	if(host)
		refresh_host_status()
	else if(stat != DEAD)
		body?.life_tick() // tissue-less views (souls) keep a simple body

	if(stat == DEAD)
		blinded = 1
		silent = 0
		deaf_loop.stop()
		return 1

	handle_emp_interference()
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

/mob/living/carbon/brain/handle_vision()
	if (stat == DEAD || (XRAY in src.mutations))
		sight |= SEE_TURFS
		sight |= SEE_MOBS
		sight |= SEE_OBJS
		see_in_dark = 8
		see_invisible = SEE_INVISIBLE_LEVEL_TWO
	else if (stat != DEAD)
		sight &= ~SEE_TURFS
		sight &= ~SEE_MOBS
		sight &= ~SEE_OBJS
		see_in_dark = 2
		see_invisible = SEE_INVISIBLE_LIVING

	// Call parent to handle signals
	..()

/mob/living/carbon/brain/handle_regular_hud_updates()
	. = ..()
	if(!.)
		return

	client.screen.Remove(GLOB.global_hud.blurry,GLOB.global_hud.druggy,GLOB.global_hud.vimpaired)

	if (stat != DEAD)
		if ((blinded))
			overlay_fullscreen("blind", /atom/movable/screen/fullscreen/blind)
		else
			clear_fullscreen("blind")
			set_fullscreen(disabilities & NEARSIGHTED, "impaired", /atom/movable/screen/fullscreen/impaired, 1)
			set_fullscreen(eye_blurry, "blurry", /atom/movable/screen/fullscreen/blurry)
			set_fullscreen(druggy, "high", /atom/movable/screen/fullscreen/high)

/mob/living/carbon/brain/handle_hud_icons_health()
	. = ..()
	if(!. || !healths)
		return

	if(stat == DEAD || (status_flags & FAKEDEATH))
		healths.icon_state = "health7"
		return

	switch(vitality() * 100)
		if(100 to INFINITY)
			healths.icon_state = "health0"
		if(80 to 100)
			healths.icon_state = "health1"
		if(60 to 80)
			healths.icon_state = "health2"
		if(40 to 60)
			healths.icon_state = "health3"
		if(20 to 40)
			healths.icon_state = "health4"
		if(0 to 20)
			healths.icon_state = "health5"
		else
			healths.icon_state = "health6"
