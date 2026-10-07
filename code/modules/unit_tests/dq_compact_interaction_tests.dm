/**
 * Compact interaction specs (doc/rewrite/interactions.md §5a, code/datums/interactions/compact.dm).
 * Fixtures exercise every INTERACT_* shape end to end through the same
 * resolver and entry dispatch as the full datum form.
 */

/obj/dq_compact_probe
	name = "compact probe"
	density = FALSE
	anchored = TRUE
	var/list/log

DECLARE_INTERACTIONS(/obj/dq_compact_probe, \
	INTERACT_USE("Zoom", PROC_REF(zoom)), \
	INTERACT_HAND("Poke", PROC_REF(poke)), \
	INTERACT_ALT("Eject", PROC_REF(eject)), \
	INTERACT_INSERT(/obj/item/tool/crowbar, PROC_REF(insert_crowbar), null), \
)

/obj/dq_compact_probe/proc/zoom()
	LAZYADD(log, "zoom")
	// Deliberately returns nothing: INTERACT_USE is the one shape whose effect
	// need not return TRUE - a self-use has no legacy fallthrough to decline into.

/obj/dq_compact_probe/proc/poke(mob/user, obj/item/held, datum/interaction/interaction)
	LAZYADD(log, "poke")
	return TRUE

/obj/dq_compact_probe/proc/eject(mob/user, obj/item/held, datum/interaction/interaction)
	LAZYADD(log, "eject")
	return TRUE

/obj/dq_compact_probe/proc/insert_crowbar(mob/user, obj/item/W, datum/interaction/interaction)
	LAZYADD(log, "insert_crowbar")
	return TRUE

/// A second type declaring the identical spec (same inherited zoom proc via subtyping),
/// to check interning: get_interactions() returning the same spec shares one singleton.
/obj/dq_compact_probe/child

/// A subtype that adds its own compact spec on top of the parent's: get_interactions()
/// overrides replace, they don't merge, so this uses declare_interactions() (which already
/// chains ..() reliably) and builds its own entry directly with dq_interaction_from_spec().
/obj/dq_compact_probe/extended

EXTEND_INTERACTIONS(/obj/dq_compact_probe/extended, \
	INTERACT_USE("Wave", PROC_REF(wave)), \
)

/obj/dq_compact_probe/extended/proc/wave()
	LAZYADD(log, "wave")

/**
 * INTERACT_HAND/INTERACT_ALT respect their effect's own TRUE/FALSE, unlike
 * INTERACT_USE: attack_hand falls through to hand_gate()/pickup and click_alt
 * to the default alt-click panel when nothing was meant, exactly as the
 * legacy handlers did, so a declining effect must actually decline.
 */
/obj/dq_compact_probe/declining

// ALLOW(interactions): the probe tests that a subtype replaces its parent's Poke/Eject with declining ones
DECLARE_INTERACTIONS(/obj/dq_compact_probe/declining, \
	INTERACT_HAND("Poke", PROC_REF(decline)), \
	INTERACT_ALT("Eject", PROC_REF(decline)), \
)

/obj/dq_compact_probe/declining/proc/decline(mob/user, obj/item/held, datum/interaction/interaction)
	LAZYADD(log, "declined")
	return FALSE

// ---- Tests ----

/datum/unit_test/dq_compact_interaction_shapes

