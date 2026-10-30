/obj/item/melee/cullingcane
	name = "culling cane"
	defend_chance = 15	// The base chance for the weapon to parry.
	projectile_parry_chance = 15
	w_class = ITEMSIZE_LARGE
	icon_state = "scythe0"

CAPABILITIES(/obj/item/melee/cullingcane)
	configure(item_combat(injury_kind = INJURY_CUT))
	configure(item_worn(slots = SLOT_BACK))
	configure(item_combat(sharp = TRUE, edge = TRUE, force = 35, attack_verbs = list("attacked", "chopped", "cleaved", "torn", "cut"), can_cleave = TRUE))
