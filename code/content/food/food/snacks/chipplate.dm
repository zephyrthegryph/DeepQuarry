//Chip Baskets//////////////////////////////////////

/obj/item/reagent_containers/food/snacks/chipplate
	name = "basket of chips"
	desc = "A plate of chips intended for dipping."
	icon_state = "chip_basket"
	trash = /obj/item/trash/chipbasket
	var/vendingobject = /obj/item/reagent_containers/food/snacks/chip
	nutriment_desc = list("tortilla chips" = 10)
	bitesize = 1
	nutriment_amt = 10

// An empty hand takes a chip from the basket.
CAPABILITIES(/obj/item/reagent_containers/food/snacks/chipplate)
	drag_onto(PROC_REF(plate_dropped))
	op("take_chip", hand(), priority(OP_PRIORITY_PART), label("Take a chip"), then(PROC_REF(chip_taken)))

/obj/item/reagent_containers/food/snacks/chipplate/proc/chip_taken(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/food/snacks/returningitem = new vendingobject(loc)
	reagents.trans_to(returningitem, bitesize)
	returningitem.set_bitesize(2)
	user.put_in_hands(returningitem)
	if (reagents && reagents.total_volume)
		to_chat(user, "You take a chip from the plate.")
	else
		to_chat(user, "You take the last chip from the plate.")
		var/obj/waste = new trash(loc)
		if (loc == user)
			user.put_in_hands(waste)
		consume(src, user)
	return OP_OK

/obj/item/reagent_containers/food/snacks/chipplate/proc/plate_dropped(datum/act/input/A)
	var/mob/user = A.over
	if(istype(user) && user == A.actor)
		user.put_in_active_hand(src)
		pickup(user)
		return
	return INPUT_FALLTHROUGH

/obj/item/reagent_containers/food/snacks/chipplate/nachos
	name = "basket of nachos"
	desc = "A very cheesy basket of nacho."
	icon_state = "nachos"
	trash = /obj/item/trash/chipbasket
	vendingobject = /obj/item/reagent_containers/food/snacks/chip/nacho
	nutriment_desc = list("tortilla chips" = 10)
	bitesize = 1
	nutriment_amt = 14 //slightly better than just plain chips
