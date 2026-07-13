// Public brain API — methods external systems call to manipulate AI state.
//
// This file exists so non-AI code (vore mobs, gaia, telesci, capture crystal,
// admin verbs, simple_mob subtypes) doesn't need to know about behaviors or
// the brain's internals. It mirrors the surface of the legacy /datum/ai_holder
// that callers were using.

// ---------------------------------------------------------------------------
// Target management
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/give_target(mob/M, urgent = FALSE)
	if(!M)
		return
	primary_threat = M
	add_personal(M, DQ_DISPOSITION_HOSTILE, 60 SECONDS, "given_target")
	update_engagement() // engage the fast tick immediately (lord command / external aggro)
	if(urgent)
		invalidate_selection()

/datum/ai_brain/proc/lose_target()
	lose_threat_at = 0
	if(primary_threat)
		var/old = primary_threat
		primary_threat = null
		SEND_SIGNAL(holder, COMSIG_DQAI_TARGET_LOST, old)
		invalidate_selection()
		update_engagement() // no threat → drop off the fast tick

/// Legacy name for lose_target — kept so direct sed-style migrations work.
/datum/ai_brain/proc/remove_target()
	lose_target()

/datum/ai_brain/proc/forget_everything()
	lose_target()
	personal = null
	clear_path()
	leader_ref = null

// ---------------------------------------------------------------------------
// Following / leader
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/set_follow(mob/leader)
	set_leader(leader)
	invalidate_selection()

/datum/ai_brain/proc/lose_follow()
	leader_ref = null
	invalidate_selection()

// ---------------------------------------------------------------------------
// Sleep / wake (legacy: go_sleep / go_wake)
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/go_sleep()
	if(process_flags == 0)
		return
	stop_active(DQ_BEHAVIOR_STOP_INTERRUPTED)
	forget_everything()
	manage_processing(0)

/datum/ai_brain/proc/go_wake()
	if(process_flags & DQAI_PROCESSING)
		return
	if(QDELETED(holder) || holder.stat >= DEAD)
		return
	if(holder.client && !autopilot)
		return
	manage_processing(DQAI_PROCESSING) // wake to the slow tick; engagement adds the fast tick on a threat
	update_engagement()

// ---------------------------------------------------------------------------
// Legacy attribute proxies — getters/setters so caller code that reads or
// writes ai_holder fields can be ported with one find-and-replace.
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/set_hostile(value)
	if(istype(holder, /mob/living/simple_mob))
		var/mob/living/simple_mob/SM = holder
		SM.ai_attack_on_sight = value ? TRUE : FALSE
		invalidate_selection()

/datum/ai_brain/proc/get_hostile()
	if(istype(holder, /mob/living/simple_mob))
		var/mob/living/simple_mob/SM = holder
		return SM.ai_attack_on_sight
	return FALSE

// ---------------------------------------------------------------------------
// react_to_attack — legacy proc external code calls when something attacks
// the holder mob. In the modern brain this is the same as a damage event
// from that attacker, so we just route through notify_damage with 0 damage
// (the brain handles the personal HOSTILE entry promotion).
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/react_to_attack(atom/movable/attacker)
	if(!attacker || !ismob(attacker))
		return
	if(!holder)
		return
	if(is_friendly_fire(attacker))
		return // a packmate / coexisting fauna clipped us — don't start a feud
	add_personal(attacker, DQ_DISPOSITION_HOSTILE, DQ_PERSONAL_DEFAULT_DURATION, "react_to_attack")
	// Record in the world model so retaliate_to_attacker.evaluate() can see
	// who struck us even when they're outside view() range.
	if(model && ismob(attacker))
		model.record_damage(0, BRUTE, attacker)
	if(!primary_threat)
		var/mob/old = primary_threat
		primary_threat = attacker
		SEND_SIGNAL(holder, COMSIG_DQAI_TARGET_CHANGED, attacker, old)
	update_engagement() // being attacked engages the fast tick immediately
	invalidate_selection()

// ---------------------------------------------------------------------------
// Legacy-compat fields exposed as vars so callers can write
//   mob.ai_brain.hostile = TRUE
// and have the change take effect. These are wired in `vars[name]` so the
// brain stays a clean datum but accepts the same writes external code used
// to do on /datum/ai_holder.
//
// Field reads also work because each of these is a real instance var.
// ---------------------------------------------------------------------------

// Legacy-mirror-style vars that the modern brain actually reads/writes.
// Anything inert was removed in the audit pass — readers were updated to use
// the modern API (`primary_threat`, `personal[]`, etc).
/datum/ai_brain
	/// Writes propagate to /mob/living/simple_mob.ai_attack_on_sight; reads
	/// return that flag directly via vv_edit_var + set_hostile/get_hostile.
	var/hostile = TRUE
	/// Adds /datum/ai_behavior/maul_unconscious to effective behaviors when TRUE.
	var/mauling = TRUE
	/// Adds /datum/ai_behavior/return_home when TRUE.
	var/returns_home = FALSE
	/// Toggles whether idle_wander behavior fires. Default TRUE.
	var/wander = TRUE
	/// Used by return_home behavior to gate the threshold.
	var/max_home_distance = 7
	/// Destination turf for a one-shot walk. Set via give_destination, read by
	/// /datum/ai_behavior/walk_to_destination.
	var/turf/destination = null

/// Legacy stubs for procs that mob subtypes still try to call. Each returns
/// a safe default — the real behavior moved to /datum/ai_behavior selection.
/datum/ai_brain/proc/list_targets()
	return model ? model.visible_hostiles : list()

/datum/ai_brain/proc/find_target()
	update_primary_threat()
	return primary_threat

/datum/ai_brain/proc/track_target_position()
	return

/datum/ai_brain/proc/check_attacker(mob/M)
	if(!personal || !M)
		return FALSE
	var/list/entry = personal[WEAKREF(M)]
	return entry && entry["disp"] <= DQ_DISPOSITION_HOSTILE

/datum/ai_brain/proc/on_hear_say(mob/living/speaker, message)
	return

/datum/ai_brain/vv_edit_var(var_name, var_value)
	. = ..()
	switch(var_name)
		if("hostile")
			set_hostile(var_value)
		if("returns_home", "mauling")
			invalidate_selection()
