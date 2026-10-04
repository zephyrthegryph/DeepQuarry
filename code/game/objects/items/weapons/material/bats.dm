/obj/item/material/twohanded/baseballbat
	name = "bat"
	desc = "HOME RUN!"
	icon_state = "metalbat0"
	base_icon = "metalbat"
	throwforce = 7
	attack_verb = list("smashed", "beaten", "slammed", "smacked", "struck", "battered", "bonked")
	hitsound = SFX_WEAPONS_GENHIT3
	default_material = MAT_WOOD
	force_divisor = 1.1           // 22 when wielded with weight 20 (steel)
	unwielded_force_divisor = 0.7 // 15 when unwielded based on above.
	dulled_divisor = 0.75		  // A "dull" bat is still gonna hurt
	slot_flags = SLOT_BACK

//Predefined materials go here.
TYPE_TABLE(/obj/item/material/twohanded/baseballbat/metal, weapon_forced_material, MAT_STEEL)

TYPE_TABLE(/obj/item/material/twohanded/baseballbat/uranium, weapon_forced_material, MAT_URANIUM)

TYPE_TABLE(/obj/item/material/twohanded/baseballbat/gold, weapon_forced_material, MAT_GOLD)

TYPE_TABLE(/obj/item/material/twohanded/baseballbat/platinum, weapon_forced_material, MAT_PLATINUM)

TYPE_TABLE(/obj/item/material/twohanded/baseballbat/diamond, weapon_forced_material, MAT_DIAMOND)
