// C7: vore on slots (doc/rewrite/containment.md §9). Bellies are sealed slots,
// cycle on SSreactor only while occupied, scale every mode by elapsed time,
// check consent through predicates and share their message lists.

/// A pred and a prey on the same floor, with vore set up.
/datum/unit_test/proc/vore_test_pair()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/pred = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/prey = allocate(/mob/living/carbon/human, T)
	pred.init_vore(TRUE)
	return list(pred, prey)

/// Runs `cycles` belly cycles of `seconds` each on `B`, driving prey Life at the same pace.
/proc/vore_test_cycles(obj/belly/B, cycles, seconds = BELLY_BASELINE_TICK / (1 SECONDS))
	for(var/i in 1 to cycles)
		if(QDELETED(B))
			return
		B.belly_cycle(seconds)

/// An empty belly costs nothing: no reactor work, no owned lists, shared messages.
/datum/unit_test/dq_vore_empty_belly_costs_nothing

/datum/unit_test/dq_vore_empty_belly_costs_nothing/Run()
	var/list/pair = vore_test_pair()
	var/mob/living/carbon/human/pred = pair[1]
	var/mob/living/carbon/human/other = pair[2]
	other.init_vore(TRUE)
	TEST_ASSERT(length(pred.vore_organs), "the pred should have a belly")
	for(var/obj/belly/B as anything in pred.vore_organs)
		TEST_ASSERT_NULL(B.cycle_token, "empty [B] should not cycle")
		TEST_ASSERT_NULL(B.liquid_timer, "empty [B] should hold no timer")
		TEST_ASSERT(!B.reactor_id, "empty [B] should hold no reactor state")
		TEST_ASSERT(!(B.datum_flags & DF_ISPROCESSING), "empty [B] should not be on a processing subsystem")
		var/list/owned = B.belly_owned_lists()
		TEST_ASSERT_EQUAL(length(owned), 0, "empty [B] owns lists: [jointext(owned, ", ")]")
		TEST_ASSERT_NULL(B.react_sleep_violation(), "empty [B] breaks its sleep rule")
	var/obj/belly/mine = pred.vore_selected
	var/obj/belly/theirs = other.vore_selected
	TEST_ASSERT(mine.digest_messages_prey == theirs.digest_messages_prey, "two default bellies should share one digest message list")
	TEST_ASSERT(mine.emote_lists == theirs.emote_lists, "two default bellies should share one emote table")
	TEST_ASSERT(mine.generated_reagents == theirs.generated_reagents, "two default bellies should share one liquid table")
	TEST_ASSERT_EQUAL(length(belly_default_lists()["emote_lists"]), 0, "the shared emote table must stay empty")

/// Subtype message lists are shared per type.
/datum/unit_test/dq_vore_subtype_lists_shared

/datum/unit_test/dq_vore_subtype_lists_shared/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/belly/dragon/maw/A = allocate(/obj/belly/dragon/maw, H)
	var/obj/belly/dragon/maw/B = allocate(/obj/belly/dragon/maw, H)
	TEST_ASSERT(A.struggle_messages_inside == B.struggle_messages_inside, "two bellies of one type should share their type's struggle messages")
	TEST_ASSERT(A.struggle_messages_inside != belly_default_lists()["struggle_messages_inside"], "a subtype's own messages should not be the base default")
	TEST_ASSERT(A.digest_messages_owner == belly_default_lists()["digest_messages_owner"], "a var the subtype leaves alone should be the base default")

/// Devour, struggle, transfer and release are ledger moves, and the cycle follows occupancy.
/datum/unit_test/dq_vore_devour_struggle_release

