// Mob statuses: the hooks and presentation the status policies name (code/library/mob/statuses.dm, which declares the status stats and
// their verbs), the per-mob rates and scaling, and voluntary sleep.

// --- Hooks named by the status policies----------------------------------------------------

/mob/proc/status_clear_facing()
	facing_dir = null

/// Stun, sleep and the end of weakness and paralysis: canmove and lying follow at once.
/mob/proc/status_incapacitation_changed()
	update_canmove()

/mob/proc/status_knocked_down()
	update_canmove()

/mob/living/status_knocked_down()
	..()
	stop_aiming(no_message = 1)

/mob/proc/status_passed_out()
	update_canmove()

/// Passing out: our AI can now control the suit.
/mob/living/carbon/human/status_passed_out()
	..()
	if(wearing_rig && !stat)
		wearing_rig.notify_ai(span_danger("Warning: user consciousness failure. Mobility control passed to integrated intelligence system."))

/mob/proc/status_sight_returned()
	return

/mob/proc/status_deafness_started()
	return

/mob/proc/status_deafness_ended()
	return

/mob/living/status_deafness_started()
	deaf_loop.start()

/mob/living/status_deafness_ended()
	deaf_loop.stop()

/mob/proc/status_dizzy_started()
	dizzy_was_resting = resting
	set_dizzy_shaking(TRUE)

/mob/proc/status_dizzy_ended()
	set_dizzy_shaking(FALSE)
	// The shaken client's view offset resets.
	if(client)
		client.pixel_x = 0
		client.pixel_y = 0

/mob/proc/status_jittery_started()
	jittery_was_resting = resting
	set_jittery_shaking(TRUE)

/mob/proc/status_jittery_ended()
	set_jittery_shaking(FALSE)
	// The jittering mob's pixel offsets reset.
	pixel_x = old_x
	pixel_y = old_y

// --- Presentation, rates and scaling ---------------------------------------------------------

/mob/status_shown(datum/status_policy/P, active)
	if(!P.alert)
		return
	if(active)
		throw_alert(P.alert, P.alert_type)
	else
		clear_alert(P.alert)

/mob/living/status_shown(datum/status_policy/P, active)
	..()
	if(P.indicator)
		if(active)
			add_status_indicator(P.indicator)
		else
			remove_status_indicator(P.indicator)

/mob/status_resting()
	return resting

/// BF_DISABLE_DURATION scales every `scaled` status (0: immune).
/mob/living/status_scale(id, amount)
	return scale_disable_duration(amount)

/// Scale a stun / weaken / paralysis / sleep / confusion / blindness duration
/// by BF_DISABLE_DURATION (0 = immune).
/mob/living/proc/scale_disable_duration(amount)
	var/scale = factor(BF_DISABLE_DURATION)
	return scale == 1 ? amount : round(amount * scale)

/// Carbons wake at their species' waking_speed.
/mob/living/carbon/status_rate(id)
	if(id == STAT_SLEEPING && species)
		return species.waking_speed
	return ..()

/// Resting your eyes with a blindfold heals blur four times as fast.
/mob/living/carbon/human/status_rate(id)
	if(id == STAT_BLURRY && wearing_blindfold())
		return 4
	return ..()

/mob/living/carbon/human/proc/wearing_blindfold()
	return istype(get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/sunglasses/blindfold)

/// Species resistances to stun and weakness apply before the modifier scaling.
/mob/living/carbon/human/status_scale(id, amount)
	switch(id)
		if(STAT_STUNNED)
			amount *= species.stun_mod
		if(STAT_WEAKENED)
			amount *= species.weaken_mod
	return ..(id, amount)

// --- Voluntary sleep ------------------------------------------------------------------------

/// TRUE while this mob sleeps by choice (the Sleep verb): a hold until it chooses to wake.
/mob/living/proc/sleeping_voluntarily()
	return held_by_source(src, STAT_SLEEPING, SRC_VOLUNTARY_SLEEP)

/mob/living/verb/mob_sleep()
	set name = "Sleep"
	set category = VERB_CAT_IC_GAME
	var/asleep = sleeping_voluntarily()
	if(!asleep)
		open_request(src, /datum/prompt/choice/voluntary_sleep, PROC_REF(sleep_confirmed), answerer = src)
		return
	toggle_voluntary_sleep()

/// Re-checked on the answer: not already sleeping by choice.
/datum/prompt/choice/voluntary_sleep
	title = "Sleepy Time"
	question = "Are you sure you wish to go to sleep? You will snooze until you use the Sleep verb again."
	choices = list("No", "Yes")
	buttons = TRUE
	timeout = 0

/datum/prompt/choice/voluntary_sleep/recheck_extra()
	. = ..()
	if(.)
		return
	var/mob/living/L = answerer
	if(!istype(L) || QDELETED(L))
		return "gone"
	return L.sleeping_voluntarily() ? "already asleep" : null

/mob/living/proc/sleep_confirmed(datum/act/request/A)
	if(!A.answer || A.answer.value != "Yes")
		return
	return apply_sleep_confirmed(A)

/mob/living/proc/apply_sleep_confirmed(datum/act/request/A)
	toggle_voluntary_sleep()

/mob/living/proc/toggle_voluntary_sleep()
	var/asleep = sleeping_voluntarily()
	asleep = !asleep
	to_chat(src, span_notice("You are [asleep ? "now sleeping. Use the Sleep verb again to wake up" : "no longer sleeping"]."))
	set_voluntary_sleep(asleep)

/// Sleeps by choice until called again with FALSE: a hold, so no dose wearing off wakes the mob
/// and ending a dose (status_set(STAT_SLEEPING, 0)) doesn't either.
/mob/living/proc/set_voluntary_sleep(asleep)
	if(asleep)
		hold(src, STAT_SLEEPING, 1, SRC_VOLUNTARY_SLEEP)
	else
		release(src, STAT_SLEEPING, SRC_VOLUNTARY_SLEEP)

/// A blindfold going on or off changes how fast blur heals.
/mob/living/carbon/human/on_equipment_changed()
	..()
	if(has_status(STAT_BLURRY))
		status_rate_check(STAT_BLURRY)
