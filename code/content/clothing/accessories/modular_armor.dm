///#define ACCESSORY_SLOT_ARMOR_G  0x8000 ///too lazy to move this upstream

/obj/item/clothing/suit/armor/pcarrier/modarm
	name = "modular plate carrier"
	desc = "A lightweight, modular plate carrier vest made from armor grade UHMWPE. It can be equipped with armor plates, but provides very little protection of its own."
	armor_spec = "melee=5;bullet=5"
	icon = 'icons/obj/modular_armor.dmi'
	icon_override = 'icons/obj/modular_armor.dmi'
	item_icons = 'icons/obj/modular_armor.dmi'
	item_state = "pcarrier"
	valid_accessory_slots = (\
		ACCESSORY_SLOT_INSIGNIA\
		|ACCESSORY_SLOT_ARMOR_C\
		|ACCESSORY_SLOT_ARMOR_A\
		|ACCESSORY_SLOT_ARMOR_L\
		|ACCESSORY_SLOT_ARMOR_S\
		|ACCESSORY_SLOT_ARMOR_M\
		|ACCESSORY_SLOT_OVER\
		|ACCESSORY_SLOT_ARMBAND)
	restricted_accessory_slots = (\
		ACCESSORY_SLOT_INSIGNIA\
		|ACCESSORY_SLOT_ARMOR_C\
		|ACCESSORY_SLOT_ARMOR_A\
		|ACCESSORY_SLOT_ARMOR_L\
		|ACCESSORY_SLOT_ARMOR_S\
		|ACCESSORY_SLOT_ARMOR_M\
		|ACCESSORY_SLOT_ARMBAND)
	blood_overlay_type = "armor"

/obj/item/clothing/suit/armor/pcarrier/modarm/green
	item_state = "pcarrierG"
	icon_state = "pcarrierG"

/obj/item/clothing/suit/armor/pcarrier/modarm/blue
	item_state = "pcarrierB"
	icon_state = "pcarrierB"

/obj/item/clothing/suit/armor/pcarrier/modarm/tan
	item_state = "pcarrierT"
	icon_state = "pcarrierT"

/obj/item/clothing/suit/armor/pcarrier/modarm/lightblue
	item_state = "pcarrierU"
	icon_state = "pcarrierU"

///snowflake armor plates

/obj/item/clothing/accessory/armor/armorplate/security
	name = "security armor plate"
	desc = "A plasteel-reinforced synthetic armor plate designed for Nanotrasen security forces. Attaches to a plate carrier."
	icon_state = "armor_medium"
	slowdown = 0.1
	armor_spec = "melee=30;bullet=30;laser=45;energy=25;bomb=10"

CAPABILITIES(/obj/item/clothing/accessory/armor/armorplate/security)
	configure(item_protection(siemens = 0.7))

/obj/item/clothing/accessory/armor/armorplate/security/heavy
	name = "heavy security armor plate"
	desc = "A plastitanium-reinforced armor plate designed for Nanotrasen security forces. Attaches to a plate carrier."
	icon_state = "armor_medium"
	slowdown = 0.5
	armor_spec = "melee=50;bullet=50;laser=55;energy=35;bomb=30;rad=15"

CAPABILITIES(/obj/item/clothing/accessory/armor/armorplate/security/heavy)
	configure(item_protection(siemens = 0.5))

///armored gloves

/obj/item/clothing/gloves/handguards_modarm
	name = "reinforced gauntlets"
	desc = "These armored gauntlets will protect your hands and forearms. Meant to be used with a plate carrier."
	icon = 'icons/obj/modular_armor.dmi'
	icon_override = 'icons/obj/modular_armor.dmi'
	icon_state = "handguards_item"
	item_state = "handguards"
	overgloves = 1
	punch_force = 3
	slowdown = 0.1
	w_class = ITEMSIZE_NORMAL
	armor_spec = "melee=30;bullet=30;laser=45;energy=25;bomb=10"

CAPABILITIES(/obj/item/clothing/gloves/handguards_modarm)
	configure(item_worn(worn_icon = "handguards", covers = HANDS))
	configure(item_protection(heat_parts = HANDS, cold_parts = HANDS))
	configure(item_sounds(drop = SFX_ITEMS_DROP_BOOTS, pickup = SFX_ITEMS_PICKUP_BOOTS))

