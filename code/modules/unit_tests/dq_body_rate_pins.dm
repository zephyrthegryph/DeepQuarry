// Behaviour pins for the body migration (doc/rewrite/body_migration.md), slice 1: wounds, bleeding and blood.
//
// Hand-written pins of the numbers a patient sees over time: how fast a dressed cut closes, how much blood a cut or a
// torn artery costs, how fast blood comes back, when a small cut clots and when a closed wound fades. Each test runs
// on the injected kernel clock (test_driver_begin) and advances the body in Life-cycle frames with body_pin_frame(),
// which only moves time: whatever the body runs on its own runs. The numbers are the contract; a changed number is a
// recorded entry in doc/rewrite/intended_changes.md.

/// One Life cycle of body time: the injected clock moves LIFE_CYCLE and whatever the body runs on its own runs.
/proc/body_pin_frame(mob/living/carbon/human/H)
	test_time(LIFE_CYCLE)

/// Pins report the measured number so a recalibration reads it from the log.
/proc/body_pin_log(name, value)
	log_test("BODY PIN [name] = [value]")

/proc/body_pin_blood(mob/living/carbon/human/H)
	return H.vessel.get_reagent_amount(REAGENT_ID_BLOOD)

/proc/body_pin_close(a, b)
	return abs(a - b) < 0.01

/datum/unit_test/dq_body_pin
	abstract_type = /datum/unit_test/dq_body_pin

/datum/unit_test/dq_body_pin/Run()
	test_driver_begin()
	test_rng(1)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	pin(H)
	test_driver_end()
	for(var/obj/effect/decal/cleanable/blood/B in range(1, H))
		qdel(B)

/datum/unit_test/dq_body_pin/proc/pin(mob/living/carbon/human/H)
	return

/// A dressed 8-point cut on an arm closes on its own.
/datum/unit_test/dq_body_pin/autoheal

/datum/unit_test/dq_body_pin/autoheal/pin(mob/living/carbon/human/H)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/datum/affliction/wound/W = arm.create_wound(CUT, 8)
	W.bandage()
	arm.update_damages()
	for(var/i in 1 to 10)
		body_pin_frame(H)
	body_pin_log("autoheal", W.damage)
	TEST_ASSERT(body_pin_close(W.damage, 4), "a dressed 8-point cut heals to 4 in ten cycles (got [W.damage])")
	TEST_ASSERT(body_pin_close(arm.get_trauma(), W.damage), "the arm's trauma follows its wound (got [arm.get_trauma()])")

/// An open 20-point arm cut bleeds; blood comes back once below full.
/datum/unit_test/dq_body_pin/external_bleed

/datum/unit_test/dq_body_pin/external_bleed/pin(mob/living/carbon/human/H)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	arm.create_wound(CUT, 20)
	arm.update_damages()
	var/before = body_pin_blood(H)
	for(var/i in 1 to 5)
		body_pin_frame(H)
	var/lost = before - body_pin_blood(H)
	body_pin_log("external_bleed", lost)
	TEST_ASSERT(body_pin_close(lost, 2.106), "an open 20-point arm cut costs 2.106 blood in five cycles (got [lost])")

/// A 20-point torn artery in the torso tears further and bleeds inside.
/datum/unit_test/dq_body_pin/internal_bleed

/datum/unit_test/dq_body_pin/internal_bleed/pin(mob/living/carbon/human/H)
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	var/datum/affliction/wound/internal_bleeding/W = new(torso, 20)
	torso.add_wound(W)
	H.process_organs(TRUE)
	var/before = body_pin_blood(H)
	for(var/i in 1 to 5)
		body_pin_frame(H)
	var/lost = before - body_pin_blood(H)
	body_pin_log("internal_bleed", "[lost] tear [W.damage]")
	TEST_ASSERT(body_pin_close(lost, 2.1), "a 20-point torn artery costs 2.1 blood in five cycles (got [lost])")
	TEST_ASSERT(body_pin_close(W.damage, 20.5), "an untreated torn artery tears 0.1 a cycle (got [W.damage])")

/// Blood comes back after a draw.
/datum/unit_test/dq_body_pin/blood_regen

/datum/unit_test/dq_body_pin/blood_regen/pin(mob/living/carbon/human/H)
	H.vessel.remove_reagent(REAGENT_ID_BLOOD, 10)
	var/before = body_pin_blood(H)
	for(var/i in 1 to 10)
		body_pin_frame(H)
	var/gained = body_pin_blood(H) - before
	body_pin_log("blood_regen", gained)
	TEST_ASSERT(body_pin_close(gained, 1), "blood regenerates 1 in ten cycles (got [gained])")

/// A 5-point cut bleeds for about five cycles of body time, then clots.
/datum/unit_test/dq_body_pin/bleed_clock

/datum/unit_test/dq_body_pin/bleed_clock/pin(mob/living/carbon/human/H)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/datum/affliction/wound/W = arm.create_wound(CUT, 5)
	arm.update_damages()
	TEST_ASSERT(W.bleeding(), "a fresh 5-point cut bleeds")
	for(var/i in 1 to 4)
		body_pin_frame(H)
	TEST_ASSERT(W.bleeding(), "a 5-point cut still bleeds after four cycles (timer [W.bleed_timer])")
	body_pin_frame(H)
	body_pin_frame(H)
	TEST_ASSERT(!W.bleeding(), "a 5-point cut has clotted after six cycles (timer [W.bleed_timer])")

/// A wound healed to nothing stays: on a limb with nothing else to process, nothing removes it.
/datum/unit_test/dq_body_pin/wound_fades

/datum/unit_test/dq_body_pin/wound_fades/pin(mob/living/carbon/human/H)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/datum/affliction/wound/W = arm.create_wound(CUT, 3)
	H.mend(TREAT_TISSUE_REPAIR, 10, BP_L_ARM)
	TEST_ASSERT(body_pin_close(W.damage, 0), "the cut is mended to nothing (got [W.damage])")
	test_time(9 MINUTES)
	body_pin_frame(H)
	TEST_ASSERT(!QDELETED(W) && (W in arm.get_wounds()), "a closed wound stays for ten minutes")
	test_time(2 MINUTES)
	body_pin_frame(H)
	TEST_ASSERT(!QDELETED(W) && (W in arm.get_wounds()), "a closed wound on an otherwise healthy limb is never processed, so it stays")
