/obj/item/reagent_containers/food/snacks/human/burger
	name = "-burger"
	desc = "A bloody burger."
	icon_state = "hburger"
	bitesize = 2

// Human Burger + cheese wedge = cheeseburger
CAPABILITIES(/obj/item/reagent_containers/food/snacks/human/burger)
	configure(atom_rules(price_tag = 2))
	configure(item_handling(center_x = 16, center_y = 11))
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 6)))
	op("add_cheese", item(/obj/item/reagent_containers/food/snacks/cheesewedge), priority(OP_PRIORITY_PART + 1), label("Add the cheese"), then(PROC_REF(cheese_added)))

/obj/item/reagent_containers/food/snacks/human/burger/proc/cheese_added(datum/act/op/A)
	return turn_into(A, /obj/item/reagent_containers/food/snacks/cheeseburger, "You make a cheeseburger.", uses_held = TRUE)
