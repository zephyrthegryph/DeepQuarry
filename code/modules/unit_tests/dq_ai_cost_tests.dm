// Cost of perception, before and after packs (doc/rewrite/ai_packs.md "Cost"): packs of 1, 5 and 20, idle and engaged. "Before" is the per-brain pass the
// ai-brains base ran for every brain (one view() of the vision range per brain, every mob in it classified); "after" is the pack pass, run on the same
// mobs. The counts are exact (view builds, line-of-sight lookups, classifications, passes); the milliseconds are one tick's TICK_USAGE over the passes
// and only indicative. No benchmarks: this is a focused test, and it asserts the counts, not the clock.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The pre-pack perception of one brain, as update_perception() ran it: clear the three lists, view() once, classify each living mob in it and add it. Returns the number of classifications (the hostiles it found are
/// counted into `hostiles`).
/proc/dq_ai_old_perception_pass(datum/ai_brain/brain, list/hostiles)
	var/datum/world_model/model = brain.model
	model.visible_hostiles ||= list()
	rel_clear(model, nameof(model.visible_hostiles))
	model.visible_friendlies ||= list()
	rel_clear(model, nameof(model.visible_friendlies))
	model.visible_neutrals ||= list()
	rel_clear(model, nameof(model.visible_neutrals))
	var/classified = 0
	for(var/mob/living/M in view(brain.vision_range, brain.get_owner()))
		if(M == brain.get_owner() || M.stat >= DEAD)
			continue
		classified++
		var/disposition = brain.disposition_to(M)
		if(disposition <= DQ_DISPOSITION_HOSTILE)
			rel_add(model, nameof(model.visible_hostiles), M)
			hostiles += M
		else if(disposition >= DQ_DISPOSITION_FRIENDLY)
			rel_add(model, nameof(model.visible_friendlies), M)
		else
			rel_add(model, nameof(model.visible_neutrals), M)
	return classified

/// One scenario of `size` mobs, with or without hostiles. Returns the row of measurements.
/datum/unit_test/proc/measure_perception(size, engaged, solo_faction)
	var/list/mobs = list()
	var/solo_type = solo_faction ? /mob/living/simple_mob/combat_ai_tactics_subject : /mob/living/simple_mob/combat_ai_pack_subject
	for(var/i in 1 to size)
		var/mob/living/simple_mob/S = new solo_type(ai_floor(i % 2)) // not allocate(): each scenario ends with its own mobs gone
		mobs += S
	var/list/humans = list()
	if(engaged)
		humans += new /mob/living/carbon/human(ai_floor(2))
	var/passes = 5
	// before: every brain looks for itself, every pass (the lists start empty, as the pack pass finds them next)
	var/old_views = 0
	var/old_classified = 0
	for(var/mob/living/simple_mob/S as anything in mobs) // warm-up pass: not timed (what a pass changes the first time is a transition, not the steady cost)
		dq_ai_old_perception_pass(S.ai_brain, list())
	var/started = TICK_USAGE
	for(var/pass in 1 to passes)
		for(var/mob/living/simple_mob/S as anything in mobs)
			var/list/found = list()
			old_classified += dq_ai_old_perception_pass(S.ai_brain, found)
			old_views++
	var/old_ms = TICK_USAGE_TO_MS(started)
	// after: the pack of each mob perceives (a pack of N once, N packs of one N times)
	var/new_views = 0
	var/new_los = 0
	var/new_passes = 0
	var/list/packs = list()
	for(var/mob/living/simple_mob/S as anything in mobs)
		packs |= S.ai_brain.pack
	for(var/mob/living/simple_mob/S as anything in mobs) // the pack pass finds the lists empty too
		var/datum/world_model/model = S.ai_brain.model
		model.visible_hostiles = list()
		model.visible_friendlies = list()
		model.visible_neutrals = list()
	GLOB.ai_pack_stage_ms = list()
	GLOB.ai_pack_profile = TRUE
	var/transition_ms = 0
	started = TICK_USAGE
	for(var/datum/ai_pack/P as anything in packs)
		P.perceive(TRUE) // the first pass: what changes (targets, states) changes here
	transition_ms = TICK_USAGE_TO_MS(started)
	var/first_stages = ""
	for(var/stage in GLOB.ai_pack_stage_ms)
		first_stages += " [stage]=[round(GLOB.ai_pack_stage_ms[stage], 0.01)]"
	GLOB.ai_pack_stage_ms = list()
	started = TICK_USAGE
	for(var/pass in 1 to passes)
		for(var/datum/ai_pack/P as anything in packs)
			var/views_before = P.view_builds
			var/los_before = P.los_checks
			P.perceive(TRUE)
			new_views += P.view_builds - views_before
			new_los += P.los_checks - los_before
			new_passes++
	var/new_ms = TICK_USAGE_TO_MS(started)
	GLOB.ai_pack_profile = FALSE
	var/stages = ""
	for(var/stage in GLOB.ai_pack_stage_ms)
		stages += " [stage]=[round(GLOB.ai_pack_stage_ms[stage], 0.01)]"
	var/packs_made = length(packs)
	for(var/mob/living/M as anything in mobs + humans)
		qdel(M)
	return list("packs" = packs_made, "old_views" = old_views, "old_classified" = old_classified, "old_ms" = old_ms, "new_views" = new_views, "new_los" = new_los, "new_passes" = new_passes, "new_ms" = new_ms, "stages" = stages, "first_ms" = transition_ms, "first_stages" = first_stages)

/datum/unit_test/dq_ai_cost_packs_of_1_5_20

/datum/unit_test/dq_ai_cost_packs_of_1_5_20/Run()
	// A pack of one (the old shape) at every size, then real packs; the arena is two tiles wide, so the sizes stack on it.
	for(var/engaged in list(FALSE, TRUE))
		for(var/size in list(1, 5, 20))
			var/list/solo = measure_perception(size, engaged, TRUE)
			TEST_NOTICE(src, "COST [engaged ? "engaged" : "idle"] x[size] solo packs: old views [solo["old_views"]] / new views [solo["new_views"]] (los [solo["new_los"]], passes [solo["new_passes"]]); old [round(solo["old_ms"], 0.01)]ms new [round(solo["new_ms"], 0.01)]ms (first pass [round(solo["first_ms"], 0.01)]ms:[solo["first_stages"]]) stages:[solo["stages"]]")
			TEST_ASSERT(solo["new_views"] <= solo["old_views"], "packs of one built more views ([solo["new_views"]]) than the old per-brain pass ([solo["old_views"]])")
			var/list/packed = measure_perception(size, engaged, FALSE)
			TEST_NOTICE(src, "COST [engaged ? "engaged" : "idle"] x[size] one pack of [packed["packs"]]: old views [packed["old_views"]] / new views [packed["new_views"]] (los [packed["new_los"]], passes [packed["new_passes"]]); old [round(packed["old_ms"], 0.01)]ms new [round(packed["new_ms"], 0.01)]ms (first pass [round(packed["first_ms"], 0.01)]ms:[packed["first_stages"]]) stages:[packed["stages"]]")
			TEST_ASSERT(packed["new_views"] <= packed["old_views"], "a pack built more views ([packed["new_views"]]) than the old per-brain pass ([packed["old_views"]])")
			if(!engaged)
				TEST_ASSERT_EQUAL(packed["new_views"], 0, "an idle pack built a view for nothing hostile")
			else if(size > 1)
				TEST_ASSERT(packed["new_views"] < packed["old_views"], "an engaged pack of [size] did not save views over [size] solo brains")

#endif
