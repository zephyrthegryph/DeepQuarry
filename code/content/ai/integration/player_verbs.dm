// Player-verb bridge for /datum/ai_behavior.
//
// When a player controls a simple_mob with a brain (e.g. possessed bigdragon,
// glitch boss, player-controlled drone), they should still get access to the
// mob's special moves. A behavior opts in by overriding get_player_verb_info()
// to return a non-null info list. The mob gets a single dispatcher verb
// (`Use Combat Move`) that lists eligible behaviors at invocation time and
// runs the chosen one.
//
// Item-granted behaviors (throw_grenade, aimed_shot) participate automatically
// because the brain's effective_behaviors list rolls them in. Picking up or
// dropping the item changes which moves the verb offers — we rebuild on each
// invocation so the player always sees the current set.
//
// Behaviors stay self-contained: applicable_to(), evaluate() and start() are
// reused as-is. The verb just runs evaluate() to confirm eligibility and pick
// a target when get_player_verb_info["auto_target"] is TRUE.

/// Override on behaviors that should be exposed as a player-castable move.
/// Return null to keep the behavior AI-only (default). Return a list:
///   "name"        — verb-list label shown to the player
///   "desc"        — short tooltip
///   "category"    — verb category (default "Combat")
///   "auto_target" — if TRUE, prefer evaluate()'s target (falls back to the
///                   player prompt if evaluate returns null). If FALSE, the
///                   player always chooses from visible mobs (or turfs for
///                   DQ_TARGET_TURF behaviors).
TYPE_TABLE_DECLARE(/datum/ai_behavior, get_player_verb_info, null)