/datum/unit_test/dq_vore_devour_struggle_release/Run()
	var/list/pair = vore_test_pair()
	var/mob/living/carbon/human/pred = pair[1]
	var/mob/living/carbon/human/prey = pair[2]
	var/obj/belly/B = pred.vore_selected
	var/obj/belly/B2 = new /obj/belly(pred)
	B2.name = "Second"

	TEST_ASSERT(pred.begin_instant_nom(pred, prey, pred, B), "an instant nom should succeed")
	TEST_ASSERT_EQUAL(prey.loc, B, "prey should be in the belly")
	TEST_ASSERT_EQUAL(B.slot_entry_id(prey) ? TRUE : FALSE, TRUE, "prey should hold an entry in the belly's slot")
	var/datum/om/relation/slot/def = dq_path_slot_of(B, prey)
	TEST_ASSERT_EQUAL(def?.slot_id, BELLY_SLOT_INTERIOR, "prey should be in the belly interior slot")
	TEST_ASSERT_EQUAL(def?.exposure, SLOT_EXPOSURE_SEALED, "a belly is sealed")
	TEST_ASSERT(def?.reaches_mobs, "a belly reaches the mobs inside")
	TEST_ASSERT(B.cycle_token, "an occupied belly should cycle")
	TEST_ASSERT_NULL(B.react_sleep_violation(), "occupied belly breaks its schedule rule")

	// Struggle: inescapable holds; a sure transfer moves the prey on through the ledger.
	B.escapable = B_ESCAPABLE_NONE
	B.relay_resist(prey)
	TEST_ASSERT_EQUAL(prey.loc, B, "struggling in an inescapable belly should not free the prey")
	B.escapable = B_ESCAPABLE_DEFAULT
	B.escapechance = 0
	B.transferchance = 100
	B.transferlocation = B2.name
	B.relay_resist(prey)
	TEST_ASSERT_EQUAL(prey.loc, B2, "a sure transfer should move the prey to the second belly")
	TEST_ASSERT_EQUAL(dq_path_slot_of(B2, prey)?.slot_id, BELLY_SLOT_INTERIOR, "the transfer should land in the second belly's slot")
	TEST_ASSERT_NULL(B.cycle_token, "the emptied belly should stop cycling")
	TEST_ASSERT(B2.cycle_token, "the occupied second belly should cycle")

	TEST_ASSERT(B2.release_specific_contents(prey, silent = TRUE), "release should report the prey")
	TEST_ASSERT_EQUAL(prey.loc, pred.loc, "released prey should land at the pred's feet")
	TEST_ASSERT_NULL(B2.cycle_token, "an emptied belly should stop cycling")
	TEST_ASSERT_NULL(B2.slot_entry_id(prey), "released prey should leave the ledger")

/// Refused devours and refused modes give the preference's reason.
/datum/unit_test/dq_vore_consent_reasons

/datum/unit_test/dq_vore_consent_reasons/Run()
	var/list/pair = vore_test_pair()
	var/mob/living/carbon/human/pred = pair[1]
	var/mob/living/carbon/human/prey = pair[2]
	var/obj/belly/B = pred.vore_selected

	TEST_ASSERT_NULL(vore_consent_refusal(/datum/predicate/vore_devour, pred, prey), "a willing prey should be devourable")
	prey.devourable = FALSE
	TEST_ASSERT_EQUAL(vore_consent_refusal(/datum/predicate/vore_devour, pred, prey), "They aren't able to be devoured.", "devour refusal reason")
	TEST_ASSERT(!pred.begin_instant_nom(pred, prey, pred, B), "an unwilling prey must not be eaten")
	TEST_ASSERT(prey.loc != B, "an unwilling prey must stay out")
	prey.devourable = TRUE

	prey.digestable = FALSE
	TEST_ASSERT_EQUAL(vore_consent_refusal(/datum/predicate/vore_digest, pred, prey), "they don't allow digestion", "digest refusal reason")
	prey.absorbable = FALSE
	TEST_ASSERT_EQUAL(vore_consent_refusal(/datum/predicate/vore_absorb, pred, prey), "they don't allow absorption", "absorb refusal reason")
	prey.permit_healbelly = FALSE
	TEST_ASSERT_EQUAL(vore_consent_refusal(/datum/predicate/vore_heal, pred, prey), "they don't allow healing bellies", "heal refusal reason")
	prey.strip_pref = FALSE
	TEST_ASSERT_EQUAL(vore_consent_refusal(/datum/predicate/vore_strip, pred, prey), "they don't allow stripping", "strip refusal reason")

	// A refused mode holds: an indigestible prey takes no digestion damage.
	B.digest_mode = DM_DIGEST
	TEST_ASSERT(pred.begin_instant_nom(pred, prey, pred, B), "a devourable prey should be eaten")
	var/before = _vore_test_total_injury(prey)
	vore_test_cycles(B, 5)
	TEST_ASSERT_EQUAL(_vore_test_total_injury(prey), before, "an indigestible prey must not be digested")
	B.release_all_contents(TRUE, TRUE)

