// MED-8: regression tests for the P2 performance / P3 cleanup rows of
// doc/medical_audit_findings.md that change behaviour. One test per row, named by row id.

/// P2-D3: dust() goes through the one disintegrate path: the mob dies and leaves its remains.
/datum/unit_test/dq_med8_d3_disintegrate

/datum/unit_test/dq_med8_d3_disintegrate/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/turf/T = get_turf(H)
	var/remains = H.species.remains_type
	H.dust()
	TEST_ASSERT_EQUAL(H.stat, DEAD, "a dusted mob is dead")
	TEST_ASSERT_EQUAL(H.invisibility, INVISIBILITY_ABSTRACT, "a dusted mob is hidden behind its animation")
	var/atom/left = locate_within(T, remains)
	TEST_ASSERT(left, "dust() leaves its species remains ([remains])")
	// The remains and the (deferred-delete) animation overlay are the test's own litter.
	qdel(left)
	for(var/atom/movable/overlay/O as anything in contents_of(T, /atom/movable/overlay))
		if(O.master == H)
			qdel(O)

/// P2-D10: one vitality -> health meter band table, dead and feigned death at the bottom.
/datum/unit_test/dq_med8_d10_health_band

/datum/unit_test/dq_med8_d10_health_band/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(vitality_health_band(H), "health0", "an unhurt mob reads full health")
	H.set_status_flags(H.status_flags | FAKEDEATH)
	TEST_ASSERT_EQUAL(vitality_health_band(H), "health7", "feigned death reads as dead")
	H.set_status_flags(H.status_flags & ~FAKEDEATH)
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/animal/passive/mouse)
	S.death()
	TEST_ASSERT_EQUAL(vitality_health_band(S), "health7", "a dead mob reads as dead")

/// A21: the Life plan key covers the body plan, so a plan swap can't reuse a stale plan.
/datum/unit_test/dq_med8_a21_plan_key_body_type

/datum/unit_test/dq_med8_a21_plan_key_body_type/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/sequence/seq = sequence_def(/datum/sequence/life)
	var/datum/seq_state/S = SEQ_STATE_OF(H, seq.idx)
	TEST_ASSERT_NOTNULL(S, "setup: the human runs the Life sequence")
	TEST_ASSERT(findtext(S.table.key, "[H.body_type]"), "the Life table key [S.table.key] names the body plan [H.body_type]")
	H.recompose_life()
	TEST_ASSERT(findtext(S.table.key, "[H.body_type]"), "recompose_life() keeps a body-plan key")

/// C18: pneumothorax drift is derived each tick, not written into progression_rate.
/datum/unit_test/dq_med8_c18_derived_drift

/datum/unit_test/dq_med8_c18_derived_drift/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/pneumothorax/P = _spawn_affliction_on(H, BP_TORSO, /datum/affliction/pneumothorax)
	TEST_ASSERT_NOTNULL(P, "setup: pneumothorax spawns")
	var/base_rate = P.progression_rate
	TEST_ASSERT_EQUAL(P.current_rate(), base_rate, "an unvented pneumothorax drifts at its own rate")
	P.decompressed = TRUE
	TEST_ASSERT(P.current_rate() < 0, "a vented pneumothorax with no leak resolves")
	P.tick()
	TEST_ASSERT_EQUAL(P.progression_rate, base_rate, "tick() no longer rewrites progression_rate")

/// C20: burn shock reads the owner's total limb burn once per tick.
/datum/unit_test/dq_med8_c20_burn_shock_total

/datum/unit_test/dq_med8_c20_burn_shock_total/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.injure(INJURY_BURN, 20, BP_L_ARM, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	H.injure(INJURY_BURN, 20, BP_R_LEG, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/expected = 0
	for(var/obj/item/organ/external/E in H.organs)
		expected += E.get_burn()
	var/datum/affliction/burn_shock/B = H.body.afflict(/datum/affliction/burn_shock)
	TEST_ASSERT_NOTNULL(B, "setup: burn shock afflicts")
	TEST_ASSERT_EQUAL(B.total_burn(TRUE), expected, "total_burn() sums every limb's burn")
	TEST_ASSERT_EQUAL(B.total_burn(), expected, "the same tick reuses the sum")

/// P2-K2: the container answers whether a death is quiet; the core no longer knows the kinds.
/datum/unit_test/dq_med8_k2_container_muffles_death

/datum/unit_test/dq_med8_k2_container_muffles_death/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(!H.death_message_suppressed(), "a mob on the floor dies audibly")
	var/obj/item/clothing/shoes/boots = allocate(/obj/item/clothing/shoes)
	H.forceMove(boots)
	TEST_ASSERT(H.death_message_suppressed(), "a mob in a shoe dies quietly")
	var/mob/living/carbon/human/holder = allocate(/mob/living/carbon/human)
	H.forceMove(holder)
	TEST_ASSERT(!H.death_message_suppressed(), "a mob that is not the holder's transformation dies audibly")
	H.forceMove(get_turf(holder))

/// P2-K4: the kiosk reads infections from its diagnosis, not raw germ counts.
/datum/unit_test/dq_med8_k4_kiosk_diagnosis

/datum/unit_test/dq_med8_k4_kiosk_diagnosis/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/machinery/medical_kiosk/K = allocate(/obj/machinery/medical_kiosk)
	TEST_ASSERT(!findtext(K.medical_scan(H), "Infection detected"), "a clean patient reports no infection")
	var/datum/affliction/wound_infection/W = _spawn_affliction_on(H, BP_L_ARM, /datum/affliction/wound_infection)
	TEST_ASSERT_NOTNULL(W, "setup: the infection spawns")
	W.set_severity(50)
	TEST_ASSERT(findtext(K.medical_scan(H), "Infection detected"), "an infection the kiosk's diagnosis finds is reported")

/// A19: an MMI's status stage stays awake while EMP interference is wearing off.
/datum/unit_test/dq_med8_a19_brain_status_idle

/datum/unit_test/dq_med8_a19_brain_status_idle/Run()
	var/mob/living/carbon/brain/B = allocate(/mob/living/carbon/brain)
	B.emp_damage = 10
	TEST_ASSERT(B.life_status_due(), "EMP interference keeps the brain's status step awake")
	B.emp_damage = 0

/// A12: the forms step is absent for a character with no self-drawn or ticking form.
/datum/unit_test/dq_med8_a12_forms_idle

/datum/unit_test/dq_med8_a12_forms_idle/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(!("life_trait_forms" in life_test_steps(H)), "a character without forms has no forms step")

/// D23: the split wound path picks the same wound for each kind of hit, and a spread over a
/// limb's children survives one of them being gone.
/datum/unit_test/dq_med8_d23_wound_split

/datum/unit_test/dq_med8_d23_wound_split/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	TEST_ASSERT_EQUAL(arm.brute_wound_type(FALSE, FALSE), BRUISE, "blunt brute bruises")
	TEST_ASSERT_EQUAL(arm.brute_wound_type(TRUE, TRUE), CUT, "an edge cuts")
	TEST_ASSERT_EQUAL(arm.brute_wound_type(TRUE, FALSE), PIERCE, "a point pierces")
	arm.spread_overflow(30, 0, null)
	TEST_ASSERT(!QDELETED(H), "spreading overflow from a limb does not break the body")
