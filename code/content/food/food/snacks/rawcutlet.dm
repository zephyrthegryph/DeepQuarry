/obj/item/reagent_containers/food/snacks/rawcutlet
	name = "raw cutlet"
	desc = "A thin piece of raw meat."
	icon = 'icons/obj/food_ingredients.dmi'
	icon_state = "rawcutlet"
	bitesize = 1

CAPABILITIES(/obj/item/reagent_containers/food/snacks/rawcutlet)
	configure(item_handling(center_x = 17, center_y = 20))
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 1)))
	op("slice_bacon", item(/obj/item/material/knife), priority(OP_PRIORITY_PART + 1), label("Slice it into bacon"), then(PROC_REF(sliced_into_bacon)))

/obj/item/reagent_containers/food/snacks/rawcutlet/proc/sliced_into_bacon(datum/act/op/A)
	return turn_into(A, /obj/item/reagent_containers/food/snacks/rawbacon, "You slice the cutlet into thin strips of bacon.", copies = 2)
