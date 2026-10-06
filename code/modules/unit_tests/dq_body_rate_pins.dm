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

/// Within one cycle's worth: where the clock's first step lands against the frames depends on when its work item armed.
/proc/body_pin_near(a, b, one_cycle)
	return abs(a - b) <= one_cycle + 0.01

/datum/unit_test/dq_body_pin
	abstract_type = /datum/unit_test/dq_body_pin

/datum/unit_test/dq_body_pin/Run()
	test_driver_begin()
	test_rng(1)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	pin(H)
	test_driver_end()
	for(var/obj/effect/decal/cleanable/B in range(1, H))
		qdel(B)

/datum/unit_test/dq_body_pin/proc/pin(mob/living/carbon/human/H)
	return

/// A dressed 8-point cut on an arm closes on its own. (Life still runs: a random regenerative mutation can mend a little more.)
/datum/unit_test/dq_body_pin/autoheal

/datum/unit_test/dq_body_pin/autoheal/pin(mob/living/carbon/human/H)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/datum/affliction/wound/W = arm.create_wound(CUT, 8)
	W.bandage()
	arm.update_damages()
	for(var/i in 1 to 10)
		body_pin_frame(H)
	body_pin_log("autoheal", W.damage)
	TEST_ASSERT(body_pin_near(W.damage, 4.75, 1.5), "a dressed 8-point cut heals to 4.75 in ten cycles (got [W.damage])")
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
	TEST_ASSERT(body_pin_near(lost, 1.991, 20 / 35.01), "an open 20-point arm cut costs 1.991 blood in five cycles (got [lost])")

/// A 20-point torn artery in the torso tears further and bleeds inside.
/datum/unit_test/dq_body_pin/internal_bleed

/datum/unit_test/dq_body_pin/internal_bleed/pin(mob/living/carbon/human/H)
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	var/datum/affliction/wound/internal_bleeding/W = new(torso, 20)
	torso.add_wound(W)
	var/before = body_pin_blood(H)
	for(var/i in 1 to 5)
		body_pin_frame(H)
	var/lost = before - body_pin_blood(H)
	body_pin_log("internal_bleed", "[lost] tear [W.damage]")
	TEST_ASSERT(body_pin_near(lost, 1.725, 0.52), "a 20-point torn artery costs 1.725 blood in five cycles (got [lost])")
	TEST_ASSERT(body_pin_near(W.damage, 20.4, 0.1), "an untreated torn artery tears 0.1 a cycle (got [W.damage])")

/// Blood comes back after a draw.
/datum/unit_test/dq_body_pin/blood_regen

/datum/unit_test/dq_body_pin/blood_regen/pin(mob/living/carbon/human/H)
	H.vessel.remove_reagent(REAGENT_ID_BLOOD, 10)
	var/before = body_pin_blood(H)
	for(var/i in 1 to 10)
		body_pin_frame(H)
	var/gained = body_pin_blood(H) - before
	body_pin_log("blood_regen", gained)
	TEST_ASSERT(body_pin_near(gained, 0.9, 0.1), "blood regenerates 0.9 in ten cycles (got [gained])")

/// A 5-point cut bleeds for about five cycles of body time, then clots.
/datum/unit_test/dq_body_pin/bleed_clock

/datum/unit_test/dq_body_pin/bleed_clock/pin(mob/living/carbon/human/H)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/datum/affliction/wound/W = arm.create_wound(CUT, 5)
	arm.update_damages()
	TEST_ASSERT(W.bleeding(), "a fresh 5-point cut bleeds")
	for(var/i in 1 to 3)
		body_pin_frame(H)
	TEST_ASSERT(W.bleeding(), "a 5-point cut still bleeds after three cycles (timer [W.bleed_timer], damage [W.damage])")
	for(var/i in 1 to 4)
		body_pin_frame(H)
	TEST_ASSERT(!W.bleeding(), "a 5-point cut has clotted after seven cycles (timer [W.bleed_timer], damage [W.damage])")

