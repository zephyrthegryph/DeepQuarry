TYPE_TABLE(/obj/item/material/twohanded/baseballbat/foam, weapon_forced_material, MAT_FOAM)

/obj/item/material/sword/foam
	force_divisor = 1
	unbreakable = 1

CAPABILITIES(/obj/item/material/sword/foam)
	configure(item_combat(injury_kind = INJURY_PAIN))
	configure(item_combat(attack_verbs = list("bonked","whacked")))

/obj/item/material/twohanded/baseballbat/foam
	force_wielded = 1
	force_divisor = 1
	unbreakable = 1

CAPABILITIES(/obj/item/material/twohanded/baseballbat/foam)
	configure(item_combat(injury_kind = INJURY_PAIN))
	configure(item_combat(attack_verbs = list("bonked","whacked")))

TYPE_TABLE(/obj/item/material/sword/foam, weapon_forced_material, MAT_FOAM)

/obj/item/material/twohanded/spear/foam
	force_wielded = 1
	force_divisor = 1
	applies_material_colour = 1
	base_icon = "spear_mask"
	icon_state = "spear_mask0"
	unbreakable = 1

CAPABILITIES(/obj/item/material/twohanded/spear/foam)
	configure(item_combat(injury_kind = INJURY_PAIN))
	configure(item_combat(attack_verbs = list("bonked","whacked")))

TYPE_TABLE(/obj/item/material/twohanded/spear/foam, weapon_forced_material, MAT_FOAM)

/obj/item/material/twohanded/fireaxe/foam
	force_wielded = 1
	force_divisor = 1
	applies_material_colour = 1
	base_icon = "fireaxe_mask"
	icon_state = "fireaxe_mask0"
	unbreakable = 1

CAPABILITIES(/obj/item/material/twohanded/fireaxe/foam)
	configure(item_combat(injury_kind = INJURY_PAIN))
	configure(item_combat(attack_verbs = list("bonked","whacked")))

TYPE_TABLE(/obj/item/material/twohanded/fireaxe/foam, weapon_forced_material, MAT_FOAM)

/obj/item/material/twohanded/fireaxe/foam/afterattack()
	return
