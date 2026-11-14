// The cost of one step of a player's mob, itemised per handler (the MOVE_COST trace's parts, code/domains/world_model/atom/move_cost.dm).
//
// A real player has a client; a test world has none, so the mob here carries what a client gives a step that the server pays for: a walking
// human in shoes at run intent (the footstep capability and the shoes_step notice), and an observer holding the chunks around the mob
// (interest_view_set, what the client's eye does every step), which is what makes the footstep audible and the lighting and draws near.

/// The costliest procs of the profile since the last clear, `count` of them by self time, as one log line each with calls a step.
/datum/unit_test/proc/step_profile_log(label, steps, count = 40, key = "self")
	var/text = world.Profile(PROFILE_REFRESH, format = "json")
	if(!istext(text))
		log_test("STEP_COST [label]: no profile text ([text])")
		return
	var/list/rows = json_decode(text)
	if(!islist(rows))
		return
	log_test("STEP_COST [label]: [length(rows)] profiled procs")
	if(length(rows))
		log_test("STEP_COST [label]: a row is [json_encode(rows[1])]")
	var/list/sorted = list()
	for(var/list/row as anything in rows)
		if(text2num("[row["calls"]]") < steps * 0.5)
			continue // not run on most steps
		sorted += list(row)
	for(var/i in 1 to min(count, length(sorted)))
		var/best = i
		for(var/j in i + 1 to length(sorted))
			if(text2num("[sorted[j][key]]") > text2num("[sorted[best][key]]"))
				best = j
		sorted.Swap(i, best)
		var/list/row = sorted[i]
		log_test("STEP_COST [label] by [key] #[i] [row["name"]]: self [round(text2num("[row["self"]]") * 1000 / steps, 0.001)] ms/step, total [round(text2num("[row["total"]]") * 1000 / steps, 0.001)] ms/step, [round(text2num("[row["calls"]]") / steps, 0.01)] calls/step")

/// Walks `steps` steps (back and forth along a row) measuring each, returns list(ms per step, parts summed, moved).
/datum/unit_test/proc/step_walk(mob/living/carbon/human/H, steps, turf/viewer_token_turf = null)
	var/list/sum = new /list(MOVE_COST_PART_COUNT)
	for(var/part in 1 to MOVE_COST_PART_COUNT)
		sum[part] = 0
	var/moved = 0
	var/total = 0
	var/walk_dir = EAST
	for(var/i in 1 to steps)
		var/turf/next = get_step(H, walk_dir)
		if(!next || next.density)
			walk_dir = turn(walk_dir, 180)
			next = get_step(H, walk_dir)
		if(!next)
			break
		var/started = move_cost_begin()
		if(H.Move(next, walk_dir))
			moved++
		if(viewer_token_turf) // the client's eye follows the mob (interest_eye_update)
			interest_view_set("dq-step-viewer", get_turf(H), null, world.view)
		total += TICK_USAGE_REAL - started
		move_cost_end(started, H, null, GLOB.refresh_marks_raised, GLOB.interest_chunks_entered, 0)
		for(var/part in 1 to MOVE_COST_PART_COUNT)
			sum[part] += GLOB.move_cost_parts[part]
		refresh_flush()
	return list(moved ? TICK_DELTA_TO_MS(total) / moved : 0, sum, moved)

/// A walking player's step: the mean cost, the notices taken and the handlers run a step.
/datum/unit_test/dq_step_cost_client_like

