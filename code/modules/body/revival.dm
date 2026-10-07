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
		var/obj/item/organ/internal/brain/brain = organ_in(O_BRAIN)
		if(!brain)
			return "no brain"
		if(istype(brain)) // Some species have 'brains' that aren't brains and have no decay timer.
			if(brain.is_brain_dead())
				return "brain dead"
			if(brain.defib_window_left() <= 0)
				return "brain decayed"
	if(HUSK in mutations)
		return "husked"
	if(!can_defib)
		return "brain stem"
	var/bad_vital_organ = check_vital_organs()
	if(bad_vital_organ)
		return "[bad_vital_organ] failed"
	return null

/// Deciseconds of biological time left to revive this dead mob, or null when nothing limits it.
/mob/living/proc/revival_window_left()
	return null

/mob/living/carbon/human/revival_window_left()
	var/obj/item/organ/internal/brain/brain = organ_in(O_BRAIN)
	return istype(brain) ? brain.defib_window_left() : null

/// The defib window stops running down (and starts recovering) at revival (audit D10).
/mob/living/carbon/human/on_revived(reason, datum/source)
	. = ..()
	var/obj/item/organ/internal/brain/brain = organ_in(O_BRAIN)
	if(istype(brain))
		brain.sync_defib_window()

/// REVIVE_RESTORE: rebuild what would refuse a revival. The base mob has nothing to rebuild.
/mob/living/proc/restore_for_revival()
	log_game("REVIVE RESTORE: [key_name(src)] ([type]) rebuilt for revival.")

/// Humans: replace missing vital organs, clear brain death, decay, husking and brain-stem damage.
/mob/living/carbon/human/restore_for_revival()
	..()
	for(var/organ_tag in species.has_organ)
		var/organ_type = species.has_organ[organ_tag]
		var/obj/item/organ/prototype = organ_type
		if(!initial(prototype.vital) || organ_in(organ_tag))
			continue
		// Born inside us, the organ places itself (ledger attach hook); set_organ_tag() rekeys
		// its slot and our caches when the species files it under a non-default tag.
		var/obj/item/organ/O = new organ_type(src, 1)
		if(O.organ_tag != organ_tag)
			O.set_organ_tag(organ_tag)
		log_game("REVIVE RESTORE: [key_name(src)] regrew missing vital organ [organ_tag].")
	restore_all_organs()
	for(var/obj/item/organ/internal/I in internal_organ_list())
		I.rejuvenate()
	var/obj/item/organ/internal/brain/brain = organ_in(O_BRAIN)
	if(istype(brain))
		brain.set_status(brain.status & ~ORGAN_DEAD)
		brain.set_damage(0)
		brain.reset_defib_window()
	remove_mutation(HUSK)
	set_status_flags(status_flags & ~DISFIGURED)
	can_defib = TRUE
	update_icons_body()

/// Vore reform: the stored body comes back fully restored, never refused. Rebuild what would
/// refuse (REVIVE_RESTORE), revive through the one path, then heal to rejuvenate level.
/mob/living/carbon/human/proc/reform_restore(reason, datum/source)
	if(stat == DEAD)
		var/revived = return_from_death(reason, source, REVIVE_RESTORE | REVIVE_IGNORE_WINDOW | REVIVE_HEAL)
		if(revived != TRUE)
			stack_trace("reform of [key_name(src)] refused despite REVIVE_RESTORE: [revived]")
	rejuvenate()

/// The only way a dead mob becomes alive. Returns TRUE on success, or the refusal reason (a
/// string) from can_return_from_death(). `reason` is logged; `source` is what did it (defib,
/// spell, admin, reagent). `flags` are REVIVE_* (code/__defines/vital_state.dm).
/mob/living/proc/return_from_death(reason, datum/source, flags = NONE)
	// 1. Rebuild and heal first when asked.
	if((flags & REVIVE_RESTORE) && stat == DEAD && !QDELETED(src))
		restore_for_revival()
	if(flags & (REVIVE_HEAL | REVIVE_RESTORE))
		fully_heal()

	// 2. Eligibility.
	var/refusal = can_return_from_death(flags)
	if(refusal)
		log_game("REVIVE REFUSED: [key_name(src)] by [source ? "[source] ([source.type])" : "nothing"] ([reason]): [refusal].")
		return refusal

	// 3. Lists and time of death.
	registry_leave(REGISTRY_DEAD_MOBS, src)
	registry_join(REGISTRY_LIVING_MOBS, src)
	if(!(flags & REVIVE_KEEP_TIMEOFDEATH))
		EXPIRY_CLEAR(src, timeofdeath)
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
	flag_hud_update(HEALTH_HUD)
	flag_hud_update(STATUS_HUD)
	flag_hud_update(LIFE_HUD)

	// 6. Subtype contributions, then everything else.
	on_revived(reason, source)
	// The HUD and sight redraw by themselves: set_stat() published nameof(stat), flag_hud_update() MOB_KEY_HUD_FLAGS.
	redraw(src)
	// set_stat() raised CHANGE_MOB_STAT, which wakes every Life stage (LIFE_WAKE_ALL).
	PUBLISH_LEGACY(src, /datum/notice/living_revived, source, reason)
	log_game("REVIVE: [key_name(src)] by [source ? "[source] ([source.type])" : "nothing"] ([reason]) at [AREACOORD(src)].")
	return TRUE

/// Subtype contributions to coming back: undo what on_death() did (verbs, density, glow, camera
/// and cult vision). The mob is already alive and listed as living.
/mob/living/proc/on_revived(reason, datum/source)
	SHOULD_CALL_PARENT(TRUE)
	GLOB.cultnet.updateVisibility(src, 0)
