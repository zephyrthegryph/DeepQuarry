/obj/item/melee/cullingcane
	name = "culling cane"
	defend_chance = 15	// The base chance for the weapon to parry.
	projectile_parry_chance = 15
	injury_kind = INJURY_CUT
	w_class = ITEMSIZE_LARGE
	slot_flags = SLOT_BACK
	icon_state = "scythe0"

CAPABILITIES(/obj/item/melee/cullingcane)
	configure(item_combat(sharp = TRUE, edge = TRUE, force = 35, attack_verbs = list("attacked", "chopped", "cleaved", "torn", "cut"), can_cleave = TRUE))