/datum/unit_test/dq_step_cost_client_like/Run()
	set_global(nameof(GLOB.move_cost_steps), GLOB.move_cost_steps)
	set_global(nameof(GLOB.move_cost_sampled), GLOB.move_cost_sampled)
	set_global(nameof(GLOB.move_cost_slow), GLOB.move_cost_slow)
	set_global(nameof(GLOB.move_cost_worst_ms), GLOB.move_cost_worst_ms)
	set_global(nameof(GLOB.move_cost_total_ms), GLOB.move_cost_total_ms)
	set_global(nameof(GLOB.move_cost_on), FALSE)
	interest_isolate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/clothing/shoes/black/shoes = allocate(/obj/item/clothing/shoes/black)
	TEST_ASSERT(H.equip_to_slot_if_possible(shoes, SLOT_ID_SHOES, quiet = TRUE), "the walker wears shoes")
	TEST_ASSERT_EQUAL(H.m_intent, I_RUN, "the walker runs")
	interest_view_set("dq-step-viewer", get_turf(H), null, world.view)
	refresh_flush()
	step_walk(H, 20, T) // warm: the first steps build caches
	var/notices_before = GLOB.notice_taken
	var/marks_before = GLOB.refresh_marks_raised
	world.Profile(PROFILE_CLEAR)
	world.Profile(PROFILE_START)
	var/list/result = step_walk(H, 1500, T)
	var/moved = result[3]
	var/list/sum = result[2]
	TEST_ASSERT(moved >= 1000, "the mob walked ([moved] steps)")
	var/notices = GLOB.notice_taken - notices_before
	var/marks = GLOB.refresh_marks_raised - marks_before
	log_test("STEP_COST client-like over [moved] steps: [round(result[1], 0.001)] ms a step (profiled, so inflated); notices taken [round(notices / moved, 0.01)] a step, marks raised [round(marks / moved, 0.01)] a step")
	log_test("STEP_COST parts, ms a step: handlers [round(TICK_DELTA_TO_MS(sum[MOVE_COST_MOVE]) / moved, 0.001)], Moved() [round(TICK_DELTA_TO_MS(sum[MOVE_COST_MOVED]) / moved, 0.001)] (notices [round(TICK_DELTA_TO_MS(sum[MOVE_COST_NOTICES]) / moved, 0.001)], loc readers [round(TICK_DELTA_TO_MS(sum[MOVE_COST_LOC_READS]) / moved, 0.001)], hops [round(TICK_DELTA_TO_MS(sum[MOVE_COST_HOPS]) / moved, 0.001)], heat [round(TICK_DELTA_TO_MS(sum[MOVE_COST_HEAT]) / moved, 0.001)], interest [round(TICK_DELTA_TO_MS(sum[MOVE_COST_INTEREST]) / moved, 0.001)], living [round(TICK_DELTA_TO_MS(sum[MOVE_COST_LIVING]) / moved, 0.001)], body [round(TICK_DELTA_TO_MS(sum[MOVE_COST_BODY]) / moved, 0.001)])")
	step_profile_log("client-like", moved)
	step_profile_log("client-like", moved, 150, "total")
	world.Profile(PROFILE_STOP)
	// What a step costs is counted, not only timed: the notices taken, and the relation rows the mob's followers are asked from.
	TEST_ASSERT(marks / moved <= 1.5, "a step marks few draws ([round(marks / moved, 0.01)] a step): no state write of the mob publishes every step")
	TEST_ASSERT(notices / moved <= 2, "a step takes at most two notices ([round(notices / moved, 0.01)] a step)")
	// Unprofiled, for the number that is reported.
	var/list/plain = step_walk(H, 300, T)
	for(var/obj/effect/decal/cleanable/mess in world) // the dirt a walker leaves
		qdel(mess)
	log_test("STEP_COST client-like unprofiled: [round(plain[1], 0.001)] ms a step over [plain[3]] steps")

/// Observers follow a mob that walks (follower_list() reads the observers, not the mob's whole relation index).
/datum/unit_test/dq_step_cost_followers_follow

/datum/unit_test/dq_step_cost_followers_follow/Run()
	var/turf/T = test_floor()
	var/turf/next = get_step(T, EAST)
	TEST_ASSERT(next && !next.density, "there is a floor to step to")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, T)
	TEST_ASSERT_EQUAL(length(H.follower_list()), 0, "nobody follows a fresh mob")
	rel_set(ghost, OBSERVER_FOLLOWING_VAR, H)
	TEST_ASSERT(ghost in H.follower_list(), "a following observer is a follower")
	TEST_ASSERT(!(H in ghost.follower_list()), "and the observer itself has none")
	TEST_ASSERT(H.Move(next, EAST), "the mob steps")
	TEST_ASSERT_EQUAL(get_turf(ghost), get_turf(H), "the follower came along")
	ghost.stop_following()
	TEST_ASSERT_EQUAL(length(H.follower_list()), 0, "and stopped following")
