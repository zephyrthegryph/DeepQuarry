/obj/item/reagent_containers/food/snacks/plumphelmetbiscuit
	name = "plump helmet biscuit"
	desc = "This is a finely-prepared plump helmet biscuit. The ingredients are exceptionally minced plump helmet, and well-minced dwarven wheat flour."
	icon_state = "phelmbiscuit"
	filling_color = "#CFB4C4"
	nutriment_amt = 5
	nutriment_desc = list(PLANT_MUSHROOMS = 4)
	bitesize = 2

CAPABILITIES(/obj/item/reagent_containers/food/snacks/plumphelmetbiscuit)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 13))
	rolls(nameof(name), pick_one(list("exceptional plump helmet biscuit")), when = nameof(exceptional), from = list(nameof(exceptional)))
	rolls(nameof(desc), pick_one(list("Microwave is taken by a fey mood! It has cooked an exceptional plump helmet biscuit!")), when = nameof(exceptional), from = list(nameof(exceptional)))
	rolls(nameof(exceptional), chance(10))
	configure(reagents(contents_from = PROC_REF(exceptional_contents)))
	configure(reagents(add = list(REAGENT_ID_FUNGI = 1)))

/obj/item/reagent_containers/food/snacks/plumphelmetbiscuit
	/// Whether the microwave's fey mood made it exceptional (rolls()).
	var/exceptional = FALSE

/obj/item/reagent_containers/food/snacks/plumphelmetbiscuit/proc/exceptional_contents()
	return exceptional ? list(REAGENT_ID_NUTRIMENT = 3) : null
