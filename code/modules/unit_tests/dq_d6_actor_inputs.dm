// D6: the explicit input actor must win over an unrelated ambient actor.
/datum/unit_test/dq_d6_actor_inputs
	abstract_type = /datum/unit_test/dq_d6_actor_inputs

/datum/unit_test/dq_d6_actor_inputs/New()
	..()
	dview(0, test_floor())
	status_policies()

/obj/item/dq_d6_drop_probe
	var/drop_actor_id

/obj/item/dq_d6_drop_probe/dropped(mob/user, equipping, slot)
	drop_actor_id = REF(user)
	return ..(user, equipping, slot)

/datum/unit_test/dq_d6_actor_inputs/ore_drop/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/ambient = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/ore_bag/B = allocate(/obj/item/ore_bag, actor)
	var/obj/item/dq_d6_drop_probe/I = allocate(/obj/item/dq_d6_drop_probe, B)
	TEST_ASSERT(with_actor(ambient, B, TYPE_PROC_REF(/obj/item/ore_bag, remove_from_storage), I, test_floor(), actor), "The actual public ore-bag removal succeeds")
	TEST_ASSERT_EQUAL(I.drop_actor_id, REF(actor), "Dropped receives the explicit remover, never the unrelated ambient actor")
	TEST_ASSERT_EQUAL(I.loc, test_floor(), "The actual item reaches the requested destination")

/obj/item/storage/dq_d6_close_probe
	var/close_actor_id

/obj/item/storage/dq_d6_close_probe/close(mob/user)
	close_actor_id = REF(user)
	return ..(user)

/datum/unit_test/dq_d6_actor_inputs/storage_close/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/ambient = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/storage/dq_d6_close_probe/B = allocate(/obj/item/storage/dq_d6_close_probe, test_floor())
	var/atom/movable/screen/close/C = allocate(/atom/movable/screen/close)
	rel_set(C, nameof(C.master_ref), B)
	with_actor(ambient, GLOBAL_PROC, GLOBAL_PROC_REF(input_dispatch), C, actor, INPUT_CLICK_ON)
	TEST_ASSERT_EQUAL(B.close_actor_id, REF(actor), "The actual close HUD forwards its explicit click actor to storage")

/obj/item/storage/secure/dq_d6_secure_probe
	var/fingerprint_actor_id
	var/inventory_actor_id

/obj/item/storage/secure/dq_d6_secure_probe/add_fingerprint(mob/user)
	fingerprint_actor_id = REF(user)
	return ..(user)

/obj/item/storage/secure/dq_d6_secure_probe/handle_inventory_drop(mob/user, obj/over_object)
	inventory_actor_id = REF(user)
	return TRUE

/datum/unit_test/dq_d6_actor_inputs/secure_drag/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/ambient = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/storage/secure/dq_d6_secure_probe/S = allocate(/obj/item/storage/secure/dq_d6_secure_probe, test_floor())
	TEST_ASSERT(S.locked, "The real secure storage starts locked")
	with_actor(ambient, GLOBAL_PROC, GLOBAL_PROC_REF(input_dispatch), S, actor, INPUT_DRAG_ONTO, null, test_floor())
	TEST_ASSERT_EQUAL(S.fingerprint_actor_id, REF(actor), "A locked drag fingerprints its actual actor")
	TEST_ASSERT_NULL(S.inventory_actor_id, "The locked drag never delegates inventory handling")
	S.set_locked(FALSE)
	with_actor(ambient, GLOBAL_PROC, GLOBAL_PROC_REF(input_dispatch), S, actor, INPUT_DRAG_ONTO, null, test_floor())
	TEST_ASSERT_EQUAL(S.inventory_actor_id, REF(actor), "The unlocked native override preserves the inherited storage callback and actor")

/obj/item/gun/dq_d6_firemode_probe
	var/firemode_actor_id

/obj/item/gun/dq_d6_firemode_probe/switch_firemodes(mob/user)
	firemode_actor_id = REF(user)

/datum/unit_test/dq_d6_actor_inputs/ammo_click/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/ambient = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/gun/dq_d6_firemode_probe/G = allocate(/obj/item/gun/dq_d6_firemode_probe, test_floor())
	var/atom/movable/screen/ammo/S = allocate(/atom/movable/screen/ammo)
	rel_set(S, nameof(S.our_gun), G)
	TEST_ASSERT(actor.checkClickCooldown(), "The actual actor is ready for the HUD click")
	with_actor(ambient, GLOBAL_PROC, GLOBAL_PROC_REF(input_dispatch), S, actor, INPUT_CLICK_ON)
	TEST_ASSERT_EQUAL(G.firemode_actor_id, REF(actor), "The actual ammo HUD forwards its explicit click actor to the gun")

/atom/movable/screen/palette_scroll/dq_d6_palette_probe
	var/check_actor_id

/atom/movable/screen/palette_scroll/dq_d6_palette_probe/can_use(mob/user)
	check_actor_id = REF(user)
	return FALSE

