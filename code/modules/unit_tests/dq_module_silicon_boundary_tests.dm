// Native actor/provider contracts retain HUD side effects and content behavior.

/datum/unit_test/dq_silicon/c2_hud_actor_routes
/datum/unit_test/dq_silicon/c2_hud_actor_routes/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = make_human(T)
	var/mob/living/silicon/robot/R = make_borg(T)
	var/mob/living/silicon/ai/AI = make_ai(T)
	AI.forceMove(T)
	var/atom/movable/screen/button = allocate(/atom/movable/screen)
	button.name = I_WALK
	H.set_m_intent(I_RUN)
	km_synthetic_click(H, button)
	TEST_ASSERT_EQUAL(H.m_intent, I_WALK, "Human's native HUD click retains shared movement selection")
	TEST_ASSERT_EQUAL(H.m_int, "14,14", "Shared movement selection retains its actual HUD position")
	if(!R.module)
		rel_set(R, nameof(R.module), new /obj/item/robot_module/robot/standard(R))
	var/obj/item/tool/crowbar/module_tool = allocate(/obj/item/tool/crowbar, R.module)
	rel_add(R.module, nameof(R.module.modules), module_tool)
	R.activate_module(module_tool)
	R.select_module(R.module_slot_of(module_tool))
	TEST_ASSERT_EQUAL(R.get_active_hand(), module_tool, "Real robot has an active module before its store click")
	button.name = "store"
	km_synthetic_click(H, button)
	TEST_ASSERT_EQUAL(R.get_active_hand(), module_tool, "Human cannot operate another actor's robot-only control")
	km_synthetic_click(AI, button)
	TEST_ASSERT_EQUAL(R.get_active_hand(), module_tool, "AI's unsupported robot control changes no robot module")
	km_synthetic_click(R, button)
	TEST_ASSERT_NULL(R.get_active_hand(), "Robot's native store click really unequips its active module")
	TEST_ASSERT_EQUAL(module_tool.loc, R.module, "Stored module returns to its real module holder")
	button.name = "Toggle Camera Light"
	var/was = AI.camera_light_on
	km_synthetic_click(H, button)
	km_synthetic_click(R, button)
	TEST_ASSERT_EQUAL(AI.camera_light_on, was, "Human and robot do not operate the AI-only camera control")
	km_synthetic_click(AI, button)
	TEST_ASSERT_EQUAL(!!AI.camera_light_on, !was, "AI's native camera-light control changes its actual lighting state")

/datum/unit_test/dq_silicon/c2_loose_hat_providers
/datum/unit_test/dq_silicon/c2_loose_hat_providers/run_gate()
	var/turf/T = test_floor()
	var/mob/living/silicon/robot/drone/D = allocate(/mob/living/silicon/robot/drone, T)
	var/obj/item/clothing/head/hardhat/first = allocate(/obj/item/clothing/head/hardhat, T)
	var/obj/item/clothing/head/hardhat/second = allocate(/obj/item/clothing/head/hardhat, T)
	TEST_ASSERT(first.mob_wear_hat(D), "Loose hat is accepted by the real drone head provider")
	TEST_ASSERT_EQUAL(D.hat, first, "Drone's actual hat relation contains the first hat")
	TEST_ASSERT_EQUAL(first.loc, D, "Accepted hat physically moves into the drone")
	TEST_ASSERT(second.mob_wear_hat(D), "An already occupied head retains the original consumed-click return")
	TEST_ASSERT_EQUAL(D.hat, first, "Second hat does not replace the original drone hat")
	TEST_ASSERT_EQUAL(second.loc, T, "Refused second hat remains on the floor")
	var/mob/living/carbon/alien/diona/nymph = allocate(/mob/living/carbon/alien/diona, T)
	TEST_ASSERT(second.mob_wear_hat(nymph), "Real nymph provider still accepts a loose hat")
	TEST_ASSERT_EQUAL(nymph.hat, second, "Nymph's actual hat relation contains the selected hat")
	TEST_ASSERT_EQUAL(second.loc, nymph, "Nymph's accepted hat really moves into it")

