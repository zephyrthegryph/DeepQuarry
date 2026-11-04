/obj/item/reagent_containers/food/snacks/sliceable/pizza/crunch
	name = "pizza crunch"
	desc = "This was once a normal pizza, but it has been coated in batter and deep-fried. Whatever toppings it once had are a mystery, but they're still under there, somewhere..."
	icon_state = "pizzacrunch"
	slice_path = /obj/item/reagent_containers/food/snacks/pizzacrunchslice
	slices_num = 6
	nutriment_amt = 25
	nutriment_desc = list("fried pizza" = 25)
	bitesize = 2

CAPABILITIES(/obj/item/reagent_containers/food/snacks/sliceable/pizza/crunch)
	configure(item_handling(center_x = 16, center_y = 11))
	setup(PROC_REF(bind_batter_coating))
	configure(reagents(add = list(REAGENT_ID_BATTER = 6.5)))
	configure(reagents(add = list(REAGENT_ID_OIL = 4)))

/obj/item/reagent_containers/food/snacks/sliceable/pizza/crunch/proc/bind_batter_coating()
	rel_set(src, nameof(coating), reagents.get_reagent(REAGENT_ID_BATTER))