/// A wound healed to nothing stays until ten minutes after it was made, then fades (its fade is a timer).
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
	TEST_ASSERT(QDELETED(W) || !(W in arm.get_wounds()), "a closed wound fades ten minutes after it was made")

/// The rates themselves, integrated over a known span without the kernel (no clock phase): a minute of body time.
/datum/unit_test/dq_body_clock_rates

/datum/unit_test/dq_body_clock_rates/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/datum/affliction/wound/W = arm.create_wound(CUT, 8)
	W.bandage()
	H.body_clock_advance(10 * LIFE_CYCLE)
	TEST_ASSERT(body_pin_close(W.damage, 8 - 10 * 0.25), "a lone dressed wound heals 0.25 a cycle (got [W.damage])")
	var/obj/item/organ/external/other = H.get_organ(BP_R_ARM)
	var/datum/affliction/wound/C = other.create_wound(CUT, 20)
	TEST_ASSERT(body_pin_close(H.blood_loss_rate(other), 20 / 35.01), "a 20-point arm cut bleeds 20 / 35.01 a cycle (got [H.blood_loss_rate(other)])")
	TEST_ASSERT(H.body_clock_active, "an open wound runs the clock")
	other.remove_wound(C)
	arm.remove_wound(W)
	H.body_clock_refresh()
	TEST_ASSERT(!H.body_clock_active, "a healthy, full body parks the clock")
	for(var/obj/effect/decal/cleanable/blood/B in range(1, H))
		qdel(B)

// --- Slice 2: external limbs (stance, grasp, fractures, splints) -------------------------------------------------

/proc/body_pin_fracture(obj/item/organ/external/E)
	E.fracture()
	E.owner?.body?.invalidate(BODY_DIRTY_ORGANS)

/// A human who lost a leg and its foot cannot stand: the stance follows the limbs at once.
/datum/unit_test/dq_body_pin/lost_leg_collapses

/datum/unit_test/dq_body_pin/lost_leg_collapses/pin(mob/living/carbon/human/H)
	var/obj/item/organ/external/leg = H.get_organ(BP_L_LEG)
	leg.droplimb(TRUE, DROPLIMB_EDGE)
	body_pin_frame(H)
	body_pin_frame(H)
	TEST_ASSERT(H.stance_damage >= 4, "a one-legged human cannot stand (stance damage [H.stance_damage])")
	for(var/obj/item/organ/external/loose in range(7, H))
		qdel(loose)

/// A fractured arm drops what its hand holds within a cycle.
/datum/unit_test/dq_body_pin/broken_arm_drops

/datum/unit_test/dq_body_pin/broken_arm_drops/pin(mob/living/carbon/human/H)
	var/obj/item/I = new /obj/item/stack/rods(H.loc)
	H.put_in_l_hand(I)
	TEST_ASSERT_EQUAL(H.get_equipped_item(SLOT_ID_HAND_L), I, "setup: the left hand holds the rods")
	body_pin_fracture(H.get_organ(BP_L_ARM))
	TEST_ASSERT(H.get_organ(BP_L_ARM).is_fractured(), "setup: the arm is fractured")
	body_pin_frame(H)
	body_pin_frame(H)
	TEST_ASSERT(H.get_equipped_item(SLOT_ID_HAND_L) != I, "a broken arm drops what it holds")
	qdel(I)

/// A splinted fractured arm keeps its grip.
/datum/unit_test/dq_body_pin/splinted_arm_holds

/datum/unit_test/dq_body_pin/splinted_arm_holds/pin(mob/living/carbon/human/H)
	var/obj/item/I = new /obj/item/stack/rods(H.loc)
	H.put_in_l_hand(I)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	body_pin_fracture(arm)
	var/obj/item/stack/medical/splint/S = new(arm)
	arm.apply_splint(S)
	for(var/i in 1 to 3)
		body_pin_frame(H)
	TEST_ASSERT_EQUAL(H.get_equipped_item(SLOT_ID_HAND_L), I, "a splinted arm keeps its grip")
	arm.remove_splint()
	qdel(S)
	qdel(I)

