// Joining the round: a player spawns at arrivals as a late joiner does, dressed for their job, in a named area whose doors have
// power, with a HUD that shows what an organic crew member has (no technomancer instability bar), and can walk.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Takes a test mind back off the round's roster (mind_initialize() adds it there).
/proc/dq_gameplay_forget_mind(datum/mind/M)
	SSticker.minds -= M

/// The late-join spawn: the arrivals turf the job system hands a joiner, the body equipped for the job there, a client's controls.
/datum/unit_test/dq_gameplay/proc/spawn_arrival(rank = JOB_INTERN)
	var/list/join = SSjob.late_spawn(null, rank)
	var/turf/T = join?["turf"]
	if(!isturf(T))
		Fail("the job system gave a late joiner no arrivals turf ([json_encode(join)])", __FILE__, __LINE__)
		return null
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.mind_initialize()
	defer_cleanup(null, GLOBAL_PROC_REF(dq_gameplay_forget_mind), H.mind)
	possess(H)
	SSjob.equip_rank(H, rank, TRUE, FALSE)
	refresh_flush()
	player = H
	return H

/// The doors around `T` (within `radius`) whose area has a working, charged APC, and which of them have no power.
/datum/unit_test/dq_gameplay/proc/dark_doors_near(turf/T, radius = 7)
	. = list("checked" = 0, "dark" = list())
	for(var/obj/machinery/door/airlock/door in range(radius, T))
		var/area/A = get_area(door)
		var/obj/machinery/power/apc/apc = A?.apc
		if(!A?.requires_power || A.always_unpowered || !apc?.cell || apc.cell.charge <= 0 || !apc.operating)
			continue
		.["checked"]++
		if(door.power_lost())
			.["dark"] += dq_power_door_state(door)

/datum/unit_test/dq_gameplay/arrival_spawn

/datum/unit_test/dq_gameplay/arrival_spawn/play()
	var/mob/living/carbon/human/H = spawn_arrival()
	if(!H)
		return
	// Dressed for the job.
	TEST_ASSERT_NOTNULL(H.get_equipped_item(SLOT_ID_UNIFORM), "the joiner wears the job's uniform")
	TEST_ASSERT_NOTNULL(H.get_equipped_item(SLOT_ID_SHOES), "and shoes")
	var/obj/item/card/id/card = H.GetIdCard()
	TEST_ASSERT_NOTNULL(card, "and carries an ID")
	var/image/worn = H.look_layers()[UNIFORM_LAYER]
	TEST_ASSERT(worn && draws_icon(H, worn.icon), "the uniform is drawn on the joiner")
	// The place they arrive at.
	var/area/A = get_area(H)
	TEST_ASSERT(A && length(trim(A.name)), "the arrivals area has a name ([A?.type])")
	TEST_ASSERT_EQUAL(A.icon_state, "", "the arrivals area draws no sprite over the map (its editor state '[initial(A.icon_state)]')")
	for(var/i in 1 to 5)
		dq_power_test_step()
	refresh_flush()
	var/list/doors = dark_doors_near(H)
	TEST_ASSERT(!length(doors["dark"]), "[length(doors["dark"])] of [doors["checked"]] doors near arrivals in APC-powered areas have no power: [jointext(doors["dark"], " || ")]")
	// An organic crew member's HUD: no instability bar, at once and after their Life has run.
	TEST_ASSERT_NULL(H.hud_used?.wiz_instability_display, "a joining human has no instability bar")
	pass_time(2 * LIFE_CYCLE_SECONDS)
	TEST_ASSERT_NULL(H.hud_used?.wiz_instability_display, "nor after their Life has run")
	TEST_ASSERT_EQUAL(H.stat, CONSCIOUS, "the joiner is awake")
	// They can walk off the spawn point and back.
	var/turf/start = H.loc
	var/moved_dir
	for(var/dir in GLOB.cardinal)
		if(stride(H, dir))
			moved_dir = dir
			break
	TEST_ASSERT(moved_dir, "the joiner can take a step from the arrivals spawn")
	TEST_ASSERT(stride(H, REVERSE_DIR(moved_dir)), "and step back")
	TEST_ASSERT_EQUAL(H.loc, start, "back on the spawn")

#endif
