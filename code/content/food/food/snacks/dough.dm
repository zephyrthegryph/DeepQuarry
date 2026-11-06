/obj/item/reagent_containers/food/snacks/dough
	name = "dough"
	desc = "A piece of dough."
	icon = 'icons/obj/food_ingredients.dmi'
	icon_state = "dough"
	bitesize = 2
	nutriment_amt = 3
	nutriment_desc = list("uncooked dough" = 3)

// Dough + rolling pin = flat dough
CAPABILITIES(/obj/item/reagent_containers/food/snacks/dough)
	configure(item_handling(center_x = 16, center_y = 13))
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 1)))
	op("flatten", item(/obj/item/material/kitchen/rollingpin), priority(OP_PRIORITY_PART + 1), label("Flatten it"), then(PROC_REF(flattened)))

/obj/item/reagent_containers/food/snacks/dough/proc/flattened(datum/act/op/A)
	return turn_into(A, /obj/item/reagent_containers/food/snacks/sliceable/flatdough, "You flatten the dough.")