/datum/unit_test/dq_d6_actor_inputs/palette_gate/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/ambient = allocate(/mob/living/carbon/human, test_floor())
	var/atom/movable/screen/palette_scroll/dq_d6_palette_probe/S = allocate(/atom/movable/screen/palette_scroll/dq_d6_palette_probe)
	with_actor(ambient, GLOBAL_PROC, GLOBAL_PROC_REF(input_dispatch), S, actor, INPUT_CLICK_ON)
	TEST_ASSERT_EQUAL(S.check_actor_id, REF(actor), "The actual palette's permission guard receives the explicit click actor")

/datum/unit_test/dq_d6_actor_inputs/zone_hover/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, test_floor())
	var/mob/observer/dead/ambient = allocate(/mob/observer/dead, test_floor())
	var/atom/movable/screen/zone_sel/Z = allocate(/atom/movable/screen/zone_sel)
	var/choice = Z.get_zone_at(16, 16)
	TEST_ASSERT_NOTNULL(choice, "The fixture uses a real nonempty doll region")
	with_actor(ambient, GLOBAL_PROC, GLOBAL_PROC_REF(input_dispatch), Z, actor, INPUT_HOVER, "icon-x=16;icon-y=16", null, TRUE)
	TEST_ASSERT_EQUAL(Z.hovering_choice, choice, "Declared hover uses its human actor even under an unrelated ghost context")
	with_actor(ambient, GLOBAL_PROC, GLOBAL_PROC_REF(input_dispatch), Z, actor, INPUT_HOVER, "", null, FALSE)
	TEST_ASSERT_NULL(Z.hovering_choice, "The same explicit actor clears the real hover on exit")

/datum/unit_test/dq_d6_actor_inputs/proc/current_actor_for_test()
	return input_actor()

/datum/unit_test/dq_d6_actor_inputs/proc/push_then_read(mob/actor, datum/callback/CB)
	var/inside = world.PushUsr(actor, CB)
	return list(inside, input_actor())

/datum/unit_test/dq_d6_actor_inputs/scoped_callback/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/ambient = allocate(/mob/living/carbon/human, test_floor())
	var/datum/callback/CB = new(src, PROC_REF(current_actor_for_test))
	own(CB)
	var/list/observed = with_actor(ambient, src, PROC_REF(push_then_read), actor, CB)
	TEST_ASSERT_EQUAL(observed[1], actor, "The existing callback API runs under its requested explicit actor")
	TEST_ASSERT_EQUAL(observed[2], ambient, "The native binding restores the caller's distinct context afterward")

/datum/unit_test/dq_d6_actor_inputs/radial_close/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, test_floor())
	var/datum/radial_menu/M = allocate(/datum/radial_menu)
	var/atom/movable/screen/radial/center/C = allocate(/atom/movable/screen/radial/center)
	C.set_parent(M)
	TEST_ASSERT(!M.finished, "The actual radial starts unfinished")
	input_dispatch(C, actor, INPUT_CLICK_ON)
	TEST_ASSERT(M.finished, "The real center click closes its matching user menu")

/mob/living/carbon/human/dq_d6_tip_actor/read_preference(preference_type)
	if(preference_type == /datum/preference/toggle/inv_tooltips)
		return TRUE
	return ..(preference_type)

/obj/item/dq_d6_tip_probe
	var/tip_actor_id
	var/tip_calls = 0

/obj/item/dq_d6_tip_probe/openTip(location, control, params, user)
	tip_actor_id = REF(user)
	tip_calls++

/datum/unit_test/dq_d6_actor_inputs/item_hover_timer/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	var/mob/living/carbon/human/dq_d6_tip_actor/actor = allocate(/mob/living/carbon/human/dq_d6_tip_actor, test_floor())
	var/mob/living/carbon/human/ambient = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/dq_d6_tip_probe/I = allocate(/obj/item/dq_d6_tip_probe, actor)
	with_actor(ambient, GLOBAL_PROC, GLOBAL_PROC_REF(input_dispatch), I, actor, INPUT_HOVER, "", null, TRUE)
	test_time(0.6 SECONDS)
	TEST_ASSERT_EQUAL(I.tip_actor_id, REF(actor), "The real inventory tooltip timer captures the explicit hovering actor")
	TEST_ASSERT_EQUAL(I.tip_calls, 1, "The actual entered item opens its tooltip once")
	with_actor(ambient, GLOBAL_PROC, GLOBAL_PROC_REF(input_dispatch), I, actor, INPUT_HOVER, "", null, TRUE)
	with_actor(ambient, GLOBAL_PROC, GLOBAL_PROC_REF(input_dispatch), I, actor, INPUT_HOVER, "", null, FALSE)
	test_time(0.6 SECONDS)
	TEST_ASSERT_EQUAL(I.tip_calls, 1, "The actual exit cancels its pending tooltip timer")
	test_driver_end()