/// Enough trauma past the break threshold fractures the limb; a hurt limb is among the damaged limbs.
/datum/unit_test/dq_body_pin/trauma_fractures

/datum/unit_test/dq_body_pin/trauma_fractures/pin(mob/living/carbon/human/H)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	arm.create_wound(BRUISE, arm.min_broken_damage + 5)
	arm.update_damages()
	TEST_ASSERT(arm.is_fractured() == !!CONFIG_GET(flag/bones_can_break), "trauma past min_broken_damage fractures the arm when bones can break")
	body_pin_frame(H)
	TEST_ASSERT(arm in H.damaged_limbs(), "a hurt arm is among the damaged limbs")
	TEST_ASSERT(!(H.get_organ(BP_R_ARM) in H.damaged_limbs()), "a sound arm is not")

// --- Slice 3: internal organs -------------------------------------------------------------------------------------

/// A body carrying heavy toxin load hurts its liver over time.
/datum/unit_test/dq_body_pin/liver_toxin_overload

/datum/unit_test/dq_body_pin/liver_toxin_overload/pin(mob/living/carbon/human/H)
	var/obj/item/organ/internal/liver/L = H.organ_in(O_LIVER)
	H.injure(INJURY_TOXIN, 60, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	for(var/i in 1 to 20)
		body_pin_frame(H)
	body_pin_log("liver_toxin_overload", L.damage)
	TEST_ASSERT(body_pin_near(L.damage, 4, 1.7), "twenty cycles of heavy toxin load cost the liver about 4 (0.2 a cycle) (got [L.damage])")

/// Healthy kidneys clear a little toxin.
/datum/unit_test/dq_body_pin/kidneys_clear_toxin

/datum/unit_test/dq_body_pin/kidneys_clear_toxin/pin(mob/living/carbon/human/H)
	H.injure(INJURY_TOXIN, 8, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/before = H.injury_load(INJURY_CATEGORY_TOXIC)
	for(var/i in 1 to 30)
		body_pin_frame(H)
	var/after = H.injury_load(INJURY_CATEGORY_TOXIC)
	body_pin_log("kidneys_clear_toxin", "[before] -> [after]")
	TEST_ASSERT(after < before, "kidneys clear some toxin in thirty cycles ([before] -> [after])")

/// A healthy body's organs leave nothing to do.
/datum/unit_test/dq_body_pin/healthy_organs_idle

/datum/unit_test/dq_body_pin/healthy_organs_idle/pin(mob/living/carbon/human/H)
	for(var/obj/item/organ/I as anything in H.internal_organ_list())
		TEST_ASSERT(I.life_step_idle(), "[I] has nothing to do in a healthy body")

// --- Slice 4: germs and pain ---------------------------------------------------------------------------------------

/// Antibiotics in the blood bring an infected limb's germs down.
/datum/unit_test/dq_body_pin/antibiotics_clear_germs

/datum/unit_test/dq_body_pin/antibiotics_clear_germs/pin(mob/living/carbon/human/H)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	arm.adjust_germ_level(300)
	H.bloodstr.add_reagent(REAGENT_ID_SPACEACILLIN, 15)
	for(var/i in 1 to 10)
		body_pin_frame(H)
	body_pin_log("antibiotics_clear_germs", arm.germ_level)
	TEST_ASSERT(arm.germ_level < 300, "antibiotics lower a limb's germs ([arm.germ_level])")

/// A limb past the third infection level, untreated, dies.
/datum/unit_test/dq_body_pin/necrosis_kills_limb

/datum/unit_test/dq_body_pin/necrosis_kills_limb/pin(mob/living/carbon/human/H)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	arm.adjust_germ_level(INFECTION_LEVEL_THREE + 50)
	for(var/i in 1 to 3)
		body_pin_frame(H)
	TEST_ASSERT(arm.status & ORGAN_DEAD, "a limb past infection level three dies")

/// A hurt limb hurts: its pain step sends a pain message naming it. (The test human has no air to breathe, so it is made
/// conscious and the step is run once, directly.)
/datum/unit_test/dq_body_pin/hurt_limb_pain

/datum/unit_test/dq_body_pin/hurt_limb_pain/pin(mob/living/carbon/human/H)
	H.injure(INJURY_BLUNT, 15, BP_L_LEG, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	H.set_stat(CONSCIOUS)
	H.body.last_pain_message = ""
	H.body.next_pain_time = 0
	H.body.multilimb_pain_time = 0
	body_pin_pain_step(H)
	TEST_ASSERT(findtext(H.body.last_pain_message, "leg"), "a hurt leg sends a pain message (got '[H.body.last_pain_message]')")

/// Runs the pain messaging once.
/proc/body_pin_pain_step(mob/living/carbon/human/H)
	H.pain_step()

// --- Slice 5: surgery --------------------------------------------------------------------------------------------

/// A surgeon with a scalpel clicks the chest of a patient lying on an operating table: within the step's time the chest is incised
/// (or, on a slip, cut).
/datum/unit_test/dq_body_pin_surgery_incision

/datum/unit_test/dq_body_pin_surgery_incision/Run()
	test_driver_begin()
	test_rng(1)
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human)
	dq_give_zone_sel(surgeon)
	surgeon.next_click = 0
	// A clientless test human counts as SSD and is put to sleep; a teleoperated one is awake, as a surgeon must be.
	surgeon.teleop = surgeon
	surgeon.status_end(EFFECT_SLEEPING)
	surgeon.set_stat(CONSCIOUS)
	var/obj/machinery/optable/table = new(patient.loc)
	patient.status_set(EFFECT_WEAKENED, 30)
	patient.update_canmove()
	TEST_ASSERT(patient.lying, "setup: the patient is lying down")
	var/obj/item/surgical/scalpel/S = new(surgeon.loc)
	surgeon.put_in_active_hand(S)
	var/obj/item/organ/external/chest = patient.get_organ(BP_TORSO)
	var/wounds_before = length(chest.get_wounds())
	var/datum/op_result/R = test_click(surgeon, patient, S)
	body_pin_log("surgery_click", "[R ? "[R.key] outcome [R.outcome] reason [R.reason]" : "nothing resolved"]")
	test_time(12 SECONDS)
	body_pin_log("surgery_after", "[R?.key] outcome [R?.outcome] reason [R?.reason]")
	var/incised = chest.surgical_depth() >= INCISION_MADE
	var/slipped = length(chest.get_wounds()) > wounds_before
	body_pin_log("surgery_incision", "depth [chest.surgical_depth()] slipped [slipped]")
	TEST_ASSERT(incised || slipped, "the incision step ran to an outcome (depth [chest.surgical_depth()])")
	chest.get_incision()?.close_site()
	surgeon.teleop = null
	test_driver_end()
	qdel(S)
	qdel(table)
	for(var/obj/effect/decal/cleanable/B in range(1, patient))
		qdel(B)


// --- Slice 6: loose organs ---------------------------------------------------------------------------------------

/// A liver taken out of the body ticks on its own (one tick: a germ), and stops once it is dead.
/datum/unit_test/dq_body_pin/loose_organ_ticks

/datum/unit_test/dq_body_pin/loose_organ_ticks/pin(mob/living/carbon/human/H)
	var/obj/item/organ/internal/liver/L = H.organ_in(O_LIVER)
	L.removed()
	L.forceMove(H.loc)
	TEST_ASSERT(body_pin_ticks_loose(L), "a removed liver ticks on its own")
	var/before = L.germ_level
	body_pin_loose_tick(L)
	TEST_ASSERT(body_pin_close(L.germ_level, before + 1), "one loose tick gathers a germ ([before] -> [L.germ_level])")
	L.die()
	TEST_ASSERT(!body_pin_ticks_loose(L), "a dead loose organ stops ticking")
	qdel(L)

/proc/body_pin_ticks_loose(obj/item/organ/O)
	return O.organ_ticks_loose()

/proc/body_pin_loose_tick(obj/item/organ/O)
	O.loose_tick()
