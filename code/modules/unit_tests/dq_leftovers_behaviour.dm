// Behaviour pins for the leftovers (rewrite/leftovers): organ butchery, robotic limb repair and peridaxon revival, and the machines whose
// periodic work and interactions moved to the final forms. Written against the legacy code first; they read state, never op keys.

/datum/unit_test/dq_leftovers
	abstract_type = /datum/unit_test/dq_leftovers

/datum/unit_test/dq_leftovers/Run()
	test_driver_begin()
	run_gate()
	test_driver_end()

/datum/unit_test/dq_leftovers/proc/run_gate()
	return

/datum/unit_test/dq_leftovers/proc/tile(dx, dy)
	return locate(run_loc_floor_bottom_left.x + dx, run_loc_floor_bottom_left.y + dy, run_loc_floor_bottom_left.z)

/// A person, awake for the whole test.
/datum/unit_test/dq_leftovers/proc/person(turf/where)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, where || tile(2, 1))
	H.enable_godmode()
	var/mob/controller = allocate(/mob/living/simple_mob/e0_fixture, tile(0, 4))
	rel_set(H, nameof(H.teleop), controller)
	return H

/// `actor` clicks `target` holding `held` (an empty hand when null).
/proc/dq_lo_click(mob/living/actor, atom/target, obj/item/held)
	if(held && actor.get_active_hand() != held)
		if(actor.get_active_hand())
			actor.drop_item()
		actor.put_in_active_hand(held)
	else if(!held && actor.get_active_hand())
		actor.drop_item()
	actor.next_click = 0
	return test_click(actor, target, held)

// ---------------------------------------------------------------------------------------------------------------------
// Organs
// ---------------------------------------------------------------------------------------------------------------------

/// A knife on an organ on the floor: ten seconds of work, then meat where the organ was, and the organ gone.
/datum/unit_test/dq_leftovers/organ_butchery_takes_ten_seconds

/datum/unit_test/dq_leftovers/organ_butchery_takes_ten_seconds/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/organ/internal/heart/heart = allocate(/obj/item/organ/internal/heart, tile(2, 2))
	heart.meat_type = /obj/item/reagent_containers/food/snacks/meat
	var/obj/item/material/knife/knife = allocate(/obj/item/material/knife, tile(2, 1))
	knife.toolspeed = 1
	dq_lo_click(H, heart, knife)
	test_time(5 SECONDS)
	TEST_ASSERT(!QDELETED(heart), "the organ is still whole halfway through")
	test_time(7 SECONDS)
	TEST_ASSERT(QDELETED(heart), "the organ is butchered after ten seconds")
	var/obj/item/meat = locate(/obj/item/reagent_containers/food/snacks/meat) in tile(2, 2)
	TEST_ASSERT_NOTNULL(meat, "the meat lies where the organ was")
	qdel(meat)

/// Five units of peridaxon bring a dead organ back.
/datum/unit_test/dq_leftovers/organ_peridaxon_revives

/datum/unit_test/dq_leftovers/organ_peridaxon_revives/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/organ/internal/heart/heart = allocate(/obj/item/organ/internal/heart, tile(2, 2))
	heart.butcherable = FALSE
	heart.set_status(heart.status | ORGAN_DEAD)
	var/obj/item/reagent_containers/glass/beaker/beaker = allocate(/obj/item/reagent_containers/glass/beaker, tile(2, 1))
	beaker.reagents.add_reagent(REAGENT_ID_PERIDAXON, 10)
	dq_lo_click(H, heart, beaker)
	test_time(3 SECONDS)
	TEST_ASSERT(!(heart.status & ORGAN_DEAD), "the organ lives again")
	TEST_ASSERT_EQUAL(beaker.reagents.get_reagent_amount(REAGENT_ID_PERIDAXON), 5, "five units were used")

/// A patch on a robotic limb lands after a second with the tool in hand, and spends what the tool says.
/datum/unit_test/dq_leftovers/robotic_limb_patch_takes_a_second

/datum/unit_test/dq_leftovers/robotic_limb_patch_takes_a_second/run_gate()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human, tile(2, 2))
	var/obj/item/organ/external/arm = patient.get_organ(BP_L_ARM)
	arm.robotize()
	patient.injure(INJURY_BLUNT, 20, BP_L_ARM)
	var/before = arm.get_trauma()
	TEST_ASSERT(before > 0, "the arm is dented")
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, tile(2, 1))
	H.put_in_active_hand(coil)
	TEST_ASSERT(arm.robo_repair(15, BRUTE, "some dents", coil, H), "the patch starts")
	TEST_ASSERT_EQUAL(arm.get_trauma(), before, "nothing is patched at once")
	test_time(2 SECONDS)
	TEST_ASSERT(arm.get_trauma() < before, "the dents are patched after a second")

/// Walking away from a patch abandons it.
/datum/unit_test/dq_leftovers/robotic_limb_patch_needs_standing_still

