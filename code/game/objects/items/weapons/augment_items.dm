// **For augment items that aren't subtypes of other things.**

/obj/item/melee/augment
	name = "integrated item"
	desc = "A surprisingly non-descript item, integrated into its user. You probably shouldn't be seeing this."
	icon = 'icons/obj/surgery.dmi'
	icon_state = "augment_box"
	embed_chance = -1


/obj/item/melee/augment/blade
	name = "handblade"
	desc = "A sleek-looking telescopic blade that fits inside the hand. Favored by infiltration specialists and assassins."
	icon_state = "augment_handblade"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_melee.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_melee.dmi',
			)
	w_class = ITEMSIZE_SMALL
	injury_kind = INJURY_PIERCE
	defend_chance = 10
	projectile_parry_chance = 5

CAPABILITIES(/obj/item/melee/augment/blade)
	configure(item_combat(force = 15, armor_penetration = 25, sharp = TRUE, attack_verbs = list("attacked", "slashed", "stabbed", "sliced", "torn", "ripped", "diced", "cut")))
	configure(item_sounds(hit = SFX_WEAPONS_BLADESLICE))

/obj/item/melee/augment/blade/arm
	name = "armblade"
	desc = "A sleek-looking cybernetic blade that cleaves through people like butter. Favored by psychopaths and assassins."
	icon_state = "augment_armblade"
	w_class = ITEMSIZE_HUGE
	injury_kind = INJURY_CUT
	defend_chance = 40
	projectile_parry_chance = 20

CAPABILITIES(/obj/item/melee/augment/blade/arm)
	configure(item_tooling(pry = 1))
	configure(item_combat(force = 30, armor_penetration = 15, edge = TRUE))
