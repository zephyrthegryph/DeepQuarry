/obj/machinery/gear_dispenser/interim_actor_probe
	var/tmp/mob/admin_actor
	var/admin_calls = 0

/obj/machinery/gear_dispenser/interim_actor_probe/admin_add(mob/user)
	rel_set(src, nameof(admin_actor), user)
	admin_calls++
	return ..()

/obj/interim_gear_pack_actor_click
	var/obj/machinery/gear_dispenser/interim_actor_probe/dispenser
	var/tmp/mob/actor
	var/result

/obj/interim_gear_pack_actor_click/Click(location, control, params)
	result = dispenser.vv_topic_admin_add(actor, list())

/// Direct VV-handler coverage chains the actual rights refusal; it does not claim native admin authorization.
/datum/unit_test/om/interim_gear_pack_actor_refusal/run_om(list/made)
	test_prompts_reset()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_NULL(actor.client, "the real fixture cannot claim a privileged native client")
	var/obj/machinery/gear_dispenser/interim_actor_probe/dispenser = allocate(/obj/machinery/gear_dispenser/interim_actor_probe, T)
	var/list/original_catalog = dispenser.dispenses.Copy()
	TEST_ASSERT(length(original_catalog) > 0, "the actual dispenser constructor creates its real default gear catalog")
	var/list/original_amounts = list()
	var/list/original_types = list()
	for(var/name in original_catalog)
		var/datum/gear_disp/gear = original_catalog[name]
		TEST_ASSERT(istype(gear), "the actual constructed catalog entry is real gear data")
		original_amounts[name] = gear.amount
		original_types[name] = gear.to_spawn.Copy()
	var/original_flags = dispenser.dispenser_flags
	var/obj/interim_gear_pack_actor_click/probe = allocate(/obj/interim_gear_pack_actor_click, T)
	rel_set(probe, nameof(probe.dispenser), dispenser)
	rel_set(probe, nameof(probe.actor), actor)
	km_synthetic_click(bystander, probe)
	TEST_ASSERT_EQUAL(probe.result, TRUE, "the actual VV wrapper preserves its handled return")
	TEST_ASSERT_EQUAL(dispenser.admin_calls, 1, "the actual VV wrapper invokes the inherited guarded helper once")
	TEST_ASSERT_EQUAL(dispenser.admin_actor, actor, "the actual VV wrapper forwards the supplied actor instead of the native bystander")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "the actual rights refusal opens no gear-pack prompt")
	TEST_ASSERT_EQUAL(dispenser.dispenser_flags, original_flags, "the actual refusal preserves all dispenser busy/dispensing flags")
	TEST_ASSERT_EQUAL(length(dispenser.dispenses), length(original_catalog), "the actual rights refusal preserves the catalog size")
	for(var/name in original_catalog)
		var/datum/gear_disp/gear = original_catalog[name]
		TEST_ASSERT_EQUAL(dispenser.dispenses[name], gear, "the actual refusal preserves exact constructed gear identity")
		TEST_ASSERT_EQUAL(gear.amount, original_amounts[name], "the actual refusal preserves the existing gear supply")
		var/list/expected_types = original_types[name]
		TEST_ASSERT_EQUAL(length(gear.to_spawn), length(expected_types), "the actual refusal preserves the gear spawn-table size")
		for(var/i in 1 to length(expected_types))
			TEST_ASSERT_EQUAL(gear.to_spawn[i], expected_types[i], "the actual refusal preserves each existing spawn type")
		TEST_ASSERT(!QDELETED(gear), "the actual refusal does not dispose a constructed catalog entry")
	dispenser.admin_add(null)
	TEST_ASSERT_EQUAL(dispenser.admin_calls, 2, "the actual missing-actor helper reaches its real guard")
	TEST_ASSERT_NULL(dispenser.admin_actor, "the absent actor stays absent instead of adopting ambient state")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "an absent actor opens no gear-pack prompt")
	TEST_ASSERT_EQUAL(dispenser.dispenser_flags, original_flags, "an absent actor changes no actual dispenser flags")
	for(var/name in original_catalog)
		var/datum/gear_disp/gear = original_catalog[name]
		TEST_ASSERT_EQUAL(dispenser.dispenses[name], gear, "the missing actor preserves exact catalog identity")
		// The legacy constructor owns no catalog declaration; dispose only these locally constructed fixture entries.
		qdel(gear)
