MATERIAL_MIX(/obj/item/nifrepairer, list(MAT_STEEL = 4000, MAT_GLASS = 6000))
//Programs nanopaste into NIF repair nanites
/obj/item/nifrepairer
	name = "advanced NIF repair tool"
	desc = "A tool that accepts nanopaste and converts the nanites into NIF repair nanites for injection/ingestion. Insert paste, deposit into container."
	icon = 'icons/obj/device_alt.dmi'
	icon_state = "hydro"
	item_state = "gun"
	slot_flags = SLOT_BELT
	throwforce = 3
	w_class = ITEMSIZE_SMALL
	throw_speed = 5
	throw_range = 10
	var/datum/reagents/supply
	var/efficiency = 15 //How many units reagent per 1 unit nanopaste
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

CAPABILITIES(/obj/item/nifrepairer)
	owns_one(nameof(supply), /datum/reagents)
	op("item", item(/obj/item), label("Load"), then(PROC_REF(interaction_item)))

/obj/item/nifrepairer/Initialize(mapload)
	. = ..()

	rel_set(src, nameof(supply), new /datum/reagents(max = 60, A = src)) // ALLOW(decl): the holder is built with constructor arguments (a size and its owner) that a bare declaration cannot pass

/obj/item/nifrepairer/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W,/obj/item/stack/nanopaste))
		var/obj/item/stack/nanopaste/np = W
		if((supply.get_free_space() >= efficiency) && np.use(1))
			to_chat(user, span_notice("You convert some nanopaste into programmed nanites inside \the [src]."))
			supply.add_reagent(id = REAGENT_ID_NIFREPAIRNANITES, amount = efficiency)
		else if(supply.get_free_space() < efficiency)
			to_chat(user, span_warning("\The [src] is too full. Empty it into a container first."))
	return TRUE

/obj/item/nifrepairer/proc/appearance_filled()
	return supply?.total_volume ? TRUE : FALSE

/// The look (the draw sweep: from its template).
/obj/item/nifrepairer/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][appearance_filled() ? "2" : ""]")

/obj/item/nifrepairer/afterattack(atom/target, mob/user, proximity)
	if(!target.is_open_container() || !target.reagents)
		return 0

	if(!supply || !supply.total_volume)
		to_chat(user, span_warning("[src] is empty. Feed it nanopaste."))
		return 1

	if(!target.reagents.get_free_space())
		to_chat(user, span_warning("[target] is already full."))
		return 1

	var/trans = supply.trans_to(target, 15)
	to_chat(user, span_notice("You transfer [trans] units of the programmed nanites to [target]."))
	changed(src)
	return 1

/obj/item/nifrepairer/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		if(supply.total_volume)
			. += span_notice("\The [src] contains [supply.total_volume] units of programmed nanites, ready for dispensing.")
		else
			. += span_notice("\The [src] is empty and ready to accept nanopaste.")