///armored boots

/obj/item/clothing/shoes/footguards_modarm
	name = "reinforced boots"
	desc = "These armored boots will protect your ankles and feet."
	icon = 'icons/obj/modular_armor.dmi'
	icon_override = 'icons/obj/modular_armor.dmi'
	icon_state = "footguards_item"
	item_state = "footguards"
	armor_spec = "melee=30;bullet=30;laser=45;energy=25;bomb=10"
	w_class = ITEMSIZE_NORMAL
	slowdown = 0.1
	step_volume_mod = 1.3
	overshoes = 1
	shoes_under_pants = -1
	can_hold_knife = TRUE
	update_icon_define_digi = 'icons/obj/modular_armor_digi.dmi' ///this doesn't work, not sure why

CAPABILITIES(/obj/item/clothing/shoes/footguards_modarm)
	configure(item_worn(worn_icon = "footguards", covers = FEET))
	configure(item_protection(heat_parts = FEET, cold_parts = FEET))
	configure(item_sounds(drop = SFX_ITEMS_DROP_BOOTS, pickup = SFX_ITEMS_PICKUP_BOOTS))

///snowflake leg guards

/obj/item/clothing/accessory/armor/legguards/modarm
	name = "modular leg guards"
	desc = "A pair of armored leg pads. Attaches to a plate carrier."
	icon = 'icons/obj/modular_armor.dmi'
	icon_override = 'icons/obj/modular_armor.dmi'
	icon_state = "legguards"
	item_state = "legguards"
	gender = PLURAL
	armor_spec = "melee=40;bullet=40;laser=40;energy=25;bomb=30"
	slot = ACCESSORY_SLOT_ARMOR_L
	update_icon_define_digi = 'icons/obj/modular_armor_digi.dmi' ///this doesn't work, not sure why

CAPABILITIES(/obj/item/clothing/accessory/armor/legguards/modarm)
	configure(item_worn(worn_icon = "legguards", covers = LEGS))
	configure(item_protection(heat_parts = LEGS, cold_parts = LEGS))

/obj/item/clothing/accessory/armor/legguards/modarm/green
	icon_state = "legguardsG"
	item_state = "legguardsG"

CAPABILITIES(/obj/item/clothing/accessory/armor/legguards/modarm/green)
	configure(item_worn(worn_icon = "legguardsG"))

/obj/item/clothing/accessory/armor/legguards/modarm/blue
	icon_state = "legguardsB"
	item_state = "legguardsB"

CAPABILITIES(/obj/item/clothing/accessory/armor/legguards/modarm/blue)
	configure(item_worn(worn_icon = "legguardsB"))

/obj/item/clothing/accessory/armor/legguards/modarm/tan
	icon_state = "legguardsT"
	item_state = "legguardsT"

CAPABILITIES(/obj/item/clothing/accessory/armor/legguards/modarm/tan)
	configure(item_worn(worn_icon = "legguardsT"))

/obj/item/clothing/accessory/armor/legguards/modarm/lightblue
	icon_state = "legguardsU"
	item_state = "legguardsU"

CAPABILITIES(/obj/item/clothing/accessory/armor/legguards/modarm/lightblue)
	configure(item_worn(worn_icon = "legguardsU"))

///snowflake arm guards

/obj/item/clothing/accessory/armor/armguards/modarm
	name = "modular arm guards"
	desc = "A pair of arm pads reinforced with armor plating. Attaches to a plate carrier."
	icon = 'icons/obj/modular_armor.dmi'
	icon_override = 'icons/obj/modular_armor.dmi'
	icon_state = "armguards"
	item_state = "armguards"
	gender = PLURAL
	armor_spec = "melee=40;bullet=40;laser=40;energy=25;bomb=30"
	slot = ACCESSORY_SLOT_ARMOR_A

CAPABILITIES(/obj/item/clothing/accessory/armor/armguards/modarm)
	configure(item_worn(worn_icon = "armguards", covers = ARMS))
	configure(item_protection(heat_parts = ARMS, cold_parts = ARMS))

