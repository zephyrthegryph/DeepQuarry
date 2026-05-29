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
/datum/ai_behavior/proc/get_player_verb_info()
	return null

// ---------------------------------------------------------------------------
// Lazy verb registration on client login.
//
// Brain init registers a one-shot listener so the dispatcher verb is only
// added to mobs that actually get piloted by a client — avoids bloating the
// verb list of every wild simple_mob in the round.
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/on_holder_login(mob/source)
	SIGNAL_HANDLER
	if(source && istype(source, /mob/living))
		add_verb(source, /mob/living/proc/dq_use_combat_move)

// ---------------------------------------------------------------------------
// Dispatcher verb
// ---------------------------------------------------------------------------

/mob/living/proc/dq_use_combat_move()
	set name = "Use Combat Move"
	set desc = "Trigger one of your AI mob's special moves."
	set category = "Combat"

	if(!ai_brain)
		to_chat(src, span_warning("You don't have any combat moves."))
		return
	if(stat != CONSCIOUS)
		to_chat(src, span_warning("You can't move."))
		return

	// Refresh effective_behaviors so newly picked-up items are visible.
	ai_brain.rebuild_behaviors()

	var/list/options = list()  // label => list("type" = btype, "source" = source)
	for(var/btype in ai_brain.effective_behaviors)
		var/datum/ai_behavior/B = dq_get_behavior(btype)
		var/list/info = B.get_player_verb_info()
		if(!info)
			continue
		if(!B.applicable_to(src))
			continue
		var/atom/source = ai_brain.effective_behaviors[btype]
		if(B.requires_held_source && !source)
			continue
		if(!B.is_off_cooldown(ai_brain, source))
			continue
		var/label = info["name"] || B.name
		options[label] = list("type" = btype, "source" = source, "info" = info)

	if(!length(options))
		to_chat(src, span_warning("You have no combat moves ready right now."))
		return

	var/picked = tgui_input_list(src, "Pick a combat move:", "Combat Move", options)
	if(!picked || !options[picked])
		return
	var/list/sel = options[picked]
	var/datum/ai_behavior/B = dq_get_behavior(sel["type"])
	var/atom/source = sel["source"]
	var/list/info = sel["info"]

	// Re-verify the source item is still held — the player may have dropped or
	// swapped it during the tgui prompt.
	if(B.requires_held_source && (!source || !(source in src.get_all_held_items())))
		to_chat(src, span_warning("[B.name]: you're no longer holding the required item."))
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
			target = dq_prompt_player_for_target(src, B, source)
			if(!target)
				return
	else
		target = dq_prompt_player_for_target(src, B, source)
		if(!target)
			return

	// Final eligibility check — owner may have moved out of range while picking.
	if(QDELETED(target))
		return
	var/dist = get_dist(src, target)
	if(dist < B.min_range || dist > B.max_range)
		to_chat(src, span_warning("[B.name]: out of range ([dist] tiles)."))
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

/proc/dq_prompt_player_for_target(mob/living/user, datum/ai_behavior/B, atom/source)
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
			if(!length(candidates))
				to_chat(user, span_warning("No valid targets in range."))
				return null
			var/picked_key = tgui_input_list(user, "Pick a target:", "Target", candidates)
			return picked_key ? candidates[picked_key] : null
		if(DQ_TARGET_TURF)
			// For turf-target behaviors (e.g. throw_grenade), let the AI's own
			// evaluate() pick the optimal spot. Manual turf selection from a
			// dropdown is unusable for a player. Pass the source through so
			// item-granted behaviors (whose evaluate checks `istype(source)`)
			// don't bail.
			var/list/result = B.evaluate(user.ai_brain, source)
			if(!result)
				to_chat(user, span_warning("No valid target turf nearby."))
				return null
			return result["target"]
		if(DQ_TARGET_ITEM)
			var/list/candidates = list()
			for(var/obj/item/I in view(scan_range, user))
				candidates["[I] ([get_dist(user, I)] tiles)"] = I
			if(!length(candidates))
				to_chat(user, span_warning("No valid items in range."))
				return null
			var/picked_key = tgui_input_list(user, "Pick an item:", "Target", candidates)
			return picked_key ? candidates[picked_key] : null
	return null

#undef DQ_PLAYER_PROMPT_MAX_RANGE
