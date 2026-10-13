/datum/preference/color/human/hair_color
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "hair_color"
	can_randomize = FALSE

/datum/preference/color/human/hair_color/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_hair_color(value)

/datum/preference/color/human/grad_color
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "grad_color"
	can_randomize = FALSE

/datum/preference/color/human/grad_color/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_grad_color(value)

/datum/preference/color/human/facial_color
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "facial_color"
	can_randomize = FALSE

/datum/preference/color/human/facial_color/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_facial_color(value)

/datum/preference/color/human/eyes_color
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "eyes_color"
	can_randomize = FALSE

/datum/preference/color/human/eyes_color/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_eyes_color(value)

/datum/preference/color/human/skin_color
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "skin_color"
	can_randomize = FALSE

/datum/preference/color/human/skin_color/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_skin_color(value)

/datum/preference/color/human/synth_color
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "synth_color_rgb"
	can_randomize = FALSE

/datum/preference/color/human/synth_color/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_synth_color_rgb(value)

/datum/preference/color/human/tail_color1
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "tail_color1"
	can_randomize = FALSE

/datum/preference/color/human/tail_color1/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_tail_color(value)

/datum/preference/color/human/tail_color2
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "tail_color2"
	can_randomize = FALSE

/datum/preference/color/human/tail_color2/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_tail_color2(value)

/datum/preference/color/human/tail_color3
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "tail_color3"
	can_randomize = FALSE

/datum/preference/color/human/tail_color3/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_tail_color3(value)

/datum/preference/numeric/human/tail_alpha
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "tail_alpha"
	can_randomize = FALSE
	minimum = 0
	maximum = 255

/datum/preference/numeric/human/tail_alpha/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_tail_alpha(value)

/datum/preference/numeric/human/tail_alpha/create_default_value()
	return 255 //nada.

/datum/preference/color/human/wing_color1
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "wing_color1"
	can_randomize = FALSE

/datum/preference/color/human/wing_color1/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_wing_color(value)

/datum/preference/color/human/wing_color2
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "wing_color2"
	can_randomize = FALSE

/datum/preference/color/human/wing_color2/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_wing_color2(value)

/datum/preference/color/human/wing_color3
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "wing_color3"
	can_randomize = FALSE

/datum/preference/color/human/wing_color3/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_wing_color3(value)

/datum/preference/numeric/human/wing_alpha
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "wing_alpha"
	can_randomize = FALSE
	minimum = 0
	maximum = 255 //while it'd be dumb to have fully transparent wings, I'm not your mom.

/datum/preference/numeric/human/wing_alpha/create_default_value()
	return 255 //no randomization here.

/datum/preference/numeric/human/wing_alpha/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_wing_alpha(value)


/datum/preference/color/human/ears_color1
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "ears_color1"
	can_randomize = FALSE

/datum/preference/color/human/ears_color1/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_ears_color(value)

/datum/preference/color/human/ears_color2
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "ears_color2"
	can_randomize = FALSE

/datum/preference/color/human/ears_color2/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_ears_color2(value)

/datum/preference/color/human/ears_color3
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "ears_color3"
	can_randomize = FALSE

/datum/preference/color/human/ears_color3/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_ears_color3(value)

/datum/preference/numeric/human/ears_alpha
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "ears_alpha"
	can_randomize = FALSE
	minimum = 0
	maximum = 255

/datum/preference/numeric/human/ears_alpha/secondary
	savefile_key = "secondary_ears_alpha"

/datum/preference/numeric/human/ears_alpha/secondary/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_ears_alpha2(value)

/datum/preference/numeric/human/ears_alpha/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_ears_alpha(value)

/datum/preference/numeric/human/ears_alpha/create_default_value()
	return 255 //no randomization here.