/// Same totals over the same time: 6 s cycles and 2 s (turbo) cycles give the same effect.
/datum/unit_test/dq_vore_mode_rates_scale_with_time

/datum/unit_test/dq_vore_mode_rates_scale_with_time/Run()
	// Drain: nutrition falls 5% per baseline cycle, compounded per second.
	var/list/slow = vore_test_pair()
	var/list/fast = vore_test_pair()
	var/obj/belly/BS = vore_rate_belly(slow, DM_DRAIN)
	var/obj/belly/BF = vore_rate_belly(fast, DM_DRAIN)
	var/mob/living/prey_s = slow[2]
	var/mob/living/prey_f = fast[2]
	prey_s.nutrition = 500
	prey_f.nutrition = 500
	vore_test_cycles(BS, 4, 6)
	vore_test_cycles(BF, 12, 2)
	TEST_ASSERT(abs(prey_s.nutrition - prey_f.nutrition) < 0.01, "drain totals differ: [prey_s.nutrition] over 4x6 s, [prey_f.nutrition] over 12x2 s")
	TEST_ASSERT(abs(prey_s.nutrition - 500 * (0.95 ** 4)) < 0.01, "drain should take 5% per 6 s: [prey_s.nutrition]")

	// Shrink: 1% of size per baseline cycle.
	slow = vore_test_pair()
	fast = vore_test_pair()
	BS = vore_rate_belly(slow, DM_SHRINK)
	BF = vore_rate_belly(fast, DM_SHRINK)
	BS.shrink_grow_size = 0.5
	BF.shrink_grow_size = 0.5
	prey_s = slow[2]
	prey_f = fast[2]
	vore_test_cycles(BS, 5, 6)
	vore_test_cycles(BF, 15, 2)
	TEST_ASSERT(abs(prey_s.size_multiplier - prey_f.size_multiplier) < 0.001, "shrink totals differ: [prey_s.size_multiplier] vs [prey_f.size_multiplier]")
	TEST_ASSERT(abs(prey_s.size_multiplier - 0.95) < 0.001, "shrink should take 1% per 6 s: [prey_s.size_multiplier]")

	// A late cycle catches up: one 12 s cycle drains as much as two 6 s ones.
	slow = vore_test_pair()
	fast = vore_test_pair()
	BS = vore_rate_belly(slow, DM_DRAIN)
	BF = vore_rate_belly(fast, DM_DRAIN)
	prey_s = slow[2]
	prey_f = fast[2]
	prey_s.nutrition = 400
	prey_f.nutrition = 400
	vore_test_cycles(BS, 1, 12)
	vore_test_cycles(BF, 2, 6)
	TEST_ASSERT(abs(prey_s.nutrition - prey_f.nutrition) < 0.01, "a late cycle should catch up: [prey_s.nutrition] vs [prey_f.nutrition]")

/// A belly on `pair`'s pred in `mode` with the prey inside.
/datum/unit_test/proc/vore_rate_belly(list/pair, mode)
	var/mob/living/pred = pair[1]
	var/mob/living/prey = pair[2]
	var/obj/belly/B = pred.vore_selected
	B.digest_mode = mode
	B.nom_atom(prey, pred)
	TEST_ASSERT_EQUAL(prey.loc, B, "prey should be inside for the rate test")
	return B

/// Digest to death, absorb and heal each reach their end state.
/datum/unit_test/dq_vore_mode_outcomes

