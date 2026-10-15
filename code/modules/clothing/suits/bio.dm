//Biosuit complete with shoes (in the item sprite)
/obj/item/clothing/head/bio_hood
	name = "bio hood"
	icon_state = "bio"
	desc = "A hood that protects the head and face from biological comtaminants."
	randpixel = 0
	center_of_mass_x = 0
	center_of_mass_y = 0
	armor_spec = "bio=100;rad=20;acid=60"
	flags = PHORONGUARD
	resistance_flags = UNACIDABLE

CAPABILITIES(/obj/item/clothing/head/bio_hood)
	configure(item_worn(hides = HIDEMASK|HIDEEARS|HIDEEYES|BLOCKHAIR, covers = HEAD|FACE|EYES, flags = THICKMATERIAL | ALLOW_SURVIVALFOOD))
	configure(item_protection(permeability = 0.01, siemens = 0.9))

/obj/item/clothing/suit/bio_suit
	name = "bio suit"
	desc = "A suit that protects against biological contamination."
	icon_state = "bio"
	w_class = ITEMSIZE_LARGE//bulky item
	slowdown = 1.0
	armor_spec = "bio=100;rad=20;acid=60"
	flags = PHORONGUARD
	resistance_flags = UNACIDABLE

CAPABILITIES(/obj/item/clothing/suit/bio_suit)
	acceptance(CONSTRAINT_SUIT_STORAGE, req_acceptance_type(list(POCKET_GENERIC, POCKET_EMERGENCY), because = "it doesn't take that"), mode = ACCEPTANCE_REPLACE)
	configure(item_worn(covers = CHEST|LEGS|ARMS|HANDS|FEET, hides = HIDEGLOVES|HIDESHOES|HIDEJUMPSUIT|HIDETAIL|HIDETIE|HIDEHOLSTER, flags = THICKMATERIAL))
	configure(item_protection(gas_transfer = 0.01, permeability = 0.01, siemens = 0.9))

//Standard biosuit, orange stripe


/obj/item/clothing/head/bio_hood/general
	icon_state = "bio_general"
	item_state_slots = list(slot_r_hand_str = "bio", slot_l_hand_str = "bio")

CAPABILITIES(/obj/item/clothing/head/bio_hood/general)
	configure(item_worn(covers = HEAD|FACE|EYES))

/obj/item/clothing/suit/bio_suit/general
	icon_state = "bio_general"
	item_state_slots = list(slot_r_hand_str = "bio", slot_l_hand_str = "bio")

CAPABILITIES(/obj/item/clothing/suit/bio_suit/general)
	configure(item_worn(hides = HIDEGLOVES|HIDEJUMPSUIT|HIDETAIL|HIDETIE|HIDEHOLSTER))

//Virology biosuit, green stripe
/obj/item/clothing/head/bio_hood/virology
	icon_state = "bio_virology"

/obj/item/clothing/suit/bio_suit/virology
	icon_state = "bio_virology"

CAPABILITIES(/obj/item/clothing/suit/bio_suit/virology)
	configure(item_worn(hides = HIDEGLOVES|HIDEJUMPSUIT|HIDETAIL|HIDETIE|HIDEHOLSTER))

//Security biosuit, grey with red stripe across the chest
/obj/item/clothing/head/bio_hood/security
	icon_state = "bio_security"

/obj/item/clothing/suit/bio_suit/security
	icon_state = "bio_security"

CAPABILITIES(/obj/item/clothing/suit/bio_suit/security)
	configure(item_worn(hides = HIDEGLOVES|HIDEJUMPSUIT|HIDETAIL|HIDETIE|HIDEHOLSTER))

//Janitor's biosuit, grey with purple arms
/obj/item/clothing/head/bio_hood/janitor
	icon_state = "bio_janitor"

/obj/item/clothing/suit/bio_suit/janitor
	icon_state = "bio_janitor"

CAPABILITIES(/obj/item/clothing/suit/bio_suit/janitor)
	configure(item_worn(hides = HIDEGLOVES|HIDEJUMPSUIT|HIDETAIL|HIDETIE|HIDEHOLSTER))

//Scientist's biosuit, white with a pink-ish hue
/obj/item/clothing/head/bio_hood/scientist
	icon_state = "bio_scientist"

/obj/item/clothing/suit/bio_suit/scientist
	icon_state = "bio_scientist"

CAPABILITIES(/obj/item/clothing/suit/bio_suit/scientist)
	configure(item_worn(hides = HIDEGLOVES|HIDEJUMPSUIT|HIDETAIL|HIDETIE|HIDEHOLSTER))

//CMO's biosuit, blue stripe
/obj/item/clothing/suit/bio_suit/cmo
	icon_state = "bio_cmo"

CAPABILITIES(/obj/item/clothing/suit/bio_suit/cmo)
	configure(item_worn(hides = HIDEGLOVES|HIDEJUMPSUIT|HIDETAIL|HIDETIE|HIDEHOLSTER))

/obj/item/clothing/head/bio_hood/cmo
	icon_state = "bio_cmo"

//Plague Dr mask can be found in clothing/masks/gasmask.dm. Golden can be found in labcoat.dm.
/obj/item/clothing/suit/bio_suit/plaguedoctorsuit
	name = "plague doctor suit"
	desc = "It protected doctors from the Black Death, back then. You bet your arse it's gonna help you against viruses."
	icon_state = "plaguedoctor"
	item_state_slots = list(slot_r_hand_str = "bio", slot_l_hand_str = "bio")

CAPABILITIES(/obj/item/clothing/suit/bio_suit/plaguedoctorsuit)
	configure(item_worn(hides = HIDEGLOVES|HIDEJUMPSUIT|HIDETAIL|HIDETIE|HIDEHOLSTER))
