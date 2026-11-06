/// Record the attribution argument while retaining actual human internals effects.
/mob/living/carbon/human/interim_air_forwarded_actor
	var/internals_actor_ref
	var/internals_calls = 0

/mob/living/carbon/human/interim_air_forwarded_actor/toggle_internals(mob/living/user)
	internals_actor_ref = user ? REF(user) : null
	internals_calls++
	return ..()

/// Record the pilot argument while retaining actual component checks and tank effects.
/obj/mecha/working/ripley/interim_air_forwarded_actor
	var/tank_actor_ref
	var/tank_calls = 0

/obj/mecha/working/ripley/interim_air_forwarded_actor/toggle_internal_tank(mob/user, obj/item/held)
	tank_actor_ref = user ? REF(user) : null
	tank_calls++
	return ..()

/datum/unit_test/interim_rig_mech_air_forwarded_actor
	abstract_type = /datum/unit_test/interim_rig_mech_air_forwarded_actor

/datum/unit_test/interim_rig_mech_air_forwarded_actor/rig/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/interim_air_forwarded_actor/actor = allocate(/mob/living/carbon/human/interim_air_forwarded_actor, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	actor.enable_godmode()
	bystander.enable_godmode()
	var/datum/hud/hud = allocate(/datum/hud, actor)
	hud.build_action_groups()
	var/obj/item/rig/rig = allocate(/obj/item/rig, T)
	TEST_ASSERT(actor.equip_to_slot(rig, SLOT_ID_BACK), "actual inventory equips the real RIG")
	test_time(rig.seal_delay + 1 SECOND)
	TEST_ASSERT_EQUAL(actor.get_equipped_item(SLOT_ID_BACK), rig, "actual timed completion retains the RIG slot")
	TEST_ASSERT_EQUAL(rig.wearer(), actor, "actual timed equipment completion establishes the checked wearer")
	var/obj/item/clothing/mask/breath/mask = allocate(/obj/item/clothing/mask/breath, T)
	var/obj/item/tank/emergency/oxygen/tank = allocate(/obj/item/tank/emergency/oxygen, T)
	TEST_ASSERT(actor.equip_to_slot(mask, SLOT_ID_MASK), "actual breath mask satisfies the real internals guard")
	TEST_ASSERT(actor.equip_to_slot(tank, SLOT_ID_BELT), "actual oxygen tank occupies the real belt slot")
	var/datum/mini_hud/rig/mini = allocate(/datum/mini_hud/rig, hud, rig)
	var/atom/movable/screen/rig/airtoggle/button = mini.airtoggle
	TEST_ASSERT_EQUAL(button.master_ref, rig, "real mini HUD construction associates its actual RIG")
	TEST_ASSERT_NULL(actor.internal, "actual actor begins without an internals source")
	km_synthetic_click(actor, button)
	TEST_ASSERT_EQUAL(actor.internal, tank, "native HUD click enables the exact real belt oxygen tank")
	TEST_ASSERT_EQUAL(actor.internals_calls, 1, "native click chains one real internals effect")
	TEST_ASSERT_EQUAL(actor.internals_actor_ref, REF(actor), "native click forwards its actual wearer to the real effect")
	button.toggle_air_with_actor(bystander)
	button.toggle_air_with_actor(null)
	TEST_ASSERT_EQUAL(actor.internal, tank, "unrelated and absent actors preserve the exact active tank")
	TEST_ASSERT_EQUAL(actor.internals_calls, 1, "ownership and absent actor guards refuse before the actual effect")
	actor.set_stat(UNCONSCIOUS)
	button.toggle_air_with_actor(actor)
	TEST_ASSERT_EQUAL(actor.internals_calls, 1, "the original stat guard refuses the actual wearer")
	actor.set_stat(CONSCIOUS)
	var/obj/item/handcuffs/cuffs = allocate(/obj/item/handcuffs, T)
	TEST_ASSERT(actor.equip_to_slot(cuffs, SLOT_ID_HANDCUFFED), "actual cuffs establish the existing incapacity guard")
	TEST_ASSERT(actor.incapacitated(), "real restraints satisfy the source incapacity predicate")
	button.toggle_air_with_actor(actor)
	TEST_ASSERT_EQUAL(actor.internal, tank, "real restrained wearer cannot disable the exact tank")
	TEST_ASSERT_EQUAL(actor.internals_calls, 1, "restraint refusal never reaches the actual internals effect")
	TEST_ASSERT(actor.unEquip(cuffs), "actual cuff removal restores the original guard")
	km_synthetic_click(actor, button)
	TEST_ASSERT_NULL(actor.internal, "second native click actually disables internals")
	TEST_ASSERT_EQUAL(actor.internals_calls, 2, "the real enable and disable effects both execute")
	TEST_ASSERT_EQUAL(actor.internals_actor_ref, REF(actor), "actual disable retains its precise wearer attribution")
	TEST_ASSERT_EQUAL(actor.get_equipped_item(SLOT_ID_BELT), tank, "internals roundtrip retains the original equipped oxygen tank")
	TEST_ASSERT_NULL(bystander.internal, "the actual unrelated human never gains an internals source")

/datum/unit_test/interim_rig_mech_air_forwarded_actor/mech/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	var/datum/hud/hud = allocate(/datum/hud, actor)
	hud.build_action_groups()
	var/obj/mecha/working/ripley/interim_air_forwarded_actor/mech = allocate(/obj/mecha/working/ripley/interim_air_forwarded_actor, T)
	TEST_ASSERT(move_into(mech, MECHA_SLOT_PILOT, actor, actor), "actual containment API establishes the real pilot slot")
	TEST_ASSERT_EQUAL(mech.slot_item(MECHA_SLOT_PILOT), actor, "the real pilot ledger contains the precise actor")
	TEST_ASSERT_EQUAL(actor.loc, mech, "actual pilot insertion moves the real human inside the mech")
	var/obj/item/mecha_parts/component/gas/gas = mech.internal_components[MECH_GAS]
	TEST_ASSERT_NOTNULL(gas, "actual Ripley initialization installs its real gas component")
	TEST_ASSERT_EQUAL(gas.get_efficiency(), 1, "healthy real gas component guarantees the original state effect")
	var/datum/mini_hud/mech/mini = allocate(/datum/mini_hud/mech, hud, mech)
	var/atom/movable/screen/mech/airtoggle/button = mini.airtoggle
	TEST_ASSERT_EQUAL(button.master_ref, mech, "real mini HUD construction associates its actual mech")
	var/initial_tank_mode = mech.use_internal_tank
	km_synthetic_click(actor, button)
	TEST_ASSERT_EQUAL(mech.use_internal_tank, !initial_tank_mode, "native HUD click actually toggles the real pilot's tank mode")
	TEST_ASSERT_EQUAL(mech.tank_calls, 1, "native click chains exactly one actual mech tank effect")
	TEST_ASSERT_EQUAL(mech.tank_actor_ref, REF(actor), "native click supplies its checked actual pilot rather than a null fallback")
	button.toggle_air_with_actor(bystander)
	button.toggle_air_with_actor(null)
	TEST_ASSERT_EQUAL(mech.tank_calls, 1, "unrelated and absent actors refuse before the real tank effect")
	TEST_ASSERT_EQUAL(mech.use_internal_tank, !initial_tank_mode, "refusals preserve the real changed tank mode")
	actor.set_stat(UNCONSCIOUS)
	button.toggle_air_with_actor(actor)
	TEST_ASSERT_EQUAL(mech.tank_calls, 1, "original stat guard refuses the actual pilot")
	actor.set_stat(CONSCIOUS)
	var/obj/item/handcuffs/cuffs = allocate(/obj/item/handcuffs, T)
	TEST_ASSERT(actor.equip_to_slot(cuffs, SLOT_ID_HANDCUFFED), "actual pilot cuffs establish the original incapacity guard")
	TEST_ASSERT(actor.incapacitated(), "actual restrained pilot satisfies the original guard")
	button.toggle_air_with_actor(actor)
	TEST_ASSERT_EQUAL(mech.tank_calls, 1, "real pilot restraint refuses before the actual tank effect")
	TEST_ASSERT(actor.unEquip(cuffs), "actual cuff removal restores pilot control")
	km_synthetic_click(actor, button)
	TEST_ASSERT_EQUAL(mech.use_internal_tank, initial_tank_mode, "actual second native click restores the original tank mode")
	TEST_ASSERT_EQUAL(mech.tank_calls, 2, "both real native toggles execute the actual backend")
	TEST_ASSERT_EQUAL(mech.tank_actor_ref, REF(actor), "the second real toggle retains exact pilot attribution")
	TEST_ASSERT_EQUAL(mech.slot_item(MECHA_SLOT_PILOT), actor, "tank controls preserve the exact actual pilot ledger identity")
