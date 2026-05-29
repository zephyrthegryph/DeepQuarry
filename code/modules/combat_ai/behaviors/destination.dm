// Destination behavior — walks the mob toward brain.destination, then clears
// the destination on arrival. Mirrors the legacy ai_holder.give_destination()
// flow used by migration events (carp/gnat/etc), technomancer control spell,
// admin verbs, etc.

/datum/ai_behavior/walk_to_destination
	name = "walk to destination"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_TURF
	no_threat_required = TRUE

/datum/ai_behavior/walk_to_destination/evaluate(datum/ai_brain/brain, atom/source)
	var/turf/dest = brain.destination
	if(!dest)
		return null
	var/mob/living/owner = brain.get_owner()
	if(!owner)
		return null
	if(get_dist(owner, dest) == 0)
		brain.destination = null
		return null
	// Score above idle_wander/return_home but below combat.
	return DQAI_RESULT(20, dest)

/datum/ai_behavior/walk_to_destination/tick(datum/ai_brain/brain, atom/target, atom/source)
	if(!target || !brain.holder)
		return DQ_BEHAVIOR_FAILED
	if(get_dist(brain.holder, target) == 0)
		brain.destination = null
		return DQ_BEHAVIOR_DONE
	if(!brain.smart_step_toward(target, 0))
		// Fall back to direct step if A* can't find a path.
		step_to(brain.holder, target)
	return DQ_BEHAVIOR_CONTINUE

// ---------------------------------------------------------------------------
// Public API — give_destination equivalent.
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/give_destination(turf/T)
	if(!T)
		return
	destination = T
	invalidate_selection()

/datum/ai_brain/proc/clear_destination()
	destination = null
	clear_path()
	invalidate_selection()