/datum/unit_test/dq_silicon/c2_written_and_record_providers
/datum/unit_test/dq_silicon/c2_written_and_record_providers/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = make_human(T)
	var/mob/living/silicon/robot/R = make_borg(T)
	var/mob/observer/dead/observer = allocate(/mob/observer/dead, T)
	var/mob/living/simple_mob/animal/passive/mouse/mouse = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	var/text = "A readable page with enough written characters to verify ordinary readers receive obscured content."
	TEST_ASSERT_EQUAL(H.written_text_view(text), text, "Human reads the original page text")
	TEST_ASSERT_EQUAL(R.written_text_view(text), text, "Cyborg's written-content provider retains the page text")
	TEST_ASSERT_EQUAL(observer.written_text_view(text), text, "Observer's original readable page view is preserved")
	var/obscured = mouse.written_text_view(text)
	TEST_ASSERT_EQUAL(length(obscured), length(text), "Obscuring retains the actual page length")
	TEST_ASSERT(findtext(obscured, "*"), "An ordinary mouse gets masked written content")
	for(var/i = 1, i <= length(text), i++)
		var/original_char = copytext(text, i, i + 1)
		var/visible_char = copytext(obscured, i, i + 1)
		TEST_ASSERT(visible_char == original_char || (original_char != " " && visible_char == "*"), "Obscuring only masks original non-space characters")
	var/obj/item/clothing/glasses/hud/security/glasses = allocate(/obj/item/clothing/glasses/hud/security, T)
	TEST_ASSERT(H.equip_to_slot(glasses, SLOT_ID_EYES), "Human actually wears the real security HUD glasses")
	TEST_ASSERT(hasHUD(H, "security"), "Security records access follows actual worn HUD equipment")
	TEST_ASSERT(!hasHUD(H, "medical"), "Security glasses do not grant medical records access")
	TEST_ASSERT_EQUAL(hasHUD(R, "security"), R.sensor_type, "Cyborg records access reads its actual sensor setting")
	TEST_ASSERT_NULL(hasHUD(mouse, "security"), "A mouse did not gain another actor's records HUD access")

/obj/item/cell/c2_shock_probe
	var/damage_queries = 0

/obj/item/cell/c2_shock_probe/get_electrocute_damage()
	damage_queries++
	return ..()

/datum/unit_test/dq_silicon/c2_contact_response_providers
/datum/unit_test/dq_silicon/c2_contact_response_providers/run_gate()
	var/turf/T = test_floor()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/stack/material/supermatter/stack = allocate(/obj/item/stack/material/supermatter, T)
	var/robot_burn = R.injury_load(INJURY_CATEGORY_THERMAL)
	stack.supermatter_touched(R)
	TEST_ASSERT_EQUAL(R.injury_load(INJURY_CATEGORY_THERMAL), robot_burn, "Real robot remains immune to direct supermatter contact")
	var/human_burn = H.injury_load(INJURY_CATEGORY_THERMAL)
	stack.supermatter_touched(H)
	TEST_ASSERT(H.injury_load(INJURY_CATEGORY_THERMAL) > human_burn, "Unprotected human's actual hands still burn on supermatter contact")
	var/obj/item/cell/c2_shock_probe/cell = allocate(/obj/item/cell/c2_shock_probe, T)
	cell.give(cell.maxcharge)
	var/charge_before = cell.charge
	TEST_ASSERT_EQUAL(electrocute_mob(R, cell, cell), 0, "Silicon rejects the complete shock transaction")
	TEST_ASSERT_EQUAL(cell.charge, charge_before, "Silicon shock rejection does not drain the real source cell")
	TEST_ASSERT_EQUAL(cell.damage_queries, 0, "Silicon rejects before querying the source damage or triggering grid work")
	TEST_ASSERT_EQUAL(R.injury_load(INJURY_CATEGORY_THERMAL), robot_burn, "Silicon shock rejection leaves real injuries unchanged")
	TEST_ASSERT_NULL(R.fingerprint_identity(), "Unkeyed robot's forensic identity remains its absent player key")
	var/mob/living/silicon/ai/AI = make_ai(T)
	var/obj/item/tool/crowbar/target = allocate(/obj/item/tool/crowbar, T)
	TEST_ASSERT(!target.add_fingerprint(AI), "AI still cannot leave a fingerprint")
	TEST_ASSERT_NULL(target.forensic_data, "Rejected AI fingerprint does not allocate forensic state")

