//Captain's Spacesuit
/obj/item/clothing/head/helmet/space/capspace
	name = "space helmet"
	icon_state = "capspace"
	desc = "A special helmet designed for work in a hazardous, low-pressure environment. Only for the most fashionable of military figureheads."
	armor_spec = "melee=65;bullet=50;laser=50;energy=25;bomb=50;bio=100;rad=50;cold=60"

CAPABILITIES(/obj/item/clothing/head/helmet/space/capspace)
	configure(item_worn(flags = 0, hides = HIDEFACE|BLOCKHAIR))
	configure(item_protection(permeability = 0.01))

//Captain's space suit This is not the proper path but I don't currently know enough about how this all works to mess with it.
/obj/item/clothing/suit/armor/captain
	name = JOB_SITE_MANAGER + "'s armor"
	desc = "A bulky, heavy-duty piece of exclusive corporate armor. YOU are in charge!"
	icon_state = "caparmor"
	w_class = ITEMSIZE_HUGE
	slowdown = 1.5
	armor_spec = "melee=65;bullet=50;laser=50;energy=25;bomb=50;bio=100;rad=50"

CAPABILITIES(/obj/item/clothing/suit/armor/captain)
	configure(item_worn(flags = 0, covers = CHEST|LEGS|FEET|ARMS|HANDS, hides = HIDEGLOVES|HIDESHOES|HIDEJUMPSUIT|HIDETAIL))
	configure(item_protection(gas_transfer = 0.01, permeability = 0.02, min_pressure = 0, max_pressure = 2 * ONE_ATMOSPHERE, cold_parts = UPPER_TORSO | LOWER_TORSO | LEGS | FEET | ARMS | HANDS, min_cold = SPACE_SUIT_MIN_COLD_PROTECTION_TEMPERATURE, siemens = 0.7))

//Deathsquad suit

TYPE_TABLE(/obj/item/clothing/suit/armor/captain, suit_storage_spec, list(HOLD_ONLY(list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SECURITY))))
/obj/item/clothing/head/helmet/space/deathsquad
	name = "deathsquad helmet"
	desc = "That's not red paint. That's real blood."
	icon_state = "deathsquad"
	item_state_slots = list(slot_r_hand_str = "syndicate-helm-black-red", slot_l_hand_str = "syndicate-helm-black-red")
	armor_spec = "melee=65;bullet=55;laser=35;energy=20;bomb=30;bio=100;rad=60;cold=60"

CAPABILITIES(/obj/item/clothing/head/helmet/space/deathsquad)
	configure(item_worn(flags = THICKMATERIAL, hides = BLOCKHAIR))
	configure(item_protection(siemens = 0.6))

//how is this a space helmet?
/obj/item/clothing/head/helmet/space/deathsquad/beret
	name = "officer's beret"
	desc = "An armored beret commonly used by special operations officers."
	icon_state = "beret_black_security" //old sprite was lost, this is the next closest.
	item_state_slots = list(slot_r_hand_str = "beret", slot_l_hand_str = "beret")
	armor_spec = "melee=65;bullet=55;laser=35;energy=20;bomb=30;bio=30;rad=30;cold=60"

CAPABILITIES(/obj/item/clothing/head/helmet/space/deathsquad/beret)
	configure(item_worn(flags = 0, hides = BLOCKHAIR))
	configure(item_protection(siemens = 0.9))

//Space santa outfit suit
/obj/item/clothing/head/helmet/space/santahat
	name = "Santa's hat"
	desc = "Ho ho ho. Merrry X-mas!"
	icon_state = "santahat"

CAPABILITIES(/obj/item/clothing/head/helmet/space/santahat)
	configure(item_worn(flags = 0, hides = BLOCKHAIR, covers = HEAD))

/obj/item/clothing/suit/space/santa
	name = "Santa's suit"
	desc = "Festive!"
	icon_state = "santa"
	slowdown = 0

CAPABILITIES(/obj/item/clothing/suit/space/santa)
	configure(item_worn(flags = 0))

//Space pirate outfit

TYPE_TABLE(/obj/item/clothing/suit/space/santa, suit_storage_spec, list(HOLD_ONLY(list(/obj/item))))
/obj/item/clothing/head/helmet/space/pirate
	name = "pirate hat"
	desc = "Yarr."
	icon_state = "pirate"
	armor_spec = "melee=60;bullet=50;laser=30;energy=15;bomb=30;bio=30;rad=30;cold=60"

CAPABILITIES(/obj/item/clothing/head/helmet/space/pirate)
	configure(item_worn(flags = 0, hides = BLOCKHAIR, covers = 0))
	configure(item_protection(siemens = 0.9))

/obj/item/clothing/suit/space/pirate //Whhhhyyyyyyy???
	name = "pirate coat"
	desc = "Yarr."
	icon_state = "pirate"
	w_class = ITEMSIZE_NORMAL
	slowdown = 0
	armor_spec = "melee=60;bullet=50;laser=30;energy=15;bomb=30;bio=30;rad=30;cold=60"

CAPABILITIES(/obj/item/clothing/suit/space/pirate)
	configure(item_worn(hides = HIDETAIL|HIDEHOLSTER, covers = UPPER_TORSO|ARMS))
	configure(item_protection(siemens = 0.9))

//Orange emergency space suit

TYPE_TABLE(/obj/item/clothing/suit/space/pirate, suit_storage_spec, list(HOLD_ONLY(list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_EXPLO))))
/obj/item/clothing/head/helmet/space/emergency
	name = "emergency soft helmet"
	icon_state = "syndicate-helm-orange"
	desc = "A simple helmet with a built in light, smells like mothballs."
	flash_protection = FLASH_PROTECTION_NONE

/obj/item/clothing/suit/space/emergency
	name = "emergency softsuit"
	icon_state = "syndicate-orange"
	desc = "A thin, ungainly softsuit colored in blaze orange for rescuers to easily locate, looks pretty fragile."
	slowdown = 2
