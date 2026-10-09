// Body effects (code/modules/body/body_effects.dm, MED-5): factor-only effects as OM
// contributions on the body clock.

/datum/body_effect/dq_test_stack
	name = "test stack"
	stacks = MODIFIER_STACK_ALLOWED
	factors = alist(BF_SLOWDOWN = 1)

/datum/body_effect/dq_test_forbid
	name = "test forbid"
	stacks = MODIFIER_STACK_FORBID
	factors = alist(BF_SLOWDOWN = 1)

/// A timed body effect applies its factors, expires on time, and a stasis hold stops the countdown.
/datum/unit_test/dq_body_effect_expires_on_body_clock

/datum/unit_test/dq_body_effect_expires_on_body_clock/Run()
	scheduler_test_begin()
	var/mob/living/carbon/human/H = new(null)
	var/base = H.factor(BF_SLOWDOWN)
	TEST_ASSERT(H.apply_body_effect(/datum/body_effect/entangled, 4 SECONDS), "entangled should take hold")
	TEST_ASSERT(H.has_body_effect(/datum/body_effect/entangled), "entangled should be on the mob")
	TEST_ASSERT(dq_near(H.factor(BF_SLOWDOWN), base + 2), "entangled adds 2 slowdown, got [H.factor(BF_SLOWDOWN)] over [base]")
	TEST_ASSERT(H.has_body_effect(/datum/body_effect/entangled), "the modifier compatibility query must see body effects")

	var/datum/stasis_source = new
	hold(H, STAT_CLOCK_RATE_BIO, 0, stasis_source, clock = HOLD_CLOCK_WORLD)
	scheduler_advance(10)
	TEST_ASSERT(H.has_body_effect(/datum/body_effect/entangled), "full stasis must stop a body effect's countdown")

	release(H, STAT_CLOCK_RATE_BIO, stasis_source)
	scheduler_advance(5)
	TEST_ASSERT(!H.has_body_effect(/datum/body_effect/entangled), "entangled should expire once body time passes its duration")
	TEST_ASSERT(dq_near(H.factor(BF_SLOWDOWN), base), "the factor should return to baseline, got [H.factor(BF_SLOWDOWN)]")
	qdel(stasis_source)
	qdel(H)
	scheduler_test_end()

/// EXTEND refreshes to the longer duration; ALLOWED stacks factors per application; FORBID ignores repeats.
/datum/unit_test/dq_body_effect_stacking_rules

/datum/unit_test/dq_body_effect_stacking_rules/Run()
	scheduler_test_begin()
	var/mob/living/carbon/human/H = new(null)
	var/base = H.factor(BF_SLOWDOWN)

	H.apply_body_effect(/datum/body_effect/entangled, 2 SECONDS)
	H.apply_body_effect(/datum/body_effect/entangled, 6 SECONDS)
	TEST_ASSERT(H.body_effect_remaining(/datum/body_effect/entangled) > 4 SECONDS, "a longer reapplication should extend an EXTEND effect")
	TEST_ASSERT_EQUAL(H.body_effect_stacks(/datum/body_effect/entangled), 1, "EXTEND never stacks")
	H.remove_body_effect(/datum/body_effect/entangled, TRUE)
	TEST_ASSERT(!H.has_body_effect(/datum/body_effect/entangled), "remove_body_effect ends it")

	H.apply_body_effect(/datum/body_effect/dq_test_stack, 2 SECONDS)
	H.apply_body_effect(/datum/body_effect/dq_test_stack, 6 SECONDS)
	TEST_ASSERT_EQUAL(H.body_effect_stacks(/datum/body_effect/dq_test_stack), 2, "ALLOWED stacks per application")
	TEST_ASSERT(dq_near(H.factor(BF_SLOWDOWN), base + 2), "two stacks apply the table twice, got [H.factor(BF_SLOWDOWN)]")
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(H.body_effect_stacks(/datum/body_effect/dq_test_stack), 1, "the shorter stack expires on its own")
	scheduler_advance(4)
	TEST_ASSERT(!H.has_body_effect(/datum/body_effect/dq_test_stack), "the last stack expires")

	H.apply_body_effect(/datum/body_effect/dq_test_forbid, 2 SECONDS)
	TEST_ASSERT(!H.apply_body_effect(/datum/body_effect/dq_test_forbid, 10 SECONDS), "FORBID refuses a second application")
	scheduler_advance(3)
	TEST_ASSERT(!H.has_body_effect(/datum/body_effect/dq_test_forbid), "a refused reapplication must not extend a FORBID effect")
	qdel(H)
	scheduler_test_end()

/// Curing doom (curea removes it) lifts it; only running out kills.
/datum/unit_test/dq_body_effect_doom_cure_does_not_kill

/datum/unit_test/dq_body_effect_doom_cure_does_not_kill/Run()
	scheduler_test_begin()
	var/mob/living/carbon/human/H = new(null)
	H.apply_body_effect(/datum/body_effect/doomed, 30 SECONDS)
	H.remove_body_effect(/datum/body_effect/doomed, TRUE)
	TEST_ASSERT(H.stat != DEAD, "removing doom must not kill the patient")
	qdel(H)
	scheduler_test_end()

/// The poisoned modifier is a lingering poisoning affliction now: synthetics are spared by
/// biology, organics get a self-resolving toxin.
/datum/unit_test/dq_lingering_poison_is_an_affliction

/datum/unit_test/dq_lingering_poison_is_an_affliction/Run()
	var/mob/living/carbon/human/H = new(null)
	H.lingering_poison(1, 30 SECONDS)
	TEST_ASSERT(H.has_affliction(/datum/affliction/venom/lingering_poison), "a lingering poison dose should afflict an organic patient")
	TEST_ASSERT(H.injury_load(INJURY_CATEGORY_TOXIC) > 0, "the poisoning counts toward toxic load")
	qdel(H)

/// MED-6: the former polling life stages idle on a healthy, idle human (they wake on events or
/// their rewake instead of running every cycle).
/datum/unit_test/dq_med6_life_stages_idle_when_healthy

/datum/unit_test/dq_med6_life_stages_idle_when_healthy/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.phobias = 0
	H.weight_gain = 0
	H.weight_loss = 0
	H.set_bodytemperature(H.species.body_temperature || H.body_temperature())
	// A fresh body starts with every domain dirty; its first medical pass settles them
	// (factors recomputed, dirty condition domains processed), as the first Life() would.
	H.factor(BF_ALLERGY)
	H.dq_process_dirty_medical_conditions()
	var/list/steps = list(
		"life_medical",
		"life_npc",
		"life_changeling",
		"life_shock",
		"life_heartbeat",
		"life_weight",
		"life_nif",
		"life_phobias",
		"life_addictions",
		"life_radiation",
	)
	var/datum/sequence/seq = sequence_def(/datum/sequence/life)
	var/datum/seq_state/state = SEQ_STATE_OF(H, seq.idx)
	for(var/key in steps)
		var/pos = state?.table.pos_of[key]
		if(!pos)
			continue
		var/datum/seq_step/S = state.table.steps[pos]
		TEST_ASSERT(!seq_should_run(S, H, state), "[key] should sleep on a healthy human")
