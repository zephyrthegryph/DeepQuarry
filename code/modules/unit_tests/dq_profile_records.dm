// Profile records (doc/rewrite/proposals/base_vars.md, "profile records"): a human's look is pinned across the move of its
// appearance vars into /datum/record/appearance. The fingerprints below were recorded on the tree before the move
// (r_/g_/b_ triples on the human); the move must not change one pixel.

/// The flat south icon of H, hashed.
/datum/unit_test/proc/dq_profile_look_hash(mob/living/carbon/human/H)
	H.force_update_limbs()
	H.regenerate_icons()
	H.update_hair()
	H.update_eyes()
	H.update_skin()
	H.update_icons_body()
	return md5(icon2base64(getFlatIcon(H, SOUTH)))

/// The first style of `styles` the species of H may wear (deterministic: list order).
/datum/unit_test/proc/dq_profile_style(mob/living/carbon/human/H, list/styles, skip)
	for(var/name in styles)
		if(name == skip)
			continue
		var/datum/sprite_accessory/S = styles[name]
		if(S?.species_allowed && (H.species.get_bodytype(H) in S.species_allowed))
			return name
	return null

/// Dresses H in a fixed, non-default appearance: every colour channel, both styles, a gradient, skin tone, lips.
/datum/unit_test/proc/dq_profile_dress(mob/living/carbon/human/H, tone)
	H.looks.set_hair_style(dq_profile_style(H, GLOB.hair_styles_list, "Bald"))
	H.looks.set_facial_style(dq_profile_style(H, GLOB.facial_hair_styles_list, "Shaved"))
	H.looks.set_grad_style(GLOB.hair_gradients[min(2, length(GLOB.hair_gradients))])
	H.looks.set_hair_color(rgb(200, 40, 90))
	H.looks.set_grad_color(rgb(10, 220, 30))
	H.looks.set_facial_color(rgb(120, 130, 5))
	H.looks.set_eyes_color(rgb(0, 255, 128))
	H.looks.set_skin_color(rgb(90, 160, 70))
	H.looks.set_skin_tone(tone)
	H.looks.set_lip_style("red")

/datum/unit_test/dq_profile_human_look_pin

/datum/unit_test/dq_profile_human_look_pin/Run()
	var/turf/T = test_floor()
	var/list/expected = list(
		"human" = "cee3e25b268799fb815295de91e9dd7d",
		"tajaran_digi" = "8de95bb39e3086bb798fb7be1ebba51d",
		"unathi" = "3d084dccad71ff48a8e1813883f70bf2",
		"dna_copy" = "cee3e25b268799fb815295de91e9dd7d",
		"colour_copy" = "cee3e25b268799fb815295de91e9dd7d",
	)
	var/list/got = list()

	var/mob/living/carbon/human/human = allocate(/mob/living/carbon/human, T)
	human.set_species(SPECIES_HUMAN)
	dq_profile_dress(human, -40)
	got["human"] = dq_profile_look_hash(human)

	var/mob/living/carbon/human/taj = allocate(/mob/living/carbon/human, T)
	taj.set_species(SPECIES_TAJARAN)
	dq_profile_dress(taj, 0)
	taj.looks.set_digitigrade(1)
	got["tajaran_digi"] = dq_profile_look_hash(taj)

	var/mob/living/carbon/human/unathi = allocate(/mob/living/carbon/human, T)
	unathi.set_species(SPECIES_UNATHI)
	dq_profile_dress(unathi, 0)
	got["unathi"] = dq_profile_look_hash(unathi)

	// DNA carries the look: a body built from the human's UI looks the same.
	human.dna.ResetUIFrom(human)
	var/mob/living/carbon/human/clone = allocate(/mob/living/carbon/human, T)
	clone.set_species(SPECIES_HUMAN)
	clone.looks.set_lip_style("red")
	clone.dna = human.dna.Clone()
	clone.UpdateAppearance()
	got["dna_copy"] = dq_profile_look_hash(clone)

	var/mob/living/carbon/human/copy = allocate(/mob/living/carbon/human, T)
	copy.set_species(SPECIES_HUMAN)
	copy.looks.set_lip_style("red")
	record_copy(copy.looks, human.looks)
	got["colour_copy"] = dq_profile_look_hash(copy)

	var/list/moved = list()
	for(var/name in expected)
		log_test("profile look pin [name] [got[name]]")
		if(got[name] != expected[name])
			moved += name
	TEST_ASSERT(!length(moved), "these looks differ from the ones recorded before the profile move: [jointext(moved, ", ")]")
	// the hash is of a real picture: two different looks hash differently
	TEST_ASSERT(got["human"] != got["unathi"], "a human and an unathi look different")

/// A human is made with its looks record: owned, edited through VV by its setters, shown in place, copied whole, gone with it.
/datum/unit_test/dq_profile_record_basics

/datum/unit_test/dq_profile_record_basics/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/record/appearance/looks = H.looks
	TEST_ASSERT(istype(looks), "a human is made with its looks record")
	TEST_ASSERT_EQUAL(owner_of(looks), H, "the human owns it")
	TEST_ASSERT_EQUAL(looks.skin_color, "#eeceb3", "the record starts with the human skin colour the old vars had")

	looks.vv_edit_var("hair_color", "#123456")
	TEST_ASSERT_EQUAL(looks.hair_color, "#123456", "an admin edit of a field goes through its setter")
	TEST_ASSERT(findtext(debug_variable("looks", looks, 0, H), "hair_color"), "VV shows the record's fields under the mob")

	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	record_copy(other.looks, looks)
	TEST_ASSERT(record_equal(other.looks, looks), "a copy holds every field: [jointext(record_diff(other.looks, looks), ", ")]")
	TEST_ASSERT(other.looks != looks, "and is its own record")

	qdel(H)
	TEST_ASSERT(QDELETED(looks), "the record goes with its holder")
