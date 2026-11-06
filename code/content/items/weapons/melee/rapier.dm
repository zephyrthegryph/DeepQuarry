/obj/item/melee/rapier
	name = "rapier"
	desc = "A gleaming steel blade with a gold handguard and inlayed with an outstanding red gem."
	icon = 'icons/obj/weapons_vr.dmi'
	icon_state = "rapier"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_melee_vr.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_melee_vr.dmi',
		)
	w_class = ITEMSIZE_NORMAL

CAPABILITIES(/obj/item/melee/rapier)
	configure(item_combat(injury_kind = INJURY_PIERCE))
	configure(item_thrown(force = 10))
	configure(item_combat(force = 15, sharp = TRUE, edge = FALSE, attack_verbs = list("stabbed", "lunged at", "dextrously struck", "sliced", "lacerated", "impaled", "diced", "charioted")))
	configure(item_sounds(hit = SFX_WEAPONS_BLADESLICE))
