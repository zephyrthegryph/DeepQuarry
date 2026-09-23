// The one revive path. A dead mob becomes alive only through return_from_death(); death goes
// through the sealed /mob/proc/death() pipeline (code/modules/mob/death.dm). /mob/living/set_stat()
// refuses DEAD -> alive anywhere else, and tools/ci/check_grep.sh rejects the hand-rolled
// list swaps (dead_mob_list -=, living_mob_list +=, timeofdeath = 0).

/// Can this mob come back? Returns null when it can, or the reason it can't (a short string).
/// REVIVE_IGNORE_WINDOW skips the revival window (brain decay, brain stem, husk, vital organs);
/// lethal injuries always refuse.
/mob/living/proc/can_return_from_death(flags = NONE)
	if(QDELETED(src))
		return "deleted"
	if(stat != DEAD)
		return "not dead"
	if(body?.is_lethal())
		return "lethal injuries"
	if(!(flags & REVIVE_IGNORE_WINDOW))
		var/window = revival_window_refusal()
		if(window)
			return window
	return null

/// Why the revival window is closed for this mob, or null if it is open. Subtypes with a brain
/// or other time-limited organs override.
/mob/living/proc/revival_window_refusal()
	return null

/mob/living/carbon/human/revival_window_refusal()
	if(should_have_organ(O_BRAIN))
		var/obj/item/organ/internal/brain/brain = internal_organs_by_name[O_BRAIN]
		if(!brain)
			return "no brain"
		if(istype(brain)) // Some species have 'brains' that aren't brains and have no decay timer.
			if(brain.is_brain_dead())
				return "brain dead"
			if(brain.defib_timer <= 0)
				return "brain decayed"
	if(HUSK in mutations)
		return "husked"
	if(!can_defib)
		return "brain stem"
	var/bad_vital_organ = check_vital_organs()
	if(bad_vital_organ)
		return "[bad_vital_organ] failed"
	return null

/// The only way a dead mob becomes alive. Returns TRUE on success, or the refusal reason (a
/// string) from can_return_from_death(). `reason` is logged; `source` is what did it (defib,
/// spell, admin, reagent). `flags` are REVIVE_* (code/__defines/vital_state.dm).
/mob/living/proc/return_from_death(reason, datum/source, flags = NONE)
	// 1. Heal first when asked.
	if(flags & REVIVE_HEAL)
		fully_heal()

	// 2. Eligibility.
	var/refusal = can_return_from_death(flags)
	if(refusal)
		log_game("REVIVE REFUSED: [key_name(src)] by [source ? "[source] ([source.type])" : "nothing"] ([reason]): [refusal].")
		return refusal

	// 3. Lists and time of death.
	GLOB.dead_mob_list -= src
	GLOB.living_mob_list |= src
	if(!(flags & REVIVE_KEEP_TIMEOFDEATH))
		timeofdeath = 0
		tod = null
	failed_last_breath = 0

	// 4. The one stat transition back.
	revival_in_progress = TRUE
	set_stat((flags & REVIVE_UNCONSCIOUS) ? UNCONSCIOUS : CONSCIOUS)
	revival_in_progress = FALSE
	body?.on_status_changed()

	// 5. Undo what death() did to the senses and screen.
	sight = initial(sight)
	see_in_dark = initial(see_in_dark)
	see_invisible = initial(see_invisible)
	ai_brain?.go_wake()
	reload_fullscreen()
	reset_perspective()
	update_canmove()
	mark_hud_dirty(HEALTH_HUD)
	mark_hud_dirty(STATUS_HUD)
	mark_hud_dirty(LIFE_HUD)

	// 6. Subtype contributions, then everything else.
	on_revived(reason, source)
	refresh_hud()
	refresh_vision()
	update_icon()
	life_wake(LIFE_SYS_ALL, "revived")
	SEND_SIGNAL(src, COMSIG_LIVING_REVIVED, source, reason)
	log_game("REVIVE: [key_name(src)] by [source ? "[source] ([source.type])" : "nothing"] ([reason]) at [AREACOORD(src)].")
	return TRUE

/// Subtype contributions to coming back: undo what on_death() did (verbs, density, glow, camera
/// and cult vision). The mob is already alive and listed as living.
/mob/living/proc/on_revived(reason, datum/source)
	SHOULD_CALL_PARENT(TRUE)
	GLOB.cultnet.updateVisibility(src, 0)
