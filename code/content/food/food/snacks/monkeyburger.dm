/obj/item/reagent_containers/food/snacks/monkeyburger
	name = "burger"
	desc = "The cornerstone of every nutritious breakfast."
	icon_state = "hburger"
	filling_color = "#D63C3C"
	nutriment_amt = 3
	nutriment_desc = list("bun" = 2)
	bitesize = 2

// Burger + cheese wedge = cheeseburger
CAPABILITIES(/obj/item/reagent_containers/food/snacks/monkeyburger)
	configure(atom_rules(price_tag = 2))
	configure(item_handling(center_x = 16, center_y = 11))
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 3)))
	op("add_cheese", item(/obj/item/reagent_containers/food/snacks/cheesewedge), priority(OP_PRIORITY_PART + 1), label("Add the cheese"), then(PROC_REF(cheese_added)))

/obj/item/reagent_containers/food/snacks/monkeyburger/proc/cheese_added(datum/act/op/A)
	return turn_into(A, /obj/item/reagent_containers/food/snacks/cheeseburger, "You make a cheeseburger.", uses_held = TRUE)
