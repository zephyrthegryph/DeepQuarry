// Idle AI cost: what one run of a calm, unseen mouse's action loop costs and what one of its steps costs. The numbers are printed as notices (the clock is
// only indicative); the tests assert counters (what the run did) and behaviour.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// ms between two TICK_USAGE_REAL reads.
#define IDLE_COST_MS(a, b) TICK_DELTA_TO_MS((b) - (a))

/// The stages of one idle run, each timed the way the run does it (a mouse with nothing to do, nobody watching). A stage's number is the least batch mean of
/// five batches, so a busy machine does not inflate it; "run" is the whole tactical_tick() of a run that did not move the mouse and "run+step" of one that did.
/datum/unit_test/dq_ai_idle_cost_breakdown

/datum/unit_test/dq_ai_idle_cost_breakdown/Run()
	set_global(nameof(GLOB.staleness_on), FALSE) // the staleness checker re-reads every stat read: not what a live round pays
	var/turf/start = locate(run_loc_floor_bottom_left.x + 2, run_loc_floor_bottom_left.y + 2, run_loc_floor_bottom_left.z)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, start)
	var/datum/ai_brain/B = M.ai_brain
	TEST_ASSERT_NOTNULL(B, "the mouse has no brain")
	var/datum/observer = allocate(/datum)
	hold(M, STAT_RELEVANCE, RELEVANCE_NEAR, observer)
	var/list/best = list()
	var/moves = 0
	var/runs = 0
	for(var/i in 1 to 20) // warm-up
		B.strategic_wait = 0
		B.tactical_tick()
	for(var/batch in 1 to 5)
		var/list/ms = list("rebuild" = 0, "perceive" = 0, "threat" = 0, "assess" = 0, "evals" = 0, "interval" = 0, "run" = 0, "run+step" = 0, "all runs" = 0)
		var/quiet = 0
		var/stepped = 0
		for(var/i in 1 to 100)
			B.strategic_wait = 0
			var/t0 = TICK_USAGE_REAL
			B.rebuild_behaviors()
			var/t1 = TICK_USAGE_REAL
			B.pack?.perceive_if_due()
			var/t2 = TICK_USAGE_REAL
			B.update_primary_threat()
			var/t3 = TICK_USAGE_REAL
			B.assess_state()
			var/t4 = TICK_USAGE_REAL
			for(var/btype as anything in B.effective_behaviors)
				var/datum/ai_behavior/BH = dq_get_behavior(btype)
				var/source = B.behavior_source(btype)
				if(!B.state_allows(BH) || !BH.applicable_to(M) || !BH.is_off_cooldown(B, source))
					continue
				BH.evaluate(B, source)
			var/t5 = TICK_USAGE_REAL
			M.ai_action_interval(null)
			var/t6 = TICK_USAGE_REAL
			ms["rebuild"] += IDLE_COST_MS(t0, t1)
			ms["perceive"] += IDLE_COST_MS(t1, t2)
			ms["threat"] += IDLE_COST_MS(t2, t3)
			ms["assess"] += IDLE_COST_MS(t3, t4)
			ms["evals"] += IDLE_COST_MS(t4, t5)
			ms["interval"] += IDLE_COST_MS(t5, t6)
			B.strategic_wait = 0
			var/turf/was = get_turf(M)
			var/r0 = TICK_USAGE_REAL
			B.tactical_tick()
			var/r1 = TICK_USAGE_REAL
			var/took = IDLE_COST_MS(r0, r1)
			ms["all runs"] += took
			if(get_turf(M) != was)
				ms["run+step"] += took
				stepped++
				moves++
			else
				ms["run"] += took
				quiet++
			runs++
			if(get_dist(get_turf(M), start) > 2)
				M.forceMove(start)
		for(var/part in ms)
			var/n = 100
			if(part == "run")
				n = max(1, quiet)
			else if(part == "run+step")
				n = max(1, stepped)
			var/mean = ms[part] / n
			if(isnull(best[part]) || mean < best[part])
				best[part] = mean
	var/text = ""
	for(var/part in best)
		text += " [part]=[round(best[part], 0.001)]"
	TEST_NOTICE(src, "IDLE_RUN runs [runs] moves [moves], ms (least batch mean):[text]")
	for(var/obj/effect/decal/cleanable/dirt/D in range(3, start))
		qdel(D)

/// The least mean ms over 5 batches of 40 of one kind of step between two turfs: 1 the AI's step op, 2 step_to(), 3 forceMove(), 4 the op's resolution alone.
/datum/unit_test/proc/idle_cost_step_best(datum/ai_brain/B, mob/living/M, turf/a, turf/b, kind)
	var/best = INFINITY
	for(var/batch in 1 to 5)
		var/t0 = TICK_USAGE_REAL
		for(var/i in 1 to 40)
			var/turf/dest = (i % 2) ? b : a
			switch(kind)
				if(1)
					B.act_step(dest)
				if(2)
					step_to(M, dest)
				if(3)
					M.forceMove(dest)
				if(4)
					op_resolve(M, dest, null, ORIGIN_AI, AUTH_AI, null, "mob_attacks.step")
		var/mean = IDLE_COST_MS(t0, TICK_USAGE_REAL) / 40
		if(mean < best)
			best = mean
	return best

/datum/unit_test/dq_ai_idle_cost_step

/datum/unit_test/dq_ai_idle_cost_step/Run()
	set_global(nameof(GLOB.staleness_on), FALSE)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, run_loc_floor_bottom_left)
	var/datum/ai_brain/B = M.ai_brain
	var/datum/observer = allocate(/datum)
	hold(M, STAT_RELEVANCE, RELEVANCE_NEAR, observer)
	var/turf/a = run_loc_floor_bottom_left
	var/turf/b = locate(a.x + 1, a.y, a.z)
	TEST_ASSERT(b && !b.density, "no open floor next to the origin")
	for(var/i in 1 to 20)
		B.act_step((i % 2) ? b : a)
	var/act_step_ms = idle_cost_step_best(B, M, a, b, 1)
	var/step_to_ms = idle_cost_step_best(B, M, a, b, 2)
	var/force_ms = idle_cost_step_best(B, M, a, b, 3)
	var/resolve_ms = idle_cost_step_best(B, M, a, b, 4)
	// where a step's time goes inside Move: the parts MOVE_COST names, over the AI's step op
	var/list/parts = list()
	for(var/part in 1 to MOVE_COST_PART_COUNT)
		parts += 0
	var/n = 100
	for(var/i in 1 to n)
		move_cost_begin()
		B.act_step((i % 2) ? b : a)
		GLOB.move_cost_on = FALSE
		for(var/part in 1 to MOVE_COST_PART_COUNT)
			parts[part] += GLOB.move_cost_parts[part]
	var/part_text = ""
	for(var/part in 1 to MOVE_COST_PART_COUNT)
		part_text += " p[part]=[round(TICK_DELTA_TO_MS(parts[part]) / n, 0.001)]"
	for(var/turf/T in list(a, b))
		for(var/obj/effect/decal/cleanable/dirt/D in T)
			qdel(D) // a mouse dirties the floor it walks on
	TEST_NOTICE(src, "IDLE_STEP (least batch mean): act_step [round(act_step_ms, 0.001)] ms, of which op resolution [round(resolve_ms, 0.001)]; step_to [round(step_to_ms, 0.001)] ms, forceMove [round(force_ms, 0.001)] ms; Move parts inside act_step (ms/step, MOVE_COST_*):[part_text]")

#undef IDLE_COST_MS

#endif
