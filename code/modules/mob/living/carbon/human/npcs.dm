/obj/item/clothing/under/punpun
	name = "fancy uniform"
	desc = "It looks like it was tailored for a monkey."
	icon_state = "punpun"
	worn_state = "punpun"
	has_sensor = 0

TYPE_TABLE(/obj/item/clothing/under/punpun, fit_spec, list(REQ_FITS_BODYTYPES(list("Monkey"))))

/mob/living/carbon/human/monkey/punpun

// The bartender's monkey: named Pun Pun (over the name its species gives it) and dressed in its uniform.
CAPABILITIES(/mob/living/carbon/human/monkey/punpun)
	profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("can_be_drop_prey" = TRUE))
	derives(nameof(name), PROC_REF(pun_pun))
	derives(nameof(real_name), PROC_REF(pun_pun))
	wears(/obj/item/clothing/under/punpun, SLOT_ID_UNIFORM)

/mob/living/carbon/human/monkey/punpun/proc/pun_pun(target)
	return "Pun Pun"
