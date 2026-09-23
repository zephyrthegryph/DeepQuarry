/obj/item/clothing/under/punpun
	name = "fancy uniform"
	desc = "It looks like it was tailored for a monkey."
	icon_state = "punpun"
	worn_state = "punpun"
	has_sensor = 0

/obj/item/clothing/under/punpun/fit_constraint()
	var/list/bodytypes = list("Monkey")
	return list(REQ_FITS_BODYTYPES(bodytypes))

/mob/living/carbon/human/monkey/punpun/Initialize(mapload)
	. = ..()
	name = "Pun Pun"
	real_name = name
	w_uniform = new /obj/item/clothing/under/punpun(src)
	regenerate_icons()
	can_be_drop_prey = TRUE
