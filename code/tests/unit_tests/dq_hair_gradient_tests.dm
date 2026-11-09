// Hair gradients: the character setup saves a gradient's id ("fadeup"), the shapeshifter and DNA paths its display name ("Fade (Up)").

/// The hair image's picture as hair_look() builds it for H now.
/datum/unit_test/proc/dq_hair_gradient_look(mob/living/carbon/human/H)
	var/list/hair = H.hair_look(null)
	var/image/built = hair[1]
	if(!built)
		return null
	return md5(icon2base64(getFlatIcon(built, SOUTH)))

/datum/unit_test/dq_hair_gradient_draws

/datum/unit_test/dq_hair_gradient_draws/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.set_species(SPECIES_HUMAN)
	H.looks.set_hair_style(dq_profile_style(H, GLOB.hair_styles_list, "Short Hair"))
	H.looks.set_hair_color(rgb(200, 40, 90))
	H.looks.set_grad_color(rgb(10, 220, 30))
	var/list/looks = list()
	for(var/style in list("none", "fadeup", "fadedown", "vsplit", "Fade (Up)"))
		H.looks.set_grad_style(style)
		looks[style] = dq_hair_gradient_look(H)
	TEST_ASSERT(looks["none"], "the human has a hair image to compare")
	TEST_ASSERT(looks["fadeup"] != looks["none"], "a saved gradient id draws on the hair")
	TEST_ASSERT(looks["fadedown"] != looks["fadeup"], "two gradients draw differently")
	TEST_ASSERT(looks["vsplit"] != looks["fadeup"], "two gradients draw differently (vsplit)")
	TEST_ASSERT_EQUAL(looks["Fade (Up)"], looks["fadeup"], "the display name draws the same gradient as its id")
