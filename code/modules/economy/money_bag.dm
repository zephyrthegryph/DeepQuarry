/*****************************Money bag********************************/

/obj/item/moneybag
	icon = 'icons/obj/storage.dmi'
	name = "Money bag"
	icon_state = "moneybag"
	force = 10.0
	throwforce = 2.0
	w_class = ITEMSIZE_LARGE

/// Old attack_hand.
/obj/item/moneybag/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	// structured TGUI Moneybag (see
	// code/modules/admin/moneybag_panel.dm).
	tgui_interact(user)
	return TRUE

/obj/item/moneybag/proc/count_coins()
	var/list/counts = list(
		"gold" = 0,
		"silver" = 0,
		"iron" = 0,
		"diamond" = 0,
		"phoron" = 0,
		"uranium" = 0,
	)
	for(var/obj/item/coin/C in contents)
		if(istype(C, /obj/item/coin/diamond))
			counts["diamond"]++
		else if(istype(C, /obj/item/coin/phoron))
			counts["phoron"]++
		else if(istype(C, /obj/item/coin/iron))
			counts["iron"]++
		else if(istype(C, /obj/item/coin/silver))
			counts["silver"]++
		else if(istype(C, /obj/item/coin/gold))
			counts["gold"]++
		else if(istype(C, /obj/item/coin/uranium))
			counts["uranium"]++
	return counts

/// Old attackby.
/obj/item/moneybag/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if (istype(W, /obj/item/coin))
		var/obj/item/coin/C = W
		if(!own_bring_in(src, nameof(contents), C, null, user, TRUE, null, FALSE))
			return OP_PASS
		to_chat(user, span_blue("You add the [C.name] into the bag."))
	if (istype(W, /obj/item/moneybag))
		var/obj/item/moneybag/C = W
		for (var/obj/O in contents_of(C))
			O.forceMove(src)
		to_chat(user, span_blue("You empty the [C.name] into the bag."))
	return OP_PASS


/obj/item/moneybag/vault

CAPABILITIES(/obj/item/moneybag/vault)
	initial_contents(/obj/item/coin/silver, count = 4)
	initial_contents(/obj/item/coin/gold, count = 2)

/// Takes one coin of material `coin_type` out of the bag.
/obj/item/moneybag/proc/moneybag_remove_coin(mob/living/user, coin_type)
	// Standard interaction gating: the actor must be a conscious, unrestrained mob
	// adjacent to the bag before any contents can be moved.
	if(!istype(user) || user.stat != CONSCIOUS || user.restrained() || !user.Adjacent(src))
		return
	var/static/list/coin_types = list(
		MAT_GOLD = /obj/item/coin/gold,
		MAT_SILVER = /obj/item/coin/silver,
		MAT_IRON = /obj/item/coin/iron,
		MAT_DIAMOND = /obj/item/coin/diamond,
		MAT_PHORON = /obj/item/coin/phoron,
		MAT_URANIUM = /obj/item/coin/uranium,
	)
	var/coin_path = coin_types[coin_type]
	if(!coin_path)
		return
	var/obj/item/coin/COIN = locate_within(src, coin_path)
	if(!COIN)
		return
	COIN.forceMove(src.loc)
