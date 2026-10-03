/// The actual resonator weapon constructs its real delayed field; ordinary floor bursting injures real victims and consumes only that original source.
/datum/unit_test/om/interim_resonance_burst_cleanup
	parent_type = /datum/unit_test/dq_p2_engine
	var/with_victim = TRUE

/datum/unit_test/om/interim_resonance_burst_cleanup/empty
	with_victim = FALSE

/datum/unit_test/om/interim_resonance_burst_cleanup/run_gate()
	var/turf/T = test_floor()
	var/turf/actor_floor = get_step(T, EAST)
	TEST_ASSERT(actor_floor && !actor_floor.density, "The real creator has an adjacent floor outside the actual resonance impact")
	TEST_ASSERT_NULL(locate_on(T, /obj/effect/resonance), "The actual target floor starts without another resonance field")
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, actor_floor)
	actor.enable_godmode()
	var/obj/item/resonator/tool = allocate(/obj/item/resonator, actor_floor)
	TEST_ASSERT(actor.put_in_active_hand(tool), "The real capable creator holds the original resonator")
	TEST_ASSERT_EQUAL(tool.burst_time, 5 SECONDS, "The actual ordinary weapon retains its original five-second burst delay")
	var/mob/living/carbon/human/victim
	if(with_victim)
		victim = allocate(/mob/living/carbon/human, T)
		TEST_ASSERT_EQUAL(victim.injury_load(INJURY_CATEGORY_PHYSICAL), 0, "The real unprotected floor victim starts without physical injuries")
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	var/list/visuals_before = turf_contents_of_type(T, /obj/effect/temp_visual/resonance_crush)
	TEST_ASSERT(assert_resolves(actor, T, tool, GESTURE_CLICK, "resonate"), "The actual held resonator resolves its native field operation: [explain_click(actor, T, tool)]")
	actor.next_click = 0
	var/datum/input_event/click/click = new(actor, T, null, "mapwindow.map", "left=1")
	input_submit(click)
	TEST_ASSERT_EQUAL(click.result?.key, "resonate", "The actual player click selects the native resonator operation")
	own_turf_contents(T)
	var/list/fields = turf_contents_of_type(T, /obj/effect/resonance)
	TEST_ASSERT_EQUAL(length(fields), 1, "The actual weapon creates exactly one real floor resonance field")
	var/obj/effect/resonance/field = fields[1]
	TEST_ASSERT(!QDELETED(field) && field.loc == T, "The actual constructed field retains its original target floor")
	TEST_ASSERT_EQUAL(field.creator, actor, "The real field preserves its exact original creator for attack logging")
	test_time(4.9 SECONDS)
	TEST_ASSERT(!QDELETED(field), "The original actual field survives until its original five-second deadline")
	TEST_ASSERT_EQUAL(length(turf_contents_of_type(T, /obj/effect/temp_visual/resonance_crush)), length(visuals_before), "Actual resonance creates no collapse visual before its original deadline")
	if(victim)
		TEST_ASSERT_EQUAL(victim.injury_load(INJURY_CATEGORY_PHYSICAL), 0, "The actual delayed resonance does not physically injure its victim early")
	test_time(0.2 SECONDS)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(field), "The actual timed floor burst consumes the original field")
	var/list/visuals = turf_contents_of_type(T, /obj/effect/temp_visual/resonance_crush) - visuals_before
	TEST_ASSERT_EQUAL(length(visuals), 1, "The actual floor burst creates exactly its real original collapse visual")
	var/obj/effect/temp_visual/resonance_crush/visual = visuals[1]
	TEST_ASSERT(!QDELETED(visual) && visual.loc == T, "The actual original collapse visual survives immediately after impact on the target floor")
	if(victim)
		TEST_ASSERT(victim.injury_load(INJURY_CATEGORY_PHYSICAL) > 0, "The actual timed floor burst applies real physical injury to its original unprotected victim")
		TEST_ASSERT(!QDELETED(victim) && victim.loc == T, "Actual floor bursting preserves the original impacted victim and floor")
	TEST_ASSERT(!QDELETED(pen) && pen.loc == T, "Actual floor bursting preserves the exact unrelated original floor pen")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), tool, "Actual floor bursting preserves the exact original held resonator")
	TEST_ASSERT(!QDELETED(actor) && actor.loc == actor_floor, "Actual floor bursting preserves the original creator outside its impact floor")
