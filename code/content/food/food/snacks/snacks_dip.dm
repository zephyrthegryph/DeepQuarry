//Dips//////////////////////////////////////

/obj/item/reagent_containers/food/snacks/dip
	name = "queso dip"
	desc = "A simple, cheesy dip consisting of tomatos, cheese, and spices."
	var/nachotrans = /obj/item/reagent_containers/food/snacks/chip/nacho/cheese
	var/chiptrans = /obj/item/reagent_containers/food/snacks/chip/cheese
	icon_state = "dip_cheese"
	trash = /obj/item/trash/small_bowl
	bitesize = 1
	nutriment_desc = list("queso" = 20)
	nutriment_amt = 20

// A chip held to a dip is dipped.
CAPABILITIES(/obj/item/reagent_containers/food/snacks/dip)
	configure(item_handling(center_x = 16, center_y = 16))
	op("dip_chip", item(/obj/item/reagent_containers/food/snacks/chip), priority(OP_PRIORITY_PART + 1), when(PROC_REF(is_dippable)), label("Dip it"), then(PROC_REF(chip_dipped)))

/// What a chip dipped here becomes, or null when it is not one that can be.
/obj/item/reagent_containers/food/snacks/dip/proc/dipped_type(obj/item/reagent_containers/food/snacks/item)
	if(istype(item, /obj/item/reagent_containers/food/snacks/chip/nacho) && item.icon_state == "nacho")
		return nachotrans
	if(istype(item, /obj/item/reagent_containers/food/snacks/chip) && (item.icon_state == "chip" || item.icon_state == "chip_half"))
		return chiptrans
	return null

/obj/item/reagent_containers/food/snacks/dip/proc/is_dippable(datum/act/op/A)
	return !isnull(dipped_type(A.held))

/// The chip comes out dipped: what it held and some of the dip, in the hand; the dip is used up with its last scoop.
/obj/item/reagent_containers/food/snacks/dip/proc/chip_dipped(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/food/snacks/item = A.held
	var/chip_type = dipped_type(item)
	var/obj/item/reagent_containers/food/snacks/returningitem = new chip_type(src)
	returningitem.reagents.clear_reagents() //Clear the new chip
	var/memed = 0
	item.reagents.trans_to(returningitem, item.reagents.total_volume) //Old chip to new chip
	if(item.icon_state == "chip_half")
		returningitem.set_icon_state("[returningitem.icon_state]_half")
		returningitem.set_bitesize(clamp(returningitem.reagents.total_volume,1,10))
	else if(prob(1))
		memed = 1
		to_chat(user, "You scoop up some dip with the chip, but mid-scop, the chip breaks off into the dreadful abyss of dip, never to be seen again...")
		returningitem.set_icon_state("[returningitem.icon_state]_half")
		returningitem.set_bitesize(clamp(returningitem.reagents.total_volume,1,10))
	else
		returningitem.set_bitesize(clamp(returningitem.reagents.total_volume*0.5,1,10))
	consume(item, user)
	reagents.trans_to(returningitem, bitesize) //Dip to new chip
	user.put_in_hands(returningitem)

	if (reagents && reagents.total_volume)
		if(!memed)
			to_chat(user, "You scoop up some dip with the chip.")
	else
		if(!memed)
			to_chat(user, "You scoop up the remaining dip with the chip.")
		var/obj/waste = variant_new(trash, loc)
		if (loc == user)
			user.put_in_hands(waste)
		consume(src, user)
	return OP_OK

/obj/item/reagent_containers/food/snacks/dip/salsa
	name = "salsa dip"
	desc = "Traditional Sol chunky salsa dip containing tomatos, peppers, and spices."
	nachotrans = /obj/item/reagent_containers/food/snacks/chip/nacho/salsa
	chiptrans = /obj/item/reagent_containers/food/snacks/chip/salsa
	icon_state = "dip_salsa"
	nutriment_desc = list("salsa" = 20)
	nutriment_amt = 20

/obj/item/reagent_containers/food/snacks/dip/guac
	name = "guac dip"
	desc = "A recreation of the ancient Sol 'Guacamole' dip using tofu, limes, and spices. This recreation obviously leaves out mole meat."
	nachotrans = /obj/item/reagent_containers/food/snacks/chip/nacho/guac
	chiptrans = /obj/item/reagent_containers/food/snacks/chip/guac
	icon_state = "dip_guac"
	nutriment_desc = list("guacmole" = 20)
	nutriment_amt = 20
