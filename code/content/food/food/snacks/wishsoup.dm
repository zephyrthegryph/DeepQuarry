/obj/item/reagent_containers/food/snacks/wishsoup
	name = "Wish Soup"
	desc = "I wish this was soup."
	icon_state = "wishsoup"
	trash = /obj/item/trash/snack_bowl
	filling_color = "#D1F4FF"
	bitesize = 5
	eating_sound = SFX_ITEMS_DRINK

CAPABILITIES(/obj/item/reagent_containers/food/snacks/wishsoup)
	configure(atom_rules(price_tag = 3))
	configure(item_handling(center_x = 16, center_y = 11))
	rolls(nameof(wished), chance(25))
	rolls(nameof(desc), PROC_REF(roll_wish_desc), from = list(nameof(wished)))
	configure(reagents(add = list(REAGENT_ID_WATER = 10, REAGENT_ID_NUTRIMENT = PROC_REF(wish_nutriment)), data = list(REAGENT_ID_NUTRIMENT = list("something good" = 8))))

/// Rolled before init: one wish soup in four came true.
/obj/item/reagent_containers/food/snacks/wishsoup/var/wished = FALSE

/obj/item/reagent_containers/food/snacks/wishsoup/proc/roll_wish_desc(datum/roller/R)
	return wished ? "A wish come true!" : desc

/// A wish that came true is a real soup: 8 units of nutriment (a computed reagents() amount; 0 adds nothing).
/obj/item/reagent_containers/food/snacks/wishsoup/proc/wish_nutriment()
	return wished ? 8 : 0