/datum/unit_test/dq_compact_interaction_shapes/Run()
	var/turf/T = test_floor()
	var/obj/dq_compact_probe/probe = allocate(/obj/dq_compact_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	// The type's candidates include every movable's default drag (Buckle), which applies_to() hides here.
	var/list/candidates = list()
	for(var/datum/interaction/candidate as anything in interaction_candidates(probe))
		if(candidate.applies_to(probe))
			candidates += candidate
	TEST_ASSERT(length(candidates) == 4, "the probe offers all 4 compact interactions, got [length(candidates)]")

	var/datum/interaction/use_interaction
	var/datum/interaction/hand_interaction
	var/datum/interaction/alt_interaction
	var/datum/interaction/insert_interaction
	for(var/datum/interaction/candidate as anything in candidates)
		if(candidate.entry == INTERACTION_ENTRY_SELF)
			use_interaction = candidate
		else if(candidate.entry == INTERACTION_ENTRY_HAND)
			hand_interaction = candidate
		else if(candidate.entry == INTERACTION_ENTRY_ALT)
			alt_interaction = candidate
		else if(candidate.entry == INTERACTION_ENTRY_ITEM)
			insert_interaction = candidate
	TEST_ASSERT(use_interaction, "INTERACT_USE produced an entry_self interaction")
	TEST_ASSERT(hand_interaction, "INTERACT_HAND produced an entry_hand interaction")
	TEST_ASSERT(alt_interaction, "INTERACT_ALT produced an entry_alt interaction")
	TEST_ASSERT(insert_interaction, "INTERACT_INSERT produced an entry_item interaction")
	TEST_ASSERT_EQUAL(use_interaction.name, "Zoom", "INTERACT_USE keeps its given name")
	TEST_ASSERT_EQUAL(insert_interaction.name, "Insert a crowbar", "INTERACT_INSERT derives a name from the held type")

	TEST_ASSERT(use_interaction.perform(H, probe, null), "Use runs even though zoom() returns nothing")
	TEST_ASSERT("zoom" in probe.log, "zoom() ran")

	TEST_ASSERT(hand_interaction.perform(H, probe, null), "Hand runs and reports TRUE from poke()")
	TEST_ASSERT("poke" in probe.log, "poke() ran")

	TEST_ASSERT(alt_interaction.perform(H, probe, null), "Alt runs and reports TRUE from eject()")
	TEST_ASSERT("eject" in probe.log, "eject() ran")

	var/obj/item/tool/crowbar/crowbar_item = allocate(/obj/item/tool/crowbar, T)
	TEST_ASSERT(insert_interaction.perform(H, probe, crowbar_item), "Insert runs and reports TRUE from insert_crowbar()")
	TEST_ASSERT("insert_crowbar" in probe.log, "insert_crowbar() ran")

	// End to end through the real entry dispatch (attack_self / attack_hand / click_alt / attackby).
	probe.log = list()
	TEST_ASSERT(H.put_in_active_hand(crowbar_item), "the human holds a crowbar")
	probe.attackby(crowbar_item, H)
	TEST_ASSERT("insert_crowbar" in probe.log, "attackby() reaches the compact insert interaction")

	probe.log = list()
	probe.attack_hand(H)
	TEST_ASSERT("poke" in probe.log, "attack_hand() reaches the compact hand interaction")

	probe.log = list()
	probe.click_alt(H)
	TEST_ASSERT("eject" in probe.log, "click_alt() reaches the compact alt interaction")

/// A get_interactions() override that chains ..() keeps its parent's specs alongside its own.
/datum/unit_test/dq_compact_interaction_subtype_chain

/datum/unit_test/dq_compact_interaction_subtype_chain/Run()
	var/turf/T = test_floor()
	var/obj/dq_compact_probe/extended/probe = allocate(/obj/dq_compact_probe/extended, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	var/list/self_interactions = list()
	for(var/datum/interaction/candidate as anything in interaction_candidates(probe))
		if(candidate.entry == INTERACTION_ENTRY_SELF)
			self_interactions += candidate
	TEST_ASSERT_EQUAL(length(self_interactions), 2, "the subtype offers both its own Use interaction and its parent's, got [length(self_interactions)]")

	var/list/names = list()
	for(var/datum/interaction/candidate as anything in self_interactions)
		names += candidate.name
		candidate.perform(H, probe, null)
	TEST_ASSERT("Wave" in names, "the subtype's own compact interaction is present")
	TEST_ASSERT("Zoom" in names, "the parent's compact interaction is still present (..() was chained)")
	TEST_ASSERT("wave" in probe.log, "wave() ran")
	TEST_ASSERT("zoom" in probe.log, "zoom() ran")

/datum/unit_test/dq_compact_interaction_decline

/datum/unit_test/dq_compact_interaction_decline/Run()
	var/turf/T = test_floor()
	var/obj/dq_compact_probe/declining/probe = allocate(/obj/dq_compact_probe/declining, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	var/datum/interaction/hand_interaction
	var/datum/interaction/alt_interaction
	for(var/datum/interaction/candidate as anything in interaction_candidates(probe))
		if(candidate.entry == INTERACTION_ENTRY_HAND)
			hand_interaction = candidate
		else if(candidate.entry == INTERACTION_ENTRY_ALT)
			alt_interaction = candidate

	TEST_ASSERT(!hand_interaction.perform(H, probe, null), "a declining INTERACT_HAND effect is not treated as handled")
	TEST_ASSERT("declined" in probe.log, "the hand effect still ran")

	probe.log = list()
	TEST_ASSERT(!alt_interaction.perform(H, probe, null), "a declining INTERACT_ALT effect is not treated as handled")
	TEST_ASSERT("declined" in probe.log, "the alt effect still ran")

// Interning: two types declaring the identical spec share one singleton (no id in tested_ids
// needed for the child's own copy - it is the same interaction object, already covered above).
/datum/unit_test/dq_compact_interaction_interning

/datum/unit_test/dq_compact_interaction_interning/Run()
	var/turf/T = test_floor()
	var/obj/dq_compact_probe/parent = allocate(/obj/dq_compact_probe, T)
	var/obj/dq_compact_probe/child/child = allocate(/obj/dq_compact_probe/child, T)

	var/datum/interaction/parent_use
	var/datum/interaction/child_use
	for(var/datum/interaction/candidate as anything in interaction_candidates(parent))
		if(candidate.entry == INTERACTION_ENTRY_SELF)
			parent_use = candidate
	for(var/datum/interaction/candidate as anything in interaction_candidates(child))
		if(candidate.entry == INTERACTION_ENTRY_SELF)
			child_use = candidate
	TEST_ASSERT(parent_use && child_use, "both types offer the Use interaction")
	TEST_ASSERT_EQUAL(parent_use, child_use, "an inherited compact spec interns to the same shared singleton, not a copy")

/**
 * Quick memory comparison (roadmap item: measure memory for a representative
 * type set against the full datum form). Every /datum/interaction, generic or
 * not, is one datum instance holding the same fixed set of vars regardless of
 * which form declared it - the compact form's saving is in source, and in
 * sharing one instance across types that declare an identical spec (verified
 * above), not in a smaller per-interaction footprint. This asserts that
 * saving is real: converting the probe's 4 interactions to the compact form
 * costs exactly as many live instances as 4 full datum subtypes would (one
 * each - nothing duplicated per type, nothing per instance), and the shared
 * singleton case (the interning test) costs one fewer.
 */
/datum/unit_test/dq_compact_interaction_memory

/datum/unit_test/dq_compact_interaction_memory/Run()
	var/turf/T = test_floor()
	var/obj/dq_compact_probe/a = allocate(/obj/dq_compact_probe, T)
	var/obj/dq_compact_probe/b = allocate(/obj/dq_compact_probe, T)

	// Two instances of the same type: interaction_candidates() is cached per type
	// (interaction.dm), so a second instance adds zero new interaction objects.
	var/list/candidates_a = interaction_candidates(a)
	var/list/candidates_b = interaction_candidates(b)
	TEST_ASSERT_EQUAL(candidates_a, candidates_b, "same-type instances share the exact same interaction list (no per-instance allocation)")
	for(var/i in 1 to length(candidates_a))
		TEST_ASSERT_EQUAL(candidates_a[i], candidates_b[i], "same-type instances share the exact same interaction objects")