/datum/unit_test/dq_leftovers/robotic_limb_patch_needs_standing_still/run_gate()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human, tile(2, 2))
	var/obj/item/organ/external/arm = patient.get_organ(BP_L_ARM)
	arm.robotize()
	patient.injure(INJURY_BLUNT, 20, BP_L_ARM)
	var/before = arm.get_trauma()
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, tile(2, 1))
	H.put_in_active_hand(coil)
	TEST_ASSERT(arm.robo_repair(15, BRUTE, "some dents", coil, H), "the patch starts")
	H.forceMove(tile(3, 1))
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(arm.get_trauma(), before, "a patch abandoned half way patches nothing")

/// A limb torn off leaves a stump in its place; the stump taken off in turn is gone.
/datum/unit_test/dq_leftovers/stump_ends_when_removed

/datum/unit_test/dq_leftovers/stump_ends_when_removed/run_gate()
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human, tile(2, 2))
	var/obj/item/organ/external/arm = patient.get_organ(BP_L_ARM)
	arm.droplimb(FALSE, DROPLIMB_EDGE)
	var/obj/item/organ/external/stump = patient.get_organ(BP_L_ARM)
	TEST_ASSERT(stump?.is_stump(), "a stump takes the arm's place")
	stump.removed()
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(stump), "a stump off its body is gone")
	qdel(arm)

/// A limb blown off in a shower of gore is gone, its contents thrown out.
/datum/unit_test/dq_leftovers/limb_gibbed_is_destroyed

/datum/unit_test/dq_leftovers/limb_gibbed_is_destroyed/run_gate()
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human, tile(2, 2))
	var/obj/item/organ/external/arm = patient.get_organ(BP_L_ARM)
	arm.droplimb(FALSE, DROPLIMB_BLUNT)
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(arm), "the arm is gone")
	for(var/obj/effect/decal/cleanable/blood/gibs/G in range(4, tile(2, 2)))
		qdel(G)
	for(var/obj/item/organ/O in range(4, tile(2, 2)))
		qdel(O)

// ---------------------------------------------------------------------------------------------------------------------
// Hydroponics trays and power cells
// ---------------------------------------------------------------------------------------------------------------------

/// A planted tray's step runs a growth cycle when one is due, stamping the cycle's start.
/datum/unit_test/dq_leftovers/tray_cycles_while_growing

/datum/unit_test/dq_leftovers/tray_cycles_while_growing/run_gate()
	var/obj/machinery/portable_atmospherics/hydroponics/tray = allocate(/obj/machinery/portable_atmospherics/hydroponics, tile(2, 2))
	var/obj/item/seeds/chiliseed/packet = allocate(/obj/item/seeds/chiliseed, tile(2, 2))
	tray.plant_seeds(packet)
	TEST_ASSERT_NOTNULL(tray.seed, "the seed is planted")
	TEST_ASSERT(test_work_allowed(tray), "a planted tray has work")
	tray.lastcycle = null
	tray.force_update = TRUE
	test_step_machine(tray)
	TEST_ASSERT_NOTNULL(tray.lastcycle, "the step ran a growth cycle")

/// A cryogenically frozen tray has no work; thawed, it has.
/datum/unit_test/dq_leftovers/frozen_tray_does_not_cycle

/datum/unit_test/dq_leftovers/frozen_tray_does_not_cycle/run_gate()
	var/obj/machinery/portable_atmospherics/hydroponics/tray = allocate(/obj/machinery/portable_atmospherics/hydroponics, tile(2, 2))
	var/obj/item/seeds/chiliseed/packet = allocate(/obj/item/seeds/chiliseed, tile(2, 2))
	tray.plant_seeds(packet)
	tray.set_frozen(1)
	TEST_ASSERT(test_machine_idle(tray), "no growth while frozen")
	tray.set_frozen(0)
	TEST_ASSERT(test_work_allowed(tray), "thawed, it grows again")

/// One step of a cell's periodic self-charge (adapter: the step's name).
/proc/dq_lo_cell_step(obj/item/cell/C)
	if(hascall(C, "recharge_step"))
		call(C, "recharge_step")(null)
	else
		call(C, "periodic_step")()

/// A self-charging cell drained by use charges itself back over time.
/datum/unit_test/dq_leftovers/self_charging_cell_recharges

/datum/unit_test/dq_leftovers/self_charging_cell_recharges/run_gate()
	var/obj/item/cell/device/weapon/recharge/C = allocate(/obj/item/cell/device/weapon/recharge, tile(2, 2))
	C.use(C.charge)
	var/drained = C.charge
	TEST_ASSERT(drained < C.maxcharge, "drained")
	COOLDOWN_RESET(C, charge_cooldown)
	dq_lo_cell_step(C)
	TEST_ASSERT(C.charge > drained, "its periodic step charged it back ([drained] -> [C.charge])")

/// A gradual charge adds its charge one step a second.
/datum/unit_test/dq_leftovers/gradual_charge_steps_each_second

/datum/unit_test/dq_leftovers/gradual_charge_steps_each_second/run_gate()
	var/obj/item/cell/C = allocate(/obj/item/cell, tile(2, 2))
	C.charge = 0
	C.gradual_charge(4, 1, FALSE, null)
	var/after_first = C.charge
	TEST_ASSERT(after_first > 0, "the first step lands at once")
	test_time(1.5 SECONDS)
	TEST_ASSERT(C.charge > after_first, "the next step lands a second later")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(C.gradual_charge_left, 0, "the steps run out")
