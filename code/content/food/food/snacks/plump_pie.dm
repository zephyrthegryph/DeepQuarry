/obj/item/reagent_containers/food/snacks/plump_pie
	name = "plump pie"
	desc = "I bet you love stuff made out of plump helmets!"
	icon_state = "plump_pie"
	filling_color = "#B8279B"
	nutriment_amt = 8
	nutriment_desc = list("heartiness" = 2, PLANT_MUSHROOMS = 3, "pie" = 3)
	bitesize = 2

CAPABILITIES(/obj/item/reagent_containers/food/snacks/plump_pie)
	configure(atom_rules(price_tag = 4))
	configure(item_handling(center_x = 17, center_y = 9))
	rolls(nameof(name), pick_one(list("exceptional plump pie")), when = nameof(exceptional), from = list(nameof(exceptional)))
	rolls(nameof(desc), pick_one(list("Microwave is taken by a fey mood! It has cooked an exceptional plump pie!")), when = nameof(exceptional), from = list(nameof(exceptional)))
	rolls(nameof(exceptional), chance(10))
	configure(reagents(contents_from = PROC_REF(exceptional_contents)))
	configure(reagents(add = list(REAGENT_ID_FUNGI = 2)))

/obj/item/reagent_containers/food/snacks/plump_pie
	/// Whether the microwave's fey mood made it exceptional (rolls()).
	var/exceptional = FALSE

/obj/item/reagent_containers/food/snacks/plump_pie/proc/exceptional_contents()
	return exceptional ? list(REAGENT_ID_NUTRIMENT = 8, REAGENT_ID_TRICORDRAZINE = 5) : null
