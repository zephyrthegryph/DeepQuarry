// A late joiner gets the job's outfit and is drawn wearing it (playtest 2026-11-08: a Visitor joined with "nothing").

/// Equipping a joiner's outfit dresses the human, and the look on screen is the one its draw gives now.
/datum/unit_test/dq_join_outfit_drawn/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.mind_initialize()
	refresh_flush()
	var/naked_key = H.rx?.look_key
	SSjob.equip_rank(H, JOB_ALT_VISITOR, TRUE, FALSE)
	refresh_flush()
	TEST_ASSERT(H.get_equipped_item(SLOT_ID_UNIFORM), "the joiner wears a uniform")
	TEST_ASSERT(H.get_equipped_item(SLOT_ID_SHOES), "and shoes")
	TEST_ASSERT(H.get_equipped_item(SLOT_ID_ID), "and carries an ID")
	TEST_ASSERT(H.look_layers()[UNIFORM_LAYER], "the draw puts the uniform on its layer")
	TEST_ASSERT(H.rx?.look_key != naked_key, "the applied look changed when the outfit went on")
	TEST_ASSERT_EQUAL(H.rx?.look_key, refresh_look(H, FALSE), "the applied look is the one the draw gives now (nothing was left undrawn)")

/// The same join with nobody looking where the joiner is made: the draw queue draws the joiner and everything it wears all the same.
/datum/unit_test/dq_join_outfit_drawn_unseen/Run()
	draw_isolate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.mind_initialize()
	SSjob.equip_rank(H, JOB_ALT_VISITOR, TRUE, FALSE)
	refresh_flush()
	var/obj/item/uniform = H.get_equipped_item(SLOT_ID_UNIFORM)
	TEST_ASSERT(uniform, "the joiner wears a uniform")
	TEST_ASSERT(!H.refresh_queued, "the joiner owes no draw after the drain")
	for(var/obj/item/worn in H.get_equipped_items())
		TEST_ASSERT(!worn.refresh_queued, "[worn] owes no draw after the drain")
	TEST_ASSERT(H.look_layers()[UNIFORM_LAYER], "the draw puts the uniform on its layer")
	TEST_ASSERT_EQUAL(H.rx?.look_key, refresh_look(H, FALSE), "the joiner on screen is the one its draw gives now")

/// Every job a player can take has an outfit: a job whose outfit_type is lost (a codemod once moved the Assistant's into a proc body, so every Visitor
/// and Assistant spawned naked) equips nothing and says nothing.
/datum/unit_test/dq_join_every_job_has_an_outfit/Run()
	for(var/rank in job_occupations_by_name())
		var/datum/job/J = SSjob.get_job(rank)
		if(!J || (J.mob_type & JOB_SILICON))
			continue
		TEST_ASSERT(J.get_outfit(null, null), "[rank] ([J.type]) has an outfit")

/// What `ref` (a type or a VARIANT() reference) names, or null when it makes nothing: the stale path a join once tripped over.
/datum/unit_test/proc/dq_made_path(ref)
	var/path = saved_type_path(ref)
	if(!ispath(path))
		return null
	if(istext(ref) && !dq_variant_vars(path, variant_key(ref)))
		return null
	return path

/// Every slot, hand, accessory and pack entry of every outfit, and every loadout gear entry, names a thing that can be made: a collapsed family's
/// old path left as a bare `new` once ended a join with "Cannot create objects of type null", and the joiner got nothing.
/datum/unit_test/dq_every_outfit_and_gear_path_resolves/Run()
	var/static/list/slots = list("uniform", "suit", "back", "belt", "gloves", "shoes", "head", "mask", "l_ear", "r_ear", "glasses", "id", "l_pocket", "r_pocket", "suit_store", "r_hand", "l_hand", "id_type", "pda_type", "headset", "headset_alt", "headset_earbud", "backpack", "satchel_one", "satchel_two", "messenger_bag", "sports_bag", "satchel_three")
	for(var/datum/decl/hierarchy/outfit/outfit as anything in GLOB.outfits_decls)
		for(var/slot in slots)
			var/ref = outfit.vars[slot]
			if(isnull(ref))
				continue
			TEST_ASSERT(dq_made_path(ref), "outfit [outfit.type] ([outfit.name]) [slot] names [ref], which makes nothing")
		for(var/list_name in list("uniform_accessories", "backpack_contents"))
			var/list/refs = outfit.vars[list_name]
			for(var/ref in refs)
				TEST_ASSERT(dq_made_path(ref), "outfit [outfit.type] ([outfit.name]) [list_name] names [ref], which makes nothing")
	for(var/gear_name in GLOB.gear_datums)
		var/datum/gear/G = GLOB.gear_datums[gear_name]
		TEST_ASSERT(dq_made_path(G.path), "loadout gear [G.type] ([gear_name]) names [G.path], which makes nothing")

/// Dressing a joiner in every job's outfit completes: each outfit's worn items are made, and one that cannot be made is skipped, not fatal.
/datum/unit_test/dq_every_job_outfit_equips/Run()
	var/list/done = list()
	for(var/rank in job_occupations_by_name())
		var/datum/job/J = SSjob.get_job(rank)
		if(!J || (J.mob_type & JOB_SILICON))
			continue
		var/datum/decl/hierarchy/outfit/outfit = J.get_outfit(null, null)
		if(!outfit || (outfit.type in done))
			continue
		done += outfit.type
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
		H.mind_initialize()
		TEST_ASSERT(outfit.equip(H, J.title, null), "[rank] outfit [outfit.type] equips")
		for(var/obj/item/dropped in contents_of(get_turf(H)))
			qdel(dropped) // survival gear the outfit could not place lands on the floor

/// A bad entry in an outfit is skipped (and logged) with the rest of the outfit still worn.
/datum/unit_test/dq_outfit_skips_a_bad_entry/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/job/J = SSjob.get_job(JOB_ALT_VISITOR)
	var/datum/decl/hierarchy/outfit/outfit = J.get_outfit(null, null)
	var/real_uniform = outfit.uniform
	outfit.uniform = "/obj/item/clothing/under/dq_no_such_family/no_such_row"
	outfit.equip_base(H)
	outfit.uniform = real_uniform
	TEST_ASSERT(!H.get_equipped_item(SLOT_ID_UNIFORM), "the unmakeable uniform is skipped")
	TEST_ASSERT(H.get_equipped_item(SLOT_ID_SHOES), "the shoes still go on")