// ---------------------------------------------------------------------------
// Lazy verb registration on client login.
//
// Brain init registers a one-shot listener so the dispatcher verb is only
// added to mobs that actually get piloted by a client — avoids bloating the
// verb list of every wild simple_mob in the round.
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/on_holder_login_event(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/source = A.target
	on_holder_login(source)

/datum/ai_brain/proc/on_holder_login(mob/source)
	if(source && istype(source, /mob/living))
		grant(source, granted_verb(/mob/living/proc/dq_use_combat_move), src)
	// A player-controlled mob is out of its pack (unless it is on autopilot): the pack never perceives or targets for it.
	if(!autopilot)
		leave_pack("player took over")

/// The player left the mob: it goes back to an AI pack.
/datum/ai_brain/proc/on_holder_logout_event(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	if(!pack && holder && !holder.client)
		seek_pack()

// ---------------------------------------------------------------------------
// Dispatcher verb

#define DQ_COMBAT_MOVE_ANSWER "move"
#define DQ_COMBAT_TARGET_ANSWER "target"
#define DQ_COMBAT_LATE_REFUSAL "late_refusal"
#define DQ_COMBAT_SILENT_REFUSAL "selection unavailable"
// ---------------------------------------------------------------------------

/mob/living/proc/dq_use_combat_move()
	set name = "Use Combat Move"
	set desc = "Trigger one of your AI mob's special moves."
	set category = VERB_CAT_COMBAT

	dq_combat_move_stage(list())

/mob/living/proc/dq_combat_move_stage(list/state, datum/request/request)
	var/reason = dq_combat_actor_refusal(src)
	if(reason)
		dq_combat_refusal_notice(src, reason)
		return

	// Refresh effective_behaviors so newly picked-up items are visible.
	ai_brain.rebuild_behaviors()

	var/list/options = list()  // label => list("type" = btype, "source" = source)
	for(var/btype in ai_brain.effective_behaviors)
		var/datum/ai_behavior/B = dq_get_behavior(btype)
		var/list/info = TYPE_TABLE_GET(B, get_player_verb_info)
		if(!info)
			continue
		if(!B.applicable_to(src))
			continue
		var/atom/source = ai_brain.behavior_source(btype)
		if(B.requires_held_source && !source)
			continue
		if(!B.is_off_cooldown(ai_brain, source))
			continue
		var/label = info["name"] || B.name
		options[label] = list("type" = btype, "source" = source, "info" = info)

	var/picked = state[DQ_COMBAT_MOVE_ANSWER]
	reason = dq_combat_late_check(request, dq_combat_options_refusal(options, picked))
	if(reason)
		dq_combat_refusal_notice(src, reason)
		return
	if(!(DQ_COMBAT_MOVE_ANSWER in state))
		dq_open_combat_choice(src, state, DQ_COMBAT_MOVE_ANSWER, "Pick a combat move:", "Combat Move", options)
		return
	var/list/sel = options[picked]
	var/datum/ai_behavior/B = dq_get_behavior(sel["type"])
	var/atom/source = sel["source"]
	var/list/info = sel["info"]

	// Re-verify the source item is still held — the player may have dropped or
	// swapped it during the tgui prompt.
	var/list/held_items
	if(B.requires_held_source && source)
		held_items = get_all_held_items()
	reason = dq_combat_late_check(request, dq_combat_source_refusal(B, source, held_items))
	if(reason)
		dq_combat_refusal_notice(src, reason)
		return

	// Resolve target.
	var/atom/target = null
	if(B.target_kind == DQ_TARGET_NONE || B.target_kind == DQ_TARGET_SELF)
		target = src
	else if(info["auto_target"])
		// Try evaluate() first for behaviors with their own smart picker
		// (throw_grenade's cluster finder, tail_sweep's mob count). If the
		// brain has no primary_threat yet — common for player-controlled mobs
		// that haven't aggro'd anyone — evaluate returns null. Fall back to
		// the manual prompt so the player can still use their move.
		var/list/result = B.evaluate(ai_brain, source)
		if(result)
			target = result["target"]
		else
			target = dq_prompt_player_for_target(src, B, source, state, request)
			if(!target)
				return
	else
		target = dq_prompt_player_for_target(src, B, source, state, request)
		if(!target)
			return

	// Final eligibility check — owner may have moved out of range while picking.
	reason = dq_combat_late_check(request, dq_combat_target_refusal(src, B, target))
	if(reason)
		dq_combat_refusal_notice(src, reason)
		return

	// Route through the brain's own lifecycle. run_behavior owns active_*
	// assignment, busy flag, and the start→done/failed dispatch — calling
	// start() directly here would skip the brain's stop_active for FAILED
	// and could race with the brain's slow tick on CONTINUE behaviors.
	ai_brain.run_behavior(B.type, target, source)

// ---------------------------------------------------------------------------
// Target prompts
// ---------------------------------------------------------------------------

/// Largest range we'll iterate when collecting target candidates for a player
/// prompt. Some behaviors have max_range = INFINITY; cap to client viewport.
#define DQ_PLAYER_PROMPT_MAX_RANGE 14

/proc/dq_prompt_player_for_target(mob/living/user, datum/ai_behavior/B, atom/source, list/state, datum/request/request)
	if(!state)
		state = list()
	var/scan_range = min(B.max_range, DQ_PLAYER_PROMPT_MAX_RANGE)
	switch(B.target_kind)
		if(DQ_TARGET_MOB)
			var/list/candidates = list()
			for(var/mob/living/M in view(scan_range, user))
				if(M == user || M.stat == DEAD)
					continue
				// Anti-grief: don't let a player-piloted mob fire its combat
				// moves at faction-mates / explicit ALLY entries. NEMESIS
				// (-2) → HOSTILE (-1) → WARY (0) are fair game; FRIENDLY (1)
				// and ALLY (2) are filtered out.
				if(user.ai_brain && user.ai_brain.disposition_to(M) >= DQ_DISPOSITION_FRIENDLY)
					continue
				candidates["[M] ([get_dist(user, M)] tiles)"] = M
			var/reason = dq_combat_late_check(request, dq_combat_candidates_refusal(candidates, "No valid targets in range."))
			if(reason)
				dq_combat_refusal_notice(user, reason)
				return null
			if(!(DQ_COMBAT_TARGET_ANSWER in state))
				dq_open_combat_choice(user, state, DQ_COMBAT_TARGET_ANSWER, "Pick a target:", "Target", candidates)
				return null
			var/picked_key = state[DQ_COMBAT_TARGET_ANSWER]
			return picked_key ? candidates[picked_key] : null
		if(DQ_TARGET_TURF)
			// For turf-target behaviors (e.g. throw_grenade), let the AI's own
			// evaluate() pick the optimal spot. Manual turf selection from a
			// dropdown is unusable for a player. Pass the source through so
			// item-granted behaviors (whose evaluate checks `istype(source)`)
			// don't bail.
			var/list/result = B.evaluate(user.ai_brain, source)
			var/reason = dq_combat_late_check(request, result ? null : "No valid target turf nearby.")
			if(reason)
				dq_combat_refusal_notice(user, reason)
				return null
			return result["target"]
		if(DQ_TARGET_ITEM)
			var/list/candidates = list()
			for(var/obj/item/I in view(scan_range, user))
				candidates["[I] ([get_dist(user, I)] tiles)"] = I
			var/reason = dq_combat_late_check(request, dq_combat_candidates_refusal(candidates, "No valid items in range."))
			if(reason)
				dq_combat_refusal_notice(user, reason)
				return null
			if(!(DQ_COMBAT_TARGET_ANSWER in state))
				dq_open_combat_choice(user, state, DQ_COMBAT_TARGET_ANSWER, "Pick an item:", "Target", candidates)
				return null
			var/picked_key = state[DQ_COMBAT_TARGET_ANSWER]
			return picked_key ? candidates[picked_key] : null
	return null

#undef DQ_PLAYER_PROMPT_MAX_RANGE

/// Only scalar answers survive the question; sources and targets are looked up again.
/datum/prompt/choice/player_combat_move
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/player_combat_move/recheck_extra()
	var/mob/living/user = owner
	if(!istype(user) || QDELETED(user) || QDELETED(answerer))
		return "gone"
	if(isnull(value))
		return null
	var/reason = dq_combat_actor_refusal(user)
	if(reason)
		return reason
	return captured[DQ_COMBAT_LATE_REFUSAL]

/proc/dq_open_combat_choice(mob/living/user, list/state, step, question, title, list/options)
	var/list/answers = state.Copy()
	answers[DQ_COMBAT_LATE_REFUSAL] = null
	var/list/labels = list()
	for(var/label in options)
		labels += label
	open_request(user, /datum/prompt/choice/player_combat_move, TYPE_PROC_REF(/mob/living, dq_combat_move_answered), answerer = user, captured = answers, step_name = step, question = question, title = title, choices = labels)

/mob/living/proc/dq_combat_move_answered(datum/act/request/A)
	if(isnull(A.request.value) || A.request.last_error == "gone")
		return
	SStgui.update_uis(src)
	if(!A.answer)
		dq_combat_refusal_notice(src, A.request.last_error)
		return
	var/list/state = A.request.captured.Copy()
	state[A.request.step_name] = A.answer.value
	dq_combat_move_stage(state, A.request)

/// Effect routing: records only the scalar result of a pure synchronous requirement.
/proc/dq_combat_late_check(datum/request/request, reason)
	if(!request)
		return reason
	request.captured[DQ_COMBAT_LATE_REFUSAL] = reason
	return request_recheck(request)

/proc/dq_combat_actor_refusal(mob/living/user)
	if(QDELETED(user))
		return "gone"
	if(!user.ai_brain)
		return "You don't have any combat moves."
	if(user.stat != CONSCIOUS)
		return "You can't move."
	return null

/proc/dq_combat_options_refusal(list/options, picked)
	if(!length(options))
		return "You have no combat moves ready right now."
	if(!isnull(picked) && (!picked || !options[picked]))
		return DQ_COMBAT_SILENT_REFUSAL
	return null

/proc/dq_combat_source_refusal(datum/ai_behavior/B, atom/source, list/held_items)
	if(B.requires_held_source && (!source || !(source in held_items)))
		return "[B.name]: you're no longer holding the required item."
	return null

/proc/dq_combat_candidates_refusal(list/candidates, empty_reason)
	return length(candidates) ? null : empty_reason

/proc/dq_combat_target_refusal(mob/living/user, datum/ai_behavior/B, atom/target)
	if(QDELETED(target))
		return DQ_COMBAT_SILENT_REFUSAL
	var/dist = get_dist(user, target)
	if(dist < B.min_range || dist > B.max_range)
		return "[B.name]: out of range ([dist] tiles)."
	return null

/proc/dq_combat_refusal_notice(mob/living/user, reason)
	if(reason && reason != "gone" && reason != DQ_COMBAT_SILENT_REFUSAL)
		to_chat(user, span_warning(reason))

#undef DQ_COMBAT_MOVE_ANSWER
#undef DQ_COMBAT_TARGET_ANSWER
#undef DQ_COMBAT_LATE_REFUSAL
#undef DQ_COMBAT_SILENT_REFUSAL