/datum/unit_test/dq_silicon/c2_module_handoff_providers
/datum/unit_test/dq_silicon/c2_module_handoff_providers/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = make_human(T)
	var/mob/living/silicon/robot/R = make_borg(T)
	var/mob/living/silicon/ai/AI = make_ai(T)
	TEST_ASSERT_EQUAL(AI.research_audit_identity(), "AI [AI.name]", "AI audit keeps its real name and original prefix")
	TEST_ASSERT_EQUAL(R.research_audit_identity(), "CYBORG [R.name]", "Cyborg audit keeps its real name and original prefix")
	TEST_ASSERT_EQUAL(H.research_audit_identity(), "Unknown", "Human's ID-based audit remains the console's decision")
	var/obj/item/electronic_assembly/wallmount/assembly = allocate(/obj/item/electronic_assembly/wallmount, T)
	TEST_ASSERT(H.put_in_active_hand(assembly), "Human really holds the assembly before wall release")
	H.release_wall_assembly(assembly, T)
	TEST_ASSERT_EQUAL(assembly.loc, T, "Human carrier drops the actual held wall assembly")
	TEST_ASSERT_NULL(H.get_active_hand(), "Human's real hand is empty after wall release")
	if(!R.module)
		rel_set(R, nameof(R.module), new /obj/item/robot_module/robot/standard(R))
	var/obj/item/electronic_assembly/wallmount/robot_assembly = allocate(/obj/item/electronic_assembly/wallmount, R.module)
	rel_add(R.module, nameof(R.module.modules), robot_assembly)
	R.activate_module(robot_assembly)
	R.select_module(R.module_slot_of(robot_assembly))
	R.release_wall_assembly(robot_assembly, T)
	TEST_ASSERT_EQUAL(robot_assembly.loc, T, "Robot carrier explicitly releases its module assembly to the actual destination")
	var/obj/item/tool/crowbar/spawned = allocate(/obj/item/tool/crowbar, T)
	R.accept_admin_hand_item(spawned)
	TEST_ASSERT(spawned in R.module.modules, "Admin-spawned hand item enters the real robot module catalog")
	TEST_ASSERT(R.module_slot_of(spawned), "Admin-spawned hand item is activated in a real module slot")
	TEST_ASSERT_EQUAL(R.antagonist_override_rank(), 0, "Normal cyborg has no mind-independent subversion rank")
	R.set_emagged(TRUE)
	TEST_ASSERT_EQUAL(R.antagonist_override_rank(), 1, "Cyborg's actual tracked emag state supplies the original subversion rank")
	TEST_ASSERT_EQUAL(H.antagonist_override_rank(), 0, "Human does not acquire another actor's subversion rank")


/obj/machinery/appliance/cooker/oven/c2_route_probe
	var/touch_effects = 0
	var/no_touch_effects = 0

/obj/machinery/appliance/cooker/oven/c2_route_probe/oven_interaction_toggle_door(datum/act/op/A)
	touch_effects++
	return ..()

/obj/machinery/appliance/cooker/oven/c2_route_probe/oven_interaction_no_touch(datum/act/op/A)
	no_touch_effects++
	return ..()

/datum/unit_test/dq_silicon/c2_oven_exclusive_routes

/datum/unit_test/dq_silicon/c2_oven_exclusive_routes/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = make_human(T)
	var/mob/living/silicon/ai/AI = make_ai(T)
	var/mob/observer/dead/G = allocate(/mob/observer/dead, T)
	var/obj/machinery/appliance/cooker/oven/c2_route_probe/O = allocate(/obj/machinery/appliance/cooker/oven/c2_route_probe, T)
	for(var/mob/actor in list(H, AI, G))
		var/expected = actor == H ? "toggle_door_alt" : "toggle_door_alt_no_touch"
		var/allowed = 0
		for(var/key in list("toggle_door_alt", "toggle_door_alt_no_touch"))
			var/datum/op_plan/P = op_plan_for(O, key)
			TEST_ASSERT_NOTNULL(P, "The real oven declares each complementary route")
			var/datum/act/op/A = take(/datum/act/op)
			A.holder = O
			A.target = O
			A.actor = actor
			A.oplan = P
			var/accepts = TRUE
			for(var/condition in P.conds)
				if(!op_cond(A, condition))
					accepts = FALSE
					break
			A.release()
			if(accepts)
				allowed++
				TEST_ASSERT_EQUAL(key, expected, "The declared actor conditions select the correct oven route")
		TEST_ASSERT_EQUAL(allowed, 1, "Exactly one oven route accepts each living, AI and nonliving actor")
	var/was_open = O.open
	var/datum/op_result/result = test_click(H, O, null, GESTURE_ALT)
	TEST_ASSERT_EQUAL(result?.key, "toggle_door_alt", "A real human alt click selects the physical oven route")
	TEST_ASSERT_EQUAL(!!O.open, !was_open, "The real selected human operation toggles the door once")
	TEST_ASSERT_EQUAL(O.touch_effects, 1, "Human input runs one physical effect")
	TEST_ASSERT_EQUAL(O.no_touch_effects, 0, "Human input does not also run its complementary effect")
	// These direct effect checks are separate from the condition audit above:
	// an AI/ghost has no physical hand provider, but the legacy no-touch effect
	// must still retain its cooldown and leave the door alone when invoked.
	for(var/mob/actor in list(AI, G))
		was_open = O.open
		test_op_handler(O, TYPE_PROC_REF(/obj/machinery/appliance/cooker/oven/c2_route_probe, oven_interaction_no_touch), actor)
		TEST_ASSERT_EQUAL(O.open, was_open, "The no-touch effect leaves the physical door unchanged")
		TEST_ASSERT(cooldown_left(actor, next_click) > 0, "The no-touch effect retains the original click cooldown")
	TEST_ASSERT_EQUAL(O.touch_effects, 1, "No-touch effects never invoke the physical door operation")
	TEST_ASSERT_EQUAL(O.no_touch_effects, 2, "AI and nonliving direct effects each run exactly once")
