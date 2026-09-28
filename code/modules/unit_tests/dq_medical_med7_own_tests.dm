// MED-7: regression tests for the CLOCK / OWN / NULL rows of doc/medical_audit_findings.md.
// One test per row, named by row id.

/// D17: a wound's bleed timer runs down by biological time, not by how often update_damages() runs.
/datum/unit_test/dq_med7_d17_bleed_timer_clock

/datum/unit_test/dq_med7_d17_bleed_timer_clock/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.injure(INJURY_CUT, 15, BP_L_ARM)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/list/wounds = arm.get_wounds()
	TEST_ASSERT(length(wounds), "setup: the cut should leave a wound")
	var/datum/affliction/wound/W = wounds[1]
	W.bleed_timer = 10
	W.bleed_clock_at = null
	W.run_bleed_clock(1000, TRUE)
	TEST_ASSERT_EQUAL(W.bleed_timer, 10, "the first reading only anchors the clock")
	for(var/i in 1 to 20)
		W.run_bleed_clock(1000, TRUE)
	TEST_ASSERT_EQUAL(W.bleed_timer, 10, "repeated calls at the same biological time cost nothing")
	W.run_bleed_clock(1000 + 3 * LIFE_CYCLE, TRUE)
	TEST_ASSERT_EQUAL(W.bleed_timer, 7, "three life cycles of bleeding cost three")
	W.run_bleed_clock(1000 + 6 * LIFE_CYCLE, FALSE)
	TEST_ASSERT_EQUAL(W.bleed_timer, 7, "time spent not bleeding costs nothing")

/// D10: one defib window on the brain, in real minutes of biological time, read by revival,
/// CPR/defib brain damage and the analyzer.
/datum/unit_test/dq_med7_d10_defib_window

/datum/unit_test/dq_med7_d10_defib_window/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/brain = H.internal_organs_by_name[O_BRAIN]
	TEST_ASSERT(istype(brain), "setup: the human needs a brain")
	brain.reset_defib_window()
	TEST_ASSERT_EQUAL(brain.defib_window_left(), CONFIG_GET(number/defib_timer) MINUTES, "a fresh brain has the whole configured window")
	TEST_ASSERT_EQUAL(H.revival_window_left(), brain.defib_window_left(), "the analyzer reads the same window")
	TEST_ASSERT_EQUAL(brain.revival_brain_damage(0), 0, "no brain damage early in the window")
	brain.defib_elapsed = defib_window_length() - defib_braindamage_length() / 2
	brain.defib_clock_at = null
	TEST_ASSERT(brain.revival_brain_damage(0) > 0, "late in the window a revival costs brain damage")
	brain.expire_defib_window()
	TEST_ASSERT_EQUAL(brain.defib_window_left(), 0, "an expired window is closed")
	TEST_ASSERT_EQUAL(H.revival_window_refusal(), "brain decayed", "a closed window refuses revival")
	brain.reset_defib_window()

/// D10: dying starts the window running on the owner's clock; living brains don't decay.
/datum/unit_test/dq_med7_d10_defib_window_follows_death

/datum/unit_test/dq_med7_d10_defib_window_follows_death/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/brain = H.internal_organs_by_name[O_BRAIN]
	TEST_ASSERT(istype(brain), "setup: the human needs a brain")
	brain.reset_defib_window()
	TEST_ASSERT(!brain.defib_decaying, "a living owner's brain does not decay")
	H.death()
	TEST_ASSERT(brain.defib_decaying, "death starts the defib window running down")

/// D15a: a tourniquet that leaves the limb by any path stops occluding it.
/datum/unit_test/dq_med7_d15a_tourniquet_release

/datum/unit_test/dq_med7_d15a_tourniquet_release/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/obj/item/tourniquet/T = allocate(/obj/item/tourniquet)
	TEST_ASSERT(arm.apply_tourniquet(T), "setup: the tourniquet should cinch")
	TEST_ASSERT(arm.flow_occluded(), "setup: the arm is occluded")
	T.forceMove(run_loc_floor_bottom_left)
	TEST_ASSERT_NULL(arm.tourniquet, "moving the tourniquet off the limb clears it")
	TEST_ASSERT(!arm.flow_occluded(), "flow returns once the tourniquet is gone")
	var/obj/item/tourniquet/T2 = allocate(/obj/item/tourniquet)
	TEST_ASSERT(arm.apply_tourniquet(T2), "setup: a second tourniquet should cinch")
	qdel(T2)
	TEST_ASSERT_NULL(arm.tourniquet, "deleting the tourniquet clears it")
	TEST_ASSERT(!arm.flow_occluded(), "flow returns once the tourniquet is deleted")

/// P2-D11: rejuvenating a borg does not give it nutrition or a body temperature reset.
/datum/unit_test/dq_med7_p2d11_robot_rejuvenate

/datum/unit_test/dq_med7_p2d11_robot_rejuvenate/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, run_loc_floor_bottom_left)
	R.set_nutrition(0)
	R.set_bodytemperature(350)
	R.rejuvenate()
	TEST_ASSERT_EQUAL(R.nutrition, 0, "a borg has no nutrition to refill")
	TEST_ASSERT_EQUAL(R.bodytemperature, 350, "a borg's temperature is not reset to T20C")

/// C11: a ticking body no longer rebuilds the treatment snapshot every cycle; regeneration is
/// re-read from the body clock instead.
/datum/unit_test/dq_med7_c11_regeneration_on_read

