// Emag as an interaction (doc/rewrite/systems.md section 13).

/obj/dq_emag_probe
	name = "emag probe"
	anchored = TRUE
	var/emagged = FALSE
	var/hits = 0
	var/refuse = FALSE

DECLARE_EMAG(/obj/dq_emag_probe, PROC_REF(on_emag), "You short the probe.", "The probe is already shorted.")

/obj/dq_emag_probe/mark_emagged()
	emagged = TRUE
/obj/dq_emag_probe/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	if(refuse)
		return EMAG_DECLINED
	hits++
	return 1

/// Repeatable subtype: no gate, the field is left alone.
/obj/dq_emag_probe/toggle
DECLARE_EMAG_REPEATABLE(/obj/dq_emag_probe/toggle, PROC_REF(on_emag), null)

/// A card on a gated target: the effect runs once, the field is set, a use is paid; again, refused.
/datum/unit_test/dq_sys_emag_gated

/datum/unit_test/dq_sys_emag_gated/Run()
	var/turf/T = test_floor()
	var/obj/dq_emag_probe/probe = allocate(/obj/dq_emag_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, T)
	var/start = card.uses

	var/datum/interaction/emag = emag_interaction_for(probe)
	TEST_ASSERT_EQUAL(emag, INTERACTION(/datum/interaction/emag/gated), "DECLARE_EMAG offers the gated interaction")
	TEST_ASSERT(emag in interaction_candidates(probe), "the emag interaction is one of the type's candidates")
	TEST_ASSERT_EQUAL(emag.attempt(H, probe, card), INTERACTION_TRY_RAN, "the first emag runs")
	TEST_ASSERT_EQUAL(probe.hits, 1, "the declared effect ran")
	TEST_ASSERT(probe.emagged, "the emagged field is set")
	TEST_ASSERT_EQUAL(card.uses, start - 1, "one use paid")
	TEST_ASSERT_EQUAL(emag.attempt(H, probe, card), INTERACTION_TRY_BLOCKED, "an emagged target refuses")
	TEST_ASSERT_EQUAL(EMAG_DECL(probe)[EMAG_DECL_ALREADY], "The probe is already shorted.", "the per-type refusal text is declared")
	TEST_ASSERT_EQUAL(probe.hits, 1, "the refused emag did nothing")
	TEST_ASSERT_EQUAL(card.uses, start - 1, "the refused emag paid nothing")
	TEST_ASSERT_EQUAL(emag_target(probe, 1, H), EMAG_DECLINED, "emag_target honours the gate")

/// Repeatable and declining effects, and a type with no declaration.
/datum/unit_test/dq_sys_emag_repeatable

/datum/unit_test/dq_sys_emag_repeatable/Run()
	var/turf/T = test_floor()
	var/obj/dq_emag_probe/toggle/probe = allocate(/obj/dq_emag_probe/toggle, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_EQUAL(emag_interaction_for(probe), INTERACTION(/datum/interaction/emag), "a repeatable declaration has no gate")
	TEST_ASSERT_EQUAL(emag_target(probe, 5, H), 1, "the effect's uses come back")
	TEST_ASSERT_EQUAL(emag_target(probe, 5, H), 1, "a repeatable effect runs again")
	TEST_ASSERT(!probe.emagged, "a repeatable effect leaves the field alone")
	probe.refuse = TRUE
	TEST_ASSERT_EQUAL(emag_target(probe, 5, H), EMAG_DECLINED, "a declining effect declines")
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	TEST_ASSERT_NULL(emag_interaction_for(wrench), "an undeclared type offers no emag")
	TEST_ASSERT_EQUAL(emag_target(wrench, 5, H), EMAG_DECLINED, "an undeclared type declines")
