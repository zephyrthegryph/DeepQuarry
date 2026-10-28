// Spells ask their caster for targets through target_questions() (code/modules/spells/spell_code.dm): the answers cast, a closed question
// drops a one-target cast and ends a many-target pick with the targets picked so far.

/datum/unit_test/dq_spell_ask
	abstract_type = /datum/unit_test/dq_spell_ask

/datum/unit_test/dq_spell_ask/Run()
	test_driver_begin()
	run_spell_ask()
	test_driver_end()

/datum/unit_test/dq_spell_ask/proc/run_spell_ask()
	return

/// A selectable two-target stun that takes its charge from a counter.
/datum/spell/targeted/dq_ask_stun
	spell_flags = SELECTABLE
	charge_type = Sp_CHARGES
	charge_max = 3
	cast_delay = 0
	range = 1
	max_targets = 2
	amt_stunned = 2 SECONDS
	compatible_mobs = list(/mob/living)

/// Many targets: the first pick is stunned, closing the second question casts with the first only.
/datum/unit_test/dq_spell_ask/many_targets
/datum/unit_test/dq_spell_ask/many_targets/run_spell_ask()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/caster = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human, T)
	var/datum/spell/targeted/dq_ask_stun/spell = allocate(/datum/spell/targeted/dq_ask_stun)
	TEST_ASSERT(caster.add_spell(spell), "the caster receives the spell")
	spell.perform(caster)
	TEST_ASSERT_EQUAL(spell.charge_counter, 3, "nothing is cast before the first question is answered")
	TEST_ASSERT(SSrequests.open_for(caster), "the first question is open")
	test_answer(caster, first)
	TEST_ASSERT(SSrequests.open_for(caster), "the second question is open once the first is answered")
	test_answer(caster, null, REQ_CANCELLED)
	TEST_ASSERT(first.has_status(STAT_STUNNED), "the picked mob is stunned")
	TEST_ASSERT(!second.has_status(STAT_STUNNED), "closing the second question picks no more")
	TEST_ASSERT_EQUAL(spell.charge_counter, 2, "the cast with the picks so far costs one charge")

/// Many targets: closing the first question picks none, so nothing is cast and no charge is spent (the old cancel_answer = "" gave no targets).
/datum/unit_test/dq_spell_ask/many_targets_first_closed
/datum/unit_test/dq_spell_ask/many_targets_first_closed/run_spell_ask()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/caster = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	var/datum/spell/targeted/dq_ask_stun/spell = allocate(/datum/spell/targeted/dq_ask_stun)
	TEST_ASSERT(caster.add_spell(spell), "the caster receives the spell")
	spell.perform(caster)
	test_answer(caster, null, REQ_CANCELLED)
	TEST_ASSERT(!other.has_status(STAT_STUNNED), "a closed first question casts nothing")
	TEST_ASSERT_EQUAL(spell.charge_counter, 3, "a closed first question costs no charge")

/// One target: closing the question drops the cast.
/datum/unit_test/dq_spell_ask/single_target_cancel
/datum/unit_test/dq_spell_ask/single_target_cancel/run_spell_ask()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/caster = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	var/datum/spell/targeted/dq_ask_stun/spell = allocate(/datum/spell/targeted/dq_ask_stun)
	spell.max_targets = 1
	TEST_ASSERT(caster.add_spell(spell), "the caster receives the spell")
	spell.perform(caster)
	test_answer(caster, null, REQ_CANCELLED)
	TEST_ASSERT(!other.has_status(STAT_STUNNED), "a closed question casts nothing")
	TEST_ASSERT_EQUAL(spell.charge_counter, 3, "a closed question costs no charge")

/// Scribing a teleport rune asks the rune, then its last word.
/datum/unit_test/dq_spell_ask/rune_teleport
/datum/unit_test/dq_spell_ask/rune_teleport/run_spell_ask()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/datum/spell/rune_write/spell = allocate(/datum/spell/rune_write)
	spell.spell_flags = NONE
	spell.charge_counter = 42
	runerandom()
	spell.perform_cast(user, TRUE)
	test_answer(user, "Teleport")
	test_answer(user, "ire")
	own_turf_contents(T)
	var/obj/effect/rune/rune = locate_within(T, /obj/effect/rune)
	TEST_ASSERT(istype(rune), "the answered questions scribe a rune")
	TEST_ASSERT_EQUAL(rune.word1, GLOB.cultwords["travel"], "the teleport rune's first word")
	TEST_ASSERT_EQUAL(rune.word3, "ire", "the answered last word")

/// Handing out the cult words leaves the full rune-word set for the last-word question to offer.
/datum/unit_test/dq_rune_words_kept
/datum/unit_test/dq_rune_words_kept/Run()
	var/before = length(GLOB.rnwords)
	TEST_ASSERT(before > 0, "the rune-word set starts filled")
	runerandom()
	TEST_ASSERT_EQUAL(length(GLOB.rnwords), before, "randomizing the cult words leaves the rune-word set whole")
	var/list/handed = list()
	for(var/word in GLOB.engwords)
		TEST_ASSERT(GLOB.cultwords[word] in GLOB.rnwords, "[word] is given a rune word")
		TEST_ASSERT(!(GLOB.cultwords[word] in handed), "[word] gets a rune word of its own")
		handed += GLOB.cultwords[word]