/datum/unit_test/dq_med7_c11_regeneration_on_read/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.set_nutrition(400)
	H.body.treatment_levels()
	H.body.life_tick()
	TEST_ASSERT(!(H.body.dirty & BODY_DIRTY_TREATMENT), "a life tick must not invalidate the treatment snapshot")
	TEST_ASSERT(H.body.treatment_levels()?[TREAT_REGENERATION] > 0, "a fed body regenerates")
	H.set_nutrition(REGENERATION_STARVING_NUTRITION - 1)
	H.body.regeneration_read_at = -1 // the body clock moved on
	TEST_ASSERT(!H.body.treatment_levels()?[TREAT_REGENERATION], "a starving body stops regenerating on the next read")

/// C24: tearing a body down with its owner unlinks afflictions without hooks.
/datum/unit_test/dq_med7_c24_quiet_teardown

/datum/unit_test/dq_med7_c24_quiet_teardown/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.internal_organs_by_name[O_LIVER]
	var/datum/affliction/custom/A = H.body.afflict(/datum/affliction/custom, liver, 10)
	TEST_ASSERT_NOTNULL(A, "setup: the affliction should land")
	H.body.dirty = 0
	TEST_ASSERT(H.body.unlink_affliction(A), "the affliction unlinks")
	TEST_ASSERT_NULL(A.body, "the unlinked affliction has no body")
	TEST_ASSERT(!(H.body.dirty & BODY_DIRTY_VITALS), "unlinking does not invalidate the body")
	qdel(A)

/// D12: bioregenerating a loose limb clears its tissue necrosis.
/datum/unit_test/dq_med7_d12_bioregen_clears_necrosis

/datum/unit_test/dq_med7_d12_bioregen_clears_necrosis/Run()
	var/obj/item/organ/external/arm/arm = allocate(/obj/item/organ/external/arm)
	var/datum/affliction/tissue_necrosis/N = new(arm)
	N.location = arm
	LAZYADD(arm.detached_afflictions, N)
	arm.clear_necrosis()
	var/list/remaining = arm.afflictions_here()
	var/datum/affliction/tissue_necrosis/left = locate_in_list(remaining, /datum/affliction/tissue_necrosis)
	TEST_ASSERT_NULL(left, "bioregeneration removes the necrosis")

/// D20: verb compatibility with a missing parent limb answers FALSE instead of runtiming.
/datum/unit_test/dq_med7_d20_verb_compat_missing_parent

/datum/unit_test/dq_med7_d20_verb_compat_missing_parent/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/heart = H.internal_organs_by_name[O_HEART]
	TEST_ASSERT_NOTNULL(heart, "setup: the human needs a heart")
	var/old_parent = heart.parent_organ
	heart.parent_organ = "no such limb"
	TEST_ASSERT(!heart.check_verb_compatability(), "no parent limb: not compatible")
	heart.parent_organ = old_parent

/// P2-D9: control efficiency is an interface on every brain-slot organ.
/datum/unit_test/dq_med7_p2d9_control_efficiency

/datum/unit_test/dq_med7_p2d9_control_efficiency/Run()
	var/obj/item/organ/internal/mmi_holder/holder = allocate(/obj/item/organ/internal/mmi_holder)
	TEST_ASSERT_EQUAL(holder.get_control_efficiency(), 1, "an undamaged MMI holder is fully in control")
	var/obj/item/organ/internal/brain/brain = allocate(/obj/item/organ/internal/brain)
	TEST_ASSERT_EQUAL(brain.get_control_efficiency(), 1, "an undamaged brain is fully in control")

/// P2-K1: installing an MMI puts it inside its holder, which takes the brain slot.
/datum/unit_test/dq_med7_p2k1_install_mmi_holder

/datum/unit_test/dq_med7_p2k1_install_mmi_holder/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/brain = H.internal_organs_by_name[O_BRAIN]
	brain?.removed()
	qdel(brain)
	var/obj/item/mmi/M = allocate(/obj/item/mmi)
	var/obj/item/organ/internal/mmi_holder/holder = install_mmi_holder(H, M)
	TEST_ASSERT_NOTNULL(holder, "a holder is made")
	TEST_ASSERT_EQUAL(M.loc, holder, "the MMI sits inside its holder")
	TEST_ASSERT_EQUAL(H.internal_organs_by_name[O_BRAIN], holder, "the holder takes the brain slot")

/// D24: a limb's wound view is cached until a wound changes, and a rebuild replaces the list
/// instead of mutating the one a caller may still be iterating.
/datum/unit_test/dq_med7_d24_cached_wound_view

/datum/unit_test/dq_med7_d24_cached_wound_view/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	H.injure(INJURY_CUT, 10, BP_L_ARM)
	var/list/first = arm.get_wounds()
	TEST_ASSERT(length(first), "setup: the cut leaves a wound")
	TEST_ASSERT(arm.get_wounds() == first, "an unchanged limb returns the cached view")
	var/count = length(first)
	H.injure(INJURY_BURN, 10, BP_L_ARM)
	var/list/second = arm.get_wounds()
	TEST_ASSERT(second != first, "a new wound rebuilds the view")
	TEST_ASSERT(length(second) > count, "the rebuilt view holds the new wound")
	TEST_ASSERT_EQUAL(length(first), count, "the old view is left intact for its reader")

/// A14: global HUD overlays are claimed by providers and reconciled; claims are a set and a
/// reconcile consumes them.
/datum/unit_test/dq_med7_a14_global_hud_claims

/datum/unit_test/dq_med7_a14_global_hud_claims/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.claim_global_hud(GLOB.global_hud.meson)
	H.claim_global_hud(GLOB.global_hud.meson)
	H.claim_global_hud(null)
	TEST_ASSERT_EQUAL(LAZYLEN(H.global_hud_claims), 1, "claims are a set")
	H.reconcile_global_huds()
	TEST_ASSERT_NULL(H.global_hud_claims, "a reconcile consumes the claims")
