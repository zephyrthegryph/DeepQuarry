TYPE_TABLE(/obj/item/material/twohanded/baseballbat/foam, weapon_forced_material, MAT_FOAM)

/obj/item/material/sword/foam
	attack_verb = list("bonked","whacked")
	force_divisor = 1
	unbreakable = 1
	injury_kind = INJURY_PAIN

/obj/item/material/twohanded/baseballbat/foam
	attack_verb = list("bonked","whacked")
	force_wielded = 1
	force_divisor = 1
	unbreakable = 1
	injury_kind = INJURY_PAIN

TYPE_TABLE(/obj/item/material/sword/foam, weapon_forced_material, MAT_FOAM)

/obj/item/material/twohanded/spear/foam
	attack_verb = list("bonked","whacked")
	force_wielded = 1
	force_divisor = 1
	injury_kind = INJURY_PAIN
	applies_material_colour = 1
	base_icon = "spear_mask"
	icon_state = "spear_mask0"
	unbreakable = 1

TYPE_TABLE(/obj/item/material/twohanded/spear/foam, weapon_forced_material, MAT_FOAM)

/obj/item/material/twohanded/fireaxe/foam
	attack_verb = list("bonked","whacked")
	force_wielded = 1
	force_divisor = 1
	injury_kind = INJURY_PAIN
	applies_material_colour = 1
	base_icon = "fireaxe_mask"
	icon_state = "fireaxe_mask0"
	unbreakable = 1

TYPE_TABLE(/obj/item/material/twohanded/fireaxe/foam, weapon_forced_material, MAT_FOAM)

/obj/item/material/twohanded/fireaxe/foam/afterattack()
	return
