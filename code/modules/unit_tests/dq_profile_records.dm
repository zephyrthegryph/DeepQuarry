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
	H.h_style = dq_profile_style(H, GLOB.hair_styles_list, "Bald")
	H.f_style = dq_profile_style(H, GLOB.facial_hair_styles_list, "Shaved")
	H.grad_style = GLOB.hair_gradients[min(2, length(GLOB.hair_gradients))]
	H.r_hair = 200
	H.g_hair = 40
	H.b_hair = 90
	H.r_grad = 10
	H.g_grad = 220
	H.b_grad = 30
	H.r_facial = 120
	H.g_facial = 130
	H.b_facial = 5
	H.r_eyes = 0
	H.g_eyes = 255
	H.b_eyes = 128
	H.r_skin = 90
	H.g_skin = 160
	H.b_skin = 70
	H.s_tone = tone
	H.set_lip_style("red")

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
	taj.digitigrade = 1
	got["tajaran_digi"] = dq_profile_look_hash(taj)

	var/mob/living/carbon/human/unathi = allocate(/mob/living/carbon/human, T)
	unathi.set_species(SPECIES_UNATHI)
	dq_profile_dress(unathi, 0)
	got["unathi"] = dq_profile_look_hash(unathi)

	// DNA carries the look: a body built from the human's UI looks the same.
	human.dna.ResetUIFrom(human)
	var/mob/living/carbon/human/clone = allocate(/mob/living/carbon/human, T)
	clone.set_species(SPECIES_HUMAN)
	clone.set_lip_style("red")
	clone.dna = human.dna.Clone()
	clone.UpdateAppearance()
	got["dna_copy"] = dq_profile_look_hash(clone)

	var/mob/living/carbon/human/copy = allocate(/mob/living/carbon/human, T)
	copy.set_species(SPECIES_HUMAN)
	copy.set_lip_style("red")
	copy.copy_colours_from(human)
	got["colour_copy"] = dq_profile_look_hash(copy)

	var/list/moved = list()
	for(var/name in expected)
		log_test("profile look pin [name] [got[name]]")
		if(got[name] != expected[name])
			moved += name
	TEST_ASSERT(!length(moved), "these looks differ from the ones recorded before the profile move: [jointext(moved, ", ")]")
	// the hash is of a real picture: two different looks hash differently
	TEST_ASSERT(got["human"] != got["unathi"], "a human and an unathi look different")
