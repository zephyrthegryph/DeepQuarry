/obj/item/clothing/under/teshari
	icon = 'icons/inventory/uniform/item_teshari.dmi'
	icon_state = "seromi_grey"


/obj/item/clothing/under/teshari/smock
	name = "small grey smock"
	desc = "It looks fitted to nonhuman proportions."
	icon_state = "seromi_grey"

/obj/item/clothing/under/teshari/smock/dress
	name = "small command dress"
	icon_state = "seromi_dress_cap"

// Worksuits
/obj/item/clothing/under/teshari/undercoat/standard/worksuit
	name = "small black and red worksuit"
	icon_state = "teshari_black_red_worksuit"
	desc = "A small worksuit designed for a Teshari"

//Standard Undercoats

/obj/item/clothing/under/teshari/undercoat
	name = "Undercoat"
	desc =  "A Teshari traditional garb, with a modern twist! Made of micro and nanofibres to make it light and billowy, perfect for going fast and stylishly!"
	icon_state = "tesh_uniform_bo"

CAPABILITIES(/obj/item/clothing/under/teshari/undercoat)
	configure(item_worn(covers = CHEST))

//Job Undercoats
/obj/item/clothing/under/teshari/undercoat/jobs/hos
	name = "head of security undercoat"
	desc = "A traditional Teshari garb made for the " + JOB_HEAD_OF_SECURITY + ". Made with slightly sturdier materials."
	icon_state = "tesh_uniform_hos"

CAPABILITIES(/obj/item/clothing/under/teshari/undercoat/jobs/hos)
	configure(atom_rules(armor_spec = "melee=10"))
	configure(item_worn(covers = UPPER_TORSO|LOWER_TORSO|LEGS|ARMS))
	configure(item_protection(siemens = 0.9))

/obj/item/clothing/under/teshari/undercoat/jobs/sec
	name = "security undercoat"
	desc = "A traditional Teshari garb made for the Security department. Made with slightly sturdier materials."
	icon_state = "tesh_uniform_sec"

CAPABILITIES(/obj/item/clothing/under/teshari/undercoat/jobs/sec)
	configure(atom_rules(armor_spec = "melee=10"))
	configure(item_worn(covers = UPPER_TORSO|LOWER_TORSO|LEGS|ARMS))
	configure(item_protection(siemens = 0.9))


CAPABILITIES(/obj/item/clothing/under/teshari)
	fits_as(FIT_TESHARI)
