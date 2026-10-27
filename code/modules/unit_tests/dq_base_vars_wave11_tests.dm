// base_vars wave 11: the weak sparse slot (sparse(T, name, type = weak): lastattacker, LAssailant, teleop, autofire_target), the rare numeric mob state that
// became slots (disabilities, losebreath, accumulated_rads) and the owned lists that became sparse links (side effects, glamour rings, map screens,
// the cozy loop, the rig and its wearer).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A weak slot names a datum without pinning it: it reads the datum while it lives and null once it is gone, and the holder itself is a fine value.
/datum/unit_test/dq_weak_sparse_slot

/datum/unit_test/dq_weak_sparse_slot/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/holder = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_NULL(sparse_ref(holder, teleop), "an unset weak slot reads null")
	TEST_ASSERT_EQUAL(sparse_ref_set(holder, teleop, other), other, "the setter answers the target")
	TEST_ASSERT_EQUAL(sparse_ref(holder, teleop), other, "the weak slot reads the live target")
	TEST_ASSERT_EQUAL(holder.teleop(), other, "the teleop view reads the slot")
	TEST_ASSERT(istext(holder.sparse_slots["teleop"]), "the slot holds a handle, not a reference")
	sparse_ref_set(holder, teleop, holder)
	TEST_ASSERT_EQUAL(sparse_ref(holder, teleop), holder, "a weak slot may name its own holder")
	sparse_ref_set(holder, teleop, other)
	qdel(other)
	TEST_ASSERT_NULL(sparse_ref(holder, teleop), "a deleted target reads as none")
	TEST_ASSERT(!sparse_has(holder, teleop), "the slot of a gone target is cleared as it is found")
	sparse_ref_set(holder, teleop, holder)
	sparse_ref_set(holder, teleop, null)
	TEST_ASSERT_NULL(holder.sparse_slots, "a null value clears the slot and the list goes with its last slot")
	TEST_ASSERT_NULL(sparse_ref_set(holder, teleop, "not a datum"), "a value that is not a datum is refused")
	var/turf/open_turf = get_turf(holder)
	sparse_ref_set(holder, autofire_target, open_turf)
	TEST_ASSERT_EQUAL(holder.autofire_target(), open_turf, "a turf is a fine weak target")

/// The weak slots are no longer vars, are listed by View Variables as slots and are edited through the slot writer.
/datum/unit_test/dq_weak_sparse_slot_vv

/datum/unit_test/dq_weak_sparse_slot_vv/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/holder = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	for(var/name in list("lastattacker", "LAssailant", "teleop", "autofire_target", "disabilities", "accumulated_rads"))
		TEST_ASSERT(!(name in holder.vars), "[name] is no longer a var of [holder.type]")
		TEST_ASSERT((sparse_slot_label(name) in sparse_slots_of(holder)), "[name] is listed as a slot of [holder.type]")
	var/label = sparse_slot_label("teleop")
	TEST_ASSERT(holder.vv_edit_var(label, other), "the VV edit of a weak slot is accepted")
	TEST_ASSERT_EQUAL(vv_var_value(holder, label), other, "View Variables reads the datum a weak slot names")
	TEST_ASSERT_EQUAL(holder.teleop(), other, "the edit went through the weak writer")
	TEST_ASSERT_EQUAL(sparse_slots_of(holder)[label], other, "the slot list shows the datum")

/// Who last hit a mob is remembered weakly, and the death record keeps the name of one who is gone.
/datum/unit_test/dq_weak_slot_attacker

/datum/unit_test/dq_weak_slot_attacker/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, T)
	attacker.set_real_name("Wave Attacker")
	victim.note_attacker(attacker)
	TEST_ASSERT_EQUAL(victim.lastattacker(), attacker, "the live attacker is read back")
	victim.note_assailant(attacker)
	TEST_ASSERT_EQUAL(victim.assailant(), attacker, "the live assailant is read back")
	qdel(attacker)
	TEST_ASSERT_NULL(victim.lastattacker(), "a deleted attacker reads as none")
	TEST_ASSERT_NULL(victim.assailant(), "a deleted assailant reads as none")
	TEST_ASSERT_EQUAL(victim.last_attacker_record()[1], "Wave Attacker", "the record keeps the attacker's name")

/// The numeric slots read 0 while unset, clear on a write of 0 and keep the bit operations of the disability field.
/datum/unit_test/dq_base_vars_wave11_numbers

/datum/unit_test/dq_base_vars_wave11_numbers/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_EQUAL(H.disabilities(), 0, "disabilities start at 0")
	TEST_ASSERT_EQUAL(H.losebreath(), 0, "losebreath starts at 0")
	TEST_ASSERT_EQUAL(H.accumulated_rads(), 0, "accumulated_rads starts at 0")
	H.add_disabilities(NEARSIGHTED)
	H.add_disabilities(CLUMSY)
	TEST_ASSERT_EQUAL(H.disabilities(), NEARSIGHTED | CLUMSY, "disability flags add up")
	H.remove_disabilities(NEARSIGHTED)
	TEST_ASSERT_EQUAL(H.disabilities(), CLUMSY, "a flag comes off alone")
	H.remove_disabilities(CLUMSY)
	TEST_ASSERT(!sparse_has(H, disabilities), "no flags left clears the slot")
	H.set_losebreath(5)
	TEST_ASSERT_EQUAL(H.losebreath(), 5, "losebreath reads what was set")
	H.set_losebreath(0)
	TEST_ASSERT(!("losebreath" in H.vars), "losebreath is not a var of the mob")
	TEST_ASSERT(!sparse_has(H, losebreath), "losebreath is not a slot: it lives on the physiology")
	H.decay_radiation(0, 30)
	TEST_ASSERT_EQUAL(H.accumulated_rads(), 30, "decay settles into the accumulated dose")
	H.clear_radiation()
	TEST_ASSERT(!sparse_has(H, accumulated_rads), "clearing radiation clears the accumulated dose slot")

