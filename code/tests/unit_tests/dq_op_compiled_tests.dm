// The compiled click (code/engine/parts/dispatch.dm, doc/rewrite/proposals/op_compiled.md): its winner and its order are the full resolver's, and
// the tables it reads go when the holder's grants change. Every click of the test build is also compared by op_click_parity_check(); this test
// drives the shapes the bench reads (a crewmate hit or touched in every stance, a light used in hand, an alt-click, a click on the floor).

/datum/unit_test/dq_op_compiled_click_matches_full

/datum/unit_test/dq_op_compiled_click_matches_full/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/B = allocate(/mob/living/carbon/human, T)
	var/obj/item/storage/toolbox/mechanical/box = allocate(/obj/item/storage/toolbox/mechanical, T)
	var/obj/item/flashlight/light = allocate(/obj/item/flashlight, T)
	TEST_ASSERT(A.put_in_active_hand(box), "the actor holds the toolbox")
	var/compiled_before = GLOB.op_count_compiled
	for(var/stance in list(I_HELP, I_DISARM, I_GRAB, I_HURT))
		A.set_use_stance(stance)
		dq_op_compiled_compare(A, B, box, GESTURE_CLICK, "a toolbox click on a crewmate in stance [stance]")
		dq_op_compiled_compare(A, B, null, GESTURE_CLICK, "an empty-hand click on a crewmate in stance [stance]")
		dq_op_compiled_compare(A, B, box, GESTURE_ALT, "an alt-click on a crewmate in stance [stance]")
		dq_op_compiled_compare(A, T, box, GESTURE_CLICK, "a toolbox click on the floor in stance [stance]")
	A.set_use_stance(I_HELP)
	A.drop_from_inventory(box, T)
	TEST_ASSERT(A.put_in_active_hand(light), "the actor holds the light")
	dq_op_compiled_compare(A, light, light, GESTURE_SELF, "the light used in hand")
	dq_op_compiled_compare(A, box, light, GESTURE_CLICK, "the light clicked on the toolbox")
	TEST_ASSERT(GLOB.op_count_compiled > compiled_before, "the clicks went through the compiled path")

/// The compiled resolution of an input orders the same survivors as op_resolve() and picks the same winner.
/datum/unit_test/proc/dq_op_compiled_compare(mob/actor, atom/target, obj/held, gesture, what)
	var/authority = actor_authority(actor)
	var/datum/op_resolution/compiled = op_click_resolution(actor, target, held, ORIGIN_CLICK, authority, gesture)
	TEST_ASSERT(compiled?.fast, "[what]: the compiled path takes the click")
	var/datum/op_resolution/full = op_resolve(actor, target, held, ORIGIN_CLICK, authority, gesture, null)
	var/datum/op_cand/mine = op_resolution_winner(compiled)
	var/datum/op_cand/theirs = op_resolution_winner(full)
	TEST_ASSERT_EQUAL(mine ? op_cand_keys(list(mine)) : "none", theirs ? op_cand_keys(list(theirs)) : "none", "[what]: the winner and its side")
	op_fast_materialize(compiled)
	TEST_ASSERT_EQUAL(op_cand_keys(compiled.ordered), op_cand_keys(full.ordered), "[what]: the order of the survivors")

/// A holder's merged rows and providers are dropped when its capability generation moves (a grant attached, ended or restacked).
/datum/unit_test/dq_op_compiled_tables_follow_grants

/datum/unit_test/dq_op_compiled_tables_follow_grants/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/B = allocate(/mob/living/carbon/human, T)
	op_click_resolution(A, B, null, ORIGIN_CLICK, actor_authority(A), GESTURE_CLICK)
	op_resolution_winner(op_click_resolution(A, B, null, ORIGIN_CLICK, actor_authority(A), GESTURE_CLICK))
	var/datum/rx_state/state = A.rx
	TEST_ASSERT(length(state?.activations), "a human holds grants (its body, its species)")
	TEST_ASSERT(state.op_dispatch_memo, "the actor's merged rows are kept after a click")
	TEST_ASSERT(state.op_provider_memo, "the actor's providers are kept after a click")
	state.set_capability_generation(state.capability_generation + 1)
	TEST_ASSERT_NULL(state.op_dispatch_memo, "a moved capability generation drops the merged rows")
	TEST_ASSERT_NULL(state.op_provider_memo, "a moved capability generation drops the providers")

/// A crewmate's menu is served from the cache on the next read (its rows that sample state are asked again on their own), and a change of what
/// the actor carries inside it (an implant) is seen at once.
/datum/unit_test/dq_op_menu_cached_past_sampled_rows

/datum/unit_test/dq_op_menu_cached_past_sampled_rows/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/B = allocate(/mob/living/carbon/human, T)
	set_global(nameof(GLOB.op_menu_builds), GLOB.op_menu_builds)
	var/list/first = op_menu(A, B, null)
	var/builds = GLOB.op_menu_builds
	var/list/second = op_menu(A, B, null)
	TEST_ASSERT_EQUAL(GLOB.op_menu_builds, builds, "the second read of a crewmate's menu is a cache hit")
	TEST_ASSERT_EQUAL(json_encode(second), json_encode(first), "and lists the same rows")
	var/obj/item/implant/reagent_generator/imp = allocate(/obj/item/implant/reagent_generator, T)
	TEST_ASSERT(imp.handle_implant(A), "the actor takes an implant")
	op_menu(A, B, null)
	TEST_ASSERT(GLOB.op_menu_builds > builds, "an implant in the actor makes the menu read again")
