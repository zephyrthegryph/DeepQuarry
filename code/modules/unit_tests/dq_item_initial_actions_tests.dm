// Use the actual starting action, slot hooks and HUD viewer instead of allocating a second action.
/obj/item/flashlight/dq_initial_actions
	var/actions_seen_by_child

CAPABILITIES(/obj/item/flashlight/dq_initial_actions)
	setup(PROC_REF(note_initial_actions))

/obj/item/flashlight/dq_initial_actions/proc/note_initial_actions()
	actions_seen_by_child = length(actions)

/datum/unit_test/dq_item_initial_actions
/datum/unit_test/dq_item_initial_actions/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/hud/hud = allocate(/datum/hud, H)
	hud.build_action_groups()
	var/obj/item/flashlight/dq_initial_actions/F = allocate(/obj/item/flashlight/dq_initial_actions, T)
	TEST_ASSERT_EQUAL(length(F.actions), 1, "the real declared flashlight creates exactly one starting action")
	TEST_ASSERT_EQUAL(F.actions_seen_by_child, 1, "the ancestor's setup completes before the child setup observes its actions")
	var/datum/action/item_action/toggle_flashlight/A = F.actions[1]
	TEST_ASSERT(istype(A), "the actual action has the declared concrete subtype")
	TEST_ASSERT_EQUAL(A.action_target(), F, "the actual action retains its exact item target")
	TEST_ASSERT_NULL(A.action_owner(), "a floor item grants no unrelated actor")
	TEST_ASSERT(H.put_in_active_hand(F), "the actual item enters the human's real hand slot")
	TEST_ASSERT_EQUAL(A.action_owner(), H, "the slot hook grants the already-created action to its real holder")
	TEST_ASSERT_EQUAL(length(F.actions), 1, "equipping does not create a duplicate action")
	var/atom/movable/screen/movable/action_button/button = A.button_for(hud)
	TEST_ASSERT_NOTNULL(button, "the real grant constructs an actual HUD viewer button")
	TEST_ASSERT_EQUAL(button.linked_action(), A, "the real viewer refers to the existing item action")
	H.drop_from_inventory(F)
	TEST_ASSERT_NULL(A.action_owner(), "the real drop releases the actor grant")
	qdel(F)
	TEST_ASSERT(QDELETED(A), "deleting the real target destroys its actual linked action")
	TEST_ASSERT(!(A in H.actions), "target deletion leaves no stale action in the actor's grants")