/// Medication and genetic side effects, map screens and the cozy loop are sparse links that go with their owner.
/datum/unit_test/dq_base_vars_wave11_owned_links

/datum/unit_test/dq_base_vars_wave11_owned_links/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/medical_effect/headache/effect = new
	TEST_ASSERT(link_make(H, LK_SIDE_EFFECTS, effect), "a medical effect links to its human")
	TEST_ASSERT_EQUAL(link_count(H, LK_SIDE_EFFECTS), 1, "the human counts it")
	TEST_ASSERT_EQUAL(H.side_effects()[1], effect, "the human lists it")
	var/datum/genetics/side_effect/genetic_burn/gene = new
	gene.start(H)
	TEST_ASSERT_EQUAL(H.genetic_side_effects()[1], gene, "a genetic side effect starts onto its human")
	TEST_ASSERT_EQUAL(gene.host(), H, "and names its host")
	var/atom/movable/screen/shown = new
	TEST_ASSERT(link_make(H, LK_MAPOBJS, shown), "a map screen links to its mob")
	TEST_ASSERT_EQUAL(H.mapobjs()[1], shown, "the mob lists the screen")
	H.clearmap()
	TEST_ASSERT(QDELETED(shown), "clearing the map disposes of its screens")
	TEST_ASSERT_EQUAL(link_count(H, LK_MAPOBJS), 0, "and the mob lists none")
	TEST_ASSERT_NULL(H.cozy_loop(), "no cozy loop exists until the music first starts")
	H.cozy_music(TRUE)
	var/datum/looping_sound/mob/cozyloop/loop = H.cozy_loop()
	TEST_ASSERT(loop && loop.running, "starting the music makes and starts the loop")
	H.cozy_music(FALSE)
	TEST_ASSERT(!loop.running, "stopping the music stops it")
	TEST_ASSERT_EQUAL(H.cozy_loop(), loop, "the loop is kept for the next time")
	qdel(effect)
	TEST_ASSERT_EQUAL(link_count(H, LK_SIDE_EFFECTS), 0, "a deleted effect leaves its human")
	qdel(H)
	TEST_ASSERT(QDELETED(gene), "a genetic side effect goes with its human")
	TEST_ASSERT(QDELETED(loop), "the cozy loop goes with its carbon")

/// A medical effect goes with its human.
/datum/unit_test/dq_base_vars_wave11_effect_goes_with_human

/datum/unit_test/dq_base_vars_wave11_effect_goes_with_human/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/medical_effect/headache/effect = new
	link_make(H, LK_SIDE_EFFECTS, effect)
	qdel(H)
	TEST_ASSERT(QDELETED(effect), "the effect is disposed of with its human")

/// The rig and the human wearing it are two ends of one link: one write sets both, and either going clears the other.
/datum/unit_test/dq_base_vars_wave11_rig_wearer

/datum/unit_test/dq_base_vars_wave11_rig_wearer/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/rig/suit = allocate(/obj/item/rig, T)
	TEST_ASSERT_NULL(H.wearing_rig(), "nobody wears a rig at first")
	TEST_ASSERT(link_make(H, LK_WEARING_RIG, suit), "the human takes the rig")
	TEST_ASSERT_EQUAL(H.wearing_rig(), suit, "the human reads its rig")
	TEST_ASSERT_EQUAL(suit.wearer(), H, "the rig reads its wearer")
	link_break(suit, LK_RIG_WEARER)
	TEST_ASSERT_NULL(H.wearing_rig(), "taking the rig off clears the human's end")
	link_make(H, LK_WEARING_RIG, suit)
	qdel(suit)
	TEST_ASSERT_NULL(H.wearing_rig(), "a deleted rig leaves its human")

/// A lleill's rings are links: the owner counts them in order, a ring broken leaves the list, and the rings go with the owner.
/datum/unit_test/dq_base_vars_wave11_glamour_rings

/datum/unit_test/dq_base_vars_wave11_glamour_rings/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/structure/glamour_ring/first = new(T)
	var/obj/structure/glamour_ring/second = new(T)
	link_make(H, LK_GLAMOUR_RINGS, first)
	link_make(H, LK_GLAMOUR_RINGS, second)
	TEST_ASSERT_EQUAL(link_count(H, LK_GLAMOUR_RINGS), 2, "both rings are counted")
	TEST_ASSERT_EQUAL(H.glamour_rings()[2], second, "the rings keep the order they were placed in")
	TEST_ASSERT(link_has(H, LK_GLAMOUR_RINGS, first), "a ring is found among them")
	qdel(first)
	TEST_ASSERT_EQUAL(link_count(H, LK_GLAMOUR_RINGS), 1, "a deleted ring leaves the owner")
	qdel(H)
	TEST_ASSERT(QDELETED(second), "a ring goes with its owner")

#endif