/obj/item/clothing/accessory/armor/armguards/modarm/green
	icon_state = "armguardsG"
	item_state = "armguardsG"

CAPABILITIES(/obj/item/clothing/accessory/armor/armguards/modarm/green)
	configure(item_worn(worn_icon = "armguardsG"))

/obj/item/clothing/accessory/armor/armguards/modarm/blue
	icon_state = "armguardsB"
	item_state = "armguardsB"

CAPABILITIES(/obj/item/clothing/accessory/armor/armguards/modarm/blue)
	configure(item_worn(worn_icon = "armguardsB"))

/obj/item/clothing/accessory/armor/armguards/modarm/tan
	icon_state = "armguardsT"
	item_state = "armguardsT"

CAPABILITIES(/obj/item/clothing/accessory/armor/armguards/modarm/tan)
	configure(item_worn(worn_icon = "armguardsT"))

/obj/item/clothing/accessory/armor/armguards/modarm/lightblue
	icon_state = "armguardsU"
	item_state = "armguardsU"

CAPABILITIES(/obj/item/clothing/accessory/armor/armguards/modarm/lightblue)
	configure(item_worn(worn_icon = "armguardsU"))


///snowflake groinpad (it's actually a tag because i can't code x_x)

/obj/item/clothing/accessory/armor/groinpad
	name = "modular groin pad"
	desc = "A thick kevlar pad, that protects the groin and the buttocks."
	icon_override = 'icons/obj/modular_armor.dmi'
	icon = 'icons/obj/modular_armor.dmi'
	icon_state = "groinpad"
	item_state = "groinpad"
	gender = PLURAL
	armor_spec = ""
	slot = ACCESSORY_SLOT_ARMOR_M
	///slot = ACCESSORY_SLOT_ARMOR_G ///too lazy to move this upstream

CAPABILITIES(/obj/item/clothing/accessory/armor/groinpad)
	configure(item_worn(worn_icon = "groinpad"))

/obj/item/clothing/accessory/armor/groinpad/green
	icon_state = "groinpadG"
	item_state = "groinpadG"

CAPABILITIES(/obj/item/clothing/accessory/armor/groinpad/green)
	configure(item_worn(worn_icon = "groinpadG"))

/obj/item/clothing/accessory/armor/groinpad/blue
	icon_state = "groinpadB"
	item_state = "groinpadB"

CAPABILITIES(/obj/item/clothing/accessory/armor/groinpad/blue)
	configure(item_worn(worn_icon = "groinpadB"))

/obj/item/clothing/accessory/armor/groinpad/tan
	icon_state = "groinpadT"
	item_state = "groinpadT"

CAPABILITIES(/obj/item/clothing/accessory/armor/groinpad/tan)
	configure(item_worn(worn_icon = "groinpadT"))

/obj/item/clothing/accessory/armor/groinpad/lightblue
	icon_state = "groinpadU"
	item_state = "groinpadU"

CAPABILITIES(/obj/item/clothing/accessory/armor/groinpad/lightblue)
	configure(item_worn(worn_icon = "groinpadU"))

///helmet
/obj/item/clothing/head/helmet/riot/modarm
	name_descriptor = "visored helmet"

/obj/item/clothing/head/helmet/riot/modarm/killa
	name = "striped visored helmet"
	desc = "It's a heavy plasteel visored helmet designed for security work, and light combat. This one has three menacing white stripes."
	icon_state = "modhelm_killa"
	item_state = "modhelm_killa"

///presets

/obj/item/clothing/suit/armor/pcarrier/modarm/full
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/medium, /obj/item/clothing/accessory/armor/armguards/modarm, /obj/item/clothing/accessory/armor/legguards/modarm, /obj/item/clothing/accessory/armor/groinpad, /obj/item/clothing/accessory/storage/pouches/large)

/obj/item/clothing/suit/armor/pcarrier/modarm/sec
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/security, /obj/item/clothing/accessory/storage/pouches/large)

/obj/item/clothing/suit/armor/pcarrier/modarm/full/sec
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/security, /obj/item/clothing/accessory/armor/armguards/modarm, /obj/item/clothing/accessory/armor/legguards/modarm, /obj/item/clothing/accessory/armor/groinpad, /obj/item/clothing/accessory/storage/pouches/large)
