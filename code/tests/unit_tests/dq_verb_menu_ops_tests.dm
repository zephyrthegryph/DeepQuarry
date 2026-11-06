// Verbs that became right-click menu entries (ops on the mob, item or turf): each is listed only where it applies, and none is left as a verb.

/// The menu row of key on target for actor, or null when the Menu does not list it.
/proc/dq_vmo_row(mob/actor, atom/target, key)
	for(var/list/row as anything in op_menu(actor, target, null))
		if(row["key"] == key)
			return row
	return null

/// A plain human lists only the entries that always apply to it; the conditional ones stay hidden.
/datum/unit_test/dq_verb_menu_ops_hidden_by_default

/datum/unit_test/dq_verb_menu_ops_hidden_by_default/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	for(var/key in list("augment_menu", "toggle_shades", "morph", "attach_limb_menu", "detach_limb_menu", "reagent_implant_transfer", "reagent_implant_egg", "toggle_cascade", "pick_fruit", "yank_out_object", "relocate_joint_menu", "activate_held", "leave_passenger", "hardsuit_interface", "combat_move"))
		TEST_ASSERT_NULL(dq_vmo_row(H, H, key), "[key] is hidden on a plain human with nothing to act on")
	TEST_ASSERT(dq_vmo_row(H, H, "toggle_self_surgery"), "Allow Self Surgery is always listed on yourself")

/// Activate Held Object appears with an item in the active hand.
/datum/unit_test/dq_verb_menu_ops_activate_held

/datum/unit_test/dq_verb_menu_ops_activate_held/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT_NULL(dq_vmo_row(H, H, "activate_held"), "nothing held, nothing to activate")
	var/obj/item/flashlight/F = allocate(/obj/item/flashlight, test_floor())
	TEST_ASSERT(H.put_in_active_hand(F), "the human takes the flashlight")
	TEST_ASSERT(dq_vmo_row(H, H, "activate_held"), "a held item lists Activate Held Object")

/// The reagent implant entries: a carrier of a generator sees the transfer on a neighbour who has one.
/datum/unit_test/dq_verb_menu_ops_reagent_implants

/datum/unit_test/dq_verb_menu_ops_reagent_implants/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/host = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/implant/reagent_generator/host_imp = allocate(/obj/item/implant/reagent_generator, T)
	var/obj/item/implant/reagent_generator/actor_imp = allocate(/obj/item/implant/reagent_generator, T)
	TEST_ASSERT_NULL(dq_vmo_row(actor, host, "reagent_implant_transfer"), "no implants, no entry")
	TEST_ASSERT(host_imp.handle_implant(host), "the host takes the generator")
	TEST_ASSERT_NULL(dq_vmo_row(actor, host, "reagent_implant_transfer"), "an actor with no generator is not offered the transfer")
	TEST_ASSERT(actor_imp.handle_implant(actor), "the actor takes a generator")
	TEST_ASSERT(dq_vmo_row(actor, host, "reagent_implant_transfer"), "a carrier is offered the transfer on a carrier beside them")
	TEST_ASSERT_NULL(dq_vmo_row(actor, host, "reagent_implant_egg"), "a plain generator is no egg implant")
	TEST_ASSERT_NULL(dq_vmo_row(actor, actor, "toggle_cascade"), "and has no cascade to toggle")

/// Egg implants offer the egg squeeze and the cascade toggle.
/datum/unit_test/dq_verb_menu_ops_egg_implants

/datum/unit_test/dq_verb_menu_ops_egg_implants/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/host = allocate(/mob/living/carbon/human, T)
	var/obj/item/implant/reagent_generator/egg/imp = allocate(/obj/item/implant/reagent_generator/egg, T)
	TEST_ASSERT(imp.handle_implant(host), "the host takes the egg implant")
	TEST_ASSERT(dq_vmo_row(host, host, "toggle_cascade"), "the carrier can toggle cascading")
	TEST_ASSERT(dq_vmo_row(host, host, "reagent_implant_egg"), "and squeeze an egg out of themself")
	TEST_ASSERT_NULL(dq_vmo_row(host, host, "reagent_implant_transfer"), "an egg implant gives no plain transfer")
	host.toggle_cascade()
	TEST_ASSERT(imp.cascade, "toggling turns cascading on")
	host.toggle_cascade()
	TEST_ASSERT(!imp.cascade, "and off again")

/// A micro-enterable object lists Micro Interact for a living actor beside it; an ordinary object does not.
/datum/unit_test/dq_verb_menu_ops_micro_interact

/datum/unit_test/dq_verb_menu_ops_micro_interact/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/structure/micro_tunnel/hole = allocate(/obj/structure/micro_tunnel, T)
	var/obj/structure/closet/plain = allocate(/obj/structure/closet, T)
	TEST_ASSERT(dq_vmo_row(H, hole, "micro_interact"), "a micro tunnel lists Micro Interact")
	TEST_ASSERT_NULL(dq_vmo_row(H, plain, "micro_interact"), "an ordinary object does not")

/// Climb Wall follows the climbable flag of the turf.
/datum/unit_test/dq_verb_menu_ops_climb_wall

/datum/unit_test/dq_verb_menu_ops_climb_wall/Run()
	var/turf/simulated/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	if(T.climbable)
		T.toggle_climbability()
	TEST_ASSERT_NULL(dq_vmo_row(H, T, "climb_wall_menu"), "an ordinary turf has no Climb Wall entry")
	T.toggle_climbability()
	TEST_ASSERT(dq_vmo_row(H, T, "climb_wall_menu"), "a climbable turf lists it")
	T.toggle_climbability()
	TEST_ASSERT_NULL(dq_vmo_row(H, T, "climb_wall_menu"), "and it goes again")

/// A voice that does not live in a communicator cannot hang up or rename itself.
/datum/unit_test/dq_verb_menu_ops_voice

/datum/unit_test/dq_verb_menu_ops_voice/Run()
	var/mob/living/voice/V = allocate(/mob/living/voice, test_floor())
	TEST_ASSERT_NULL(dq_vmo_row(V, V, "hang_up"), "no communicator, no Hang Up")
	TEST_ASSERT_NULL(dq_vmo_row(V, V, "change_name"), "no communicator, no Change Name")
