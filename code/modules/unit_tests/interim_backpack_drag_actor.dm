/// Deliver the unchanged native drop under the existing synthetic actor boundary.
/obj/interim_backpack_drag_actor_click
	var/obj/item/device

/obj/interim_backpack_drag_actor_click/Click(location, control, params)
	device.MouseDrop()

/datum/unit_test/interim_backpack_drag_actor
	abstract_type = /datum/unit_test/interim_backpack_drag_actor
	var/device_type

/datum/unit_test/interim_backpack_drag_actor/defib
	device_type = /obj/item/defib_kit/loaded

/datum/unit_test/interim_backpack_drag_actor/radio
	device_type = /obj/item/bluespaceradio

/datum/unit_test/interim_backpack_drag_actor/medigun
	device_type = /obj/item/medigun_backpack

/datum/unit_test/interim_backpack_drag_actor/shield
	device_type = /obj/item/personal_shield_generator/loaded

/datum/unit_test/interim_backpack_drag_actor/proton
	device_type = /obj/item/proton_pack

/datum/unit_test/interim_backpack_drag_actor/proc/linked_handheld(obj/item/device)
	if(istype(device, /obj/item/personal_shield_generator))
		var/obj/item/personal_shield_generator/generator = device
		return generator.active_weapon
	return device.tethered_handheld()

/datum/unit_test/interim_backpack_drag_actor/proc/drag_for(obj/item/device, mob/user)
	if(istype(device, /obj/item/defib_kit))
		var/obj/item/defib_kit/defib = device
		defib.drag_backpack_with_actor(user)
	else if(istype(device, /obj/item/bluespaceradio))
		var/obj/item/bluespaceradio/radio = device
		radio.drag_backpack_with_actor(user)
	else if(istype(device, /obj/item/medigun_backpack))
		var/obj/item/medigun_backpack/medigun = device
		medigun.drag_backpack_with_actor(user)
	else if(istype(device, /obj/item/personal_shield_generator))
		var/obj/item/personal_shield_generator/generator = device
		generator.drag_backpack_with_actor(user)
	else
		var/obj/item/proton_pack/proton = device
		proton.drag_backpack_with_actor(user)

/datum/unit_test/interim_backpack_drag_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/far = get_step(get_step(get_step(T, EAST), EAST), EAST)
	TEST_ASSERT(isfloorturf(far), "a real distant floor exists for the original drag guards")
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	var/datum/hud/hud = allocate(/datum/hud, actor)
	hud.build_action_groups()
	var/obj/item/device = allocate(device_type, T)
	var/obj/item/tether = linked_handheld(device)
	TEST_ASSERT_NOTNULL(tether, "actual device initialization creates its real linked handheld")
	TEST_ASSERT(actor.equip_to_slot(device, SLOT_ID_BACK), "actual inventory equips the real backpack device")
	set_var(device, nameof(device.canremove), FALSE)
	drag_for(device, actor)
	TEST_ASSERT_EQUAL(actor.get_equipped_item(SLOT_ID_BACK), device, "actual removal refusal preserves the real worn slot")
	TEST_ASSERT(!actor.item_is_in_hands(device), "refused removal does not duplicate the device into a hand")
	set_var(device, nameof(device.canremove), TRUE)
	actor.forceMove(far)
	TEST_ASSERT(!device.CanMouseDrop(device, bystander), "actual distant worn device fails the explicit nearby bystander range predicate")
	drag_for(device, bystander)
	TEST_ASSERT_EQUAL(actor.get_equipped_item(SLOT_ID_BACK), device, "explicit far-from-device actor cannot move the worn device")
	actor.forceMove(T)
	drag_for(device, null)
	TEST_ASSERT_EQUAL(actor.get_equipped_item(SLOT_ID_BACK), device, "absent explicit actor refuses the original predicate")
	var/obj/item/handcuffs/cuffs = allocate(/obj/item/handcuffs, T)
	TEST_ASSERT(actor.equip_to_slot(cuffs, SLOT_ID_HANDCUFFED), "real cuffs establish the source incapacity guard")
	TEST_ASSERT(actor.incapacitated(), "actual restrained actor satisfies the original predicate")
	drag_for(device, actor)
	TEST_ASSERT_EQUAL(actor.get_equipped_item(SLOT_ID_BACK), device, "actual restraint refusal preserves the real backpack slot")
	TEST_ASSERT(actor.unEquip(cuffs), "actual cuff removal restores the original source guard")
	var/obj/interim_backpack_drag_actor_click/native = allocate(/obj/interim_backpack_drag_actor_click, T)
	native.device = device
	km_synthetic_click(actor, native)
	TEST_ASSERT_NULL(actor.get_equipped_item(SLOT_ID_BACK), "native successful pickup clears the exact real worn slot")
	TEST_ASSERT(actor.item_is_in_hands(device), "native successful pickup puts the exact device in its actual wearer's hand")
	TEST_ASSERT_EQUAL(device.loc, actor, "actual native pickup retains the wearer's physical containment")
	TEST_ASSERT_EQUAL(linked_handheld(device), tether, "actual pickup preserves the original linked handheld identity")
	TEST_ASSERT(!bystander.item_is_in_hands(device), "original destination semantics do not grant the device to the unrelated human")
	TEST_ASSERT(actor.unEquip(device), "actual held item removal permits the second real worn fixture")
	TEST_ASSERT(actor.equip_to_slot(device, SLOT_ID_BACK), "actual inventory restores the real backpack slot")
	TEST_ASSERT(!device.CanMouseDrop(device, bystander), "actual adjacency refuses another actor while the device is worn")
	drag_for(device, bystander)
	TEST_ASSERT_EQUAL(actor.get_equipped_item(SLOT_ID_BACK), device, "nearby bystander refusal preserves the original worn slot")
	TEST_ASSERT(!actor.item_is_in_hands(device), "bystander refusal does not move the original into its wearer's hand")
	TEST_ASSERT(!bystander.item_is_in_hands(device), "bystander refusal preserves the unrelated human's hands")
	var/obj/item/left = allocate(/obj/item, T)
	var/obj/item/right = allocate(/obj/item, T)
	TEST_ASSERT(actor.put_in_l_hand(left), "actual unrelated item occupies the left destination")
	TEST_ASSERT(actor.put_in_r_hand(right), "actual unrelated item occupies the right destination")
	drag_for(device, actor)
	TEST_ASSERT_NULL(actor.get_equipped_item(SLOT_ID_BACK), "original removal occurs before occupied-hand pickup failure")
	TEST_ASSERT_EQUAL(device.loc, T, "original checked worn release leaves the exact device on the real floor when neither hand fits")
	TEST_ASSERT_EQUAL(actor.get_left_hand(), left, "pickup failure preserves the actual left hand blocker")
	TEST_ASSERT_EQUAL(actor.get_right_hand(), right, "pickup failure preserves the actual right hand blocker")
	TEST_ASSERT_EQUAL(linked_handheld(device), tether, "all real worn and floor transitions preserve exact linked handheld identity")
	TEST_ASSERT(!QDELETED(device), "original occupied-hand handling never deletes the real backpack device")