/datum/unit_test/dq_vore_mode_outcomes/Run()
	// Digest to death.
	var/list/pair = vore_test_pair()
	var/obj/belly/B = vore_rate_belly(pair, DM_DIGEST)
	var/mob/living/carbon/human/prey = pair[2]
	B.digest_brute = 18
	B.digest_burn = 18
	for(var/i in 1 to 300)
		if(B.digested_prey_count)
			break
		if(!QDELETED(prey) && prey.loc == B)
			om_run_frame_now(prey, /datum/om/pipeline/life)
		B.belly_cycle(BELLY_BASELINE_TICK / (1 SECONDS))
	TEST_ASSERT_EQUAL(B.digested_prey_count, 1, "a digest belly should finish its prey (stat [prey?.stat])")

	// Absorb: a drained prey is absorbed.
	pair = vore_test_pair()
	B = vore_rate_belly(pair, DM_ABSORB)
	var/mob/living/carbon/human/absorbee = pair[2]
	absorbee.nutrition = 110
	vore_test_cycles(B, 10)
	TEST_ASSERT(absorbee.absorbed, "an absorb belly should absorb a drained prey (nutrition [absorbee.nutrition])")
	B.release_all_contents(TRUE, TRUE)
	TEST_ASSERT(!absorbee.absorbed, "release should unabsorb")

	// Heal: an injured prey mends.
	pair = vore_test_pair()
	var/mob/living/carbon/human/pred = pair[1]
	B = vore_rate_belly(pair, DM_HEAL)
	var/mob/living/carbon/human/patient = pair[2]
	pred.nutrition = 500
	patient.injure(INJURY_CORROSIVE, 20)
	var/hurt = _vore_test_total_injury(patient)
	vore_test_cycles(B, 5)
	TEST_ASSERT(_vore_test_total_injury(patient) < hurt, "a heal belly should mend its prey ([hurt] -> [_vore_test_total_injury(patient)])")

/// Customized bellies round-trip through the prefs serializer; uncustomized lists stay shared.
/datum/unit_test/dq_vore_customized_belly_round_trip

/datum/unit_test/dq_vore_customized_belly_round_trip/Run()
	var/mob/living/simple_mob/animal/passive/mouse/pred = allocate(/mob/living/simple_mob/animal/passive/mouse)
	var/obj/belly/belly = new(pred)
	belly.name = "Custom"
	belly.set_messages("You are held in a custom belly.\n\nThe custom belly squeezes you.", STRUGGLE_INSIDE, limit = MAX_MESSAGE_LEN)
	belly.set_messages("A custom idle emote, gently.", BELLY_MODE_HOLD, limit = MAX_MESSAGE_LEN)
	TEST_ASSERT_EQUAL(length(belly_default_lists()["emote_lists"]), 0, "customizing an emote must not touch the shared table")
	TEST_ASSERT(belly.struggle_messages_inside != belly_default_lists()["struggle_messages_inside"], "a customized list should be the belly's own")
	TEST_ASSERT_EQUAL(belly.struggle_messages_outside, belly_default_lists()["struggle_messages_outside"], "an untouched list should stay shared")

	var/list/errors = list()
	var/list/blob = state_serialize(belly, NONE, errors)
	TEST_ASSERT_NOTNULL(blob, "the belly should serialize: [jointext(errors, "; ")]")
	var/list/saved = blob[STATE_KEY_VARS]
	TEST_ASSERT("struggle_messages_inside" in saved, "a customized list should be saved")
	TEST_ASSERT(!("struggle_messages_outside" in saved), "a shared default list should not be saved")

	var/obj/belly/copy = state_materialize(json_decode(json_encode(blob)), pred, NONE, errors)
	TEST_ASSERT_NOTNULL(copy, "the belly should load: [jointext(errors, "; ")]")
	TEST_ASSERT_EQUAL(jointext(copy.struggle_messages_inside, "|"), "You are held in a custom belly.|The custom belly squeezes you.", "customized messages should round trip")
	TEST_ASSERT_EQUAL(jointext(copy.emote_lists[DM_HOLD], "|"), "A custom idle emote, gently.", "customized emotes should round trip")
	TEST_ASSERT_EQUAL(copy.struggle_messages_outside, belly_default_lists()["struggle_messages_outside"], "a default list should load shared")

	// An older save wrote every list out in full: equal ones go back to sharing.
	var/list/default_prey_messages = belly_default_lists()["digest_messages_prey"]
	var/list/old = list("type" = "/obj/belly", "name" = "Old", "digest_messages_prey" = default_prey_messages.Copy())
	var/obj/belly/old_belly = state_materialize(json_decode(json_encode(old)), pred, NONE, errors)
	TEST_ASSERT_NOTNULL(old_belly, "an old blob should load: [jointext(errors, "; ")]")
	TEST_ASSERT_EQUAL(old_belly.digest_messages_prey, belly_default_lists()["digest_messages_prey"], "a saved list equal to the default should be shared again")
	TEST_ASSERT_EQUAL(length(old_belly.belly_owned_lists()), 0, "a loaded default belly owns no lists")
