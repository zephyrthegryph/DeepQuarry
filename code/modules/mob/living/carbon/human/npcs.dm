/obj/item/clothing/under/punpun
	name = "fancy uniform"
	desc = "It looks like it was tailored for a monkey."
	icon_state = "punpun"
	worn_state = "punpun"
	has_sensor = 0

TYPE_TABLE(/obj/item/clothing/under/punpun, fit_spec, list(REQ_FITS_BODYTYPES(list("Monkey"))))

/mob/living/carbon/human/monkey/punpun/Initialize(mapload)
	. = ..()
	name = "Pun Pun"
	real_name = name
	equip_to_slot_or_del(new /obj/item/clothing/under/punpun(src), SLOT_ID_UNIFORM)
	regenerate_icons()
	can_be_drop_prey = TRUE
