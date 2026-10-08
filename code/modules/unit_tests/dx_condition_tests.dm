// held_condition() and /datum/capability/condition (code/datums/capabilities/condition.dm).

/datum/capability/condition/dx_jam
	layer_name = "dx_jam_layer"

/datum/capability/condition/dx_jam_soft
	blocks = list(/datum/capability/dx_test/a)
	layer_name = "dx_soft_layer"

/proc/dx_condition_entry(atom/A)
	for(var/datum/interaction/capability/E as anything in cap_interactions(A))
		return E
	return null

/datum/unit_test/om/dx_condition_timed_grant

/datum/unit_test/om/dx_condition_timed_grant/run_om(list/made)
	var/obj/cap_fixture/dx_core/F = new
	made += F
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	var/datum/src_a = new
	made += src_a
	refresh_flush()
	var/datum/interaction/capability/entry = dx_condition_entry(F)
	TEST_ASSERT(entry, "the fixture has an entry")
	TEST_ASSERT_NULL(cap_gate_reason(F, user, null, entry), "not gated before the grant")
	TEST_ASSERT(!findtext(F.look_key, "dx_jam_layer"), "no condition layer yet")

	TEST_ASSERT(grant(F, held_condition(/datum/capability/condition/dx_jam), src_a, 2 SECONDS), "granted")
	refresh_flush()
	TEST_ASSERT(cap_of_all(F, /datum/capability/condition/dx_jam), "the capability is attached")
	TEST_ASSERT_EQUAL(cap_gate_reason(F, user, null, entry), "it isn't responding", "entries refused with its else_say")
	TEST_ASSERT(findtext(F.look_key, "dx_jam_layer"), "draw layer present: [F.look_key]")

	scheduler_advance(1)
	TEST_ASSERT(cap_of_all(F, /datum/capability/condition/dx_jam), "still held before the end")
	scheduler_advance(1.5)
	refresh_flush()
	TEST_ASSERT(!cap_of_all(F, /datum/capability/condition/dx_jam), "detached on expiry")
	TEST_ASSERT_NULL(cap_gate_reason(F, user, null, entry), "entries work again")
	TEST_ASSERT(!findtext(F.look_key, "dx_jam_layer"), "redrawn without the layer: [F.look_key]")

/datum/unit_test/om/dx_condition_sources

/datum/unit_test/om/dx_condition_sources/run_om(list/made)
	var/obj/cap_fixture/dx_core/F = new
	made += F
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	var/datum/src_a = new
	var/datum/src_b = new
	made += src_a
	refresh_flush()
	var/datum/interaction/capability/entry = dx_condition_entry(F)
	grant(F, held_condition(/datum/capability/condition/dx_jam), src_a)
	grant(F, held_condition(/datum/capability/condition/dx_jam), src_b)
	TEST_ASSERT(cap_of_all(F, /datum/capability/condition/dx_jam), "held")
	revoke(F, held_condition(/datum/capability/condition/dx_jam), src_a)
	TEST_ASSERT(cap_of_all(F, /datum/capability/condition/dx_jam), "still held by the second source")
	TEST_ASSERT(cap_gate_reason(F, user, null, entry), "still refusing")
	qdel(src_b)
	scheduler_advance(0.1)
	TEST_ASSERT(!cap_of_all(F, /datum/capability/condition/dx_jam), "a deleted source's hold is dropped")
	TEST_ASSERT_NULL(cap_gate_reason(F, user, null, entry), "entries work again")

	var/obj/cap_fixture/dx_core/G = new
	made += G
	grant(F, held_condition(/datum/capability/condition/dx_jam), src_a)
	grant(G, held_condition(/datum/capability/condition/dx_jam), src_a)
	TEST_ASSERT(cap_of_all(F, /datum/capability/condition/dx_jam) == cap_of_all(G, /datum/capability/condition/dx_jam), "one shared instance per path")

/datum/unit_test/om/dx_condition_blocks

/datum/unit_test/om/dx_condition_blocks/run_om(list/made)
	var/obj/cap_fixture/dx_core/F = new
	made += F
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	var/datum/src_a = new
	made += src_a
	var/datum/interaction/capability/entry = dx_condition_entry(F)
	grant(F, held_condition(/datum/capability/condition/dx_jam_soft), src_a)
	TEST_ASSERT_NULL(cap_gate_reason(F, user, null, entry), "a condition that blocks other capabilities lets this entry through")
