/*****************************Money bag********************************/

/obj/item/moneybag
	icon = 'icons/obj/storage.dmi'
	name = "Money bag"
	icon_state = "moneybag"
	force = 10.0
	throwforce = 2.0
	w_class = ITEMSIZE_LARGE

DECLARE_INTERACTIONS(/obj/item/moneybag, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_hand.
/obj/item/moneybag/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
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
/obj/item/moneybag/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if (istype(W, /obj/item/coin))
		var/obj/item/coin/C = W
		if(!own_bring_in(src, nameof(contents), C, null, user, TRUE, null, FALSE))
			return INTERACTION_HANDLED_PASS
		to_chat(user, span_blue("You add the [C.name] into the bag."))
	if (istype(W, /obj/item/moneybag))
		var/obj/item/moneybag/C = W
		for (var/obj/O in contents_of(C))
			O.forceMove(src)
		to_chat(user, span_blue("You empty the [C.name] into the bag."))
	return INTERACTION_HANDLED_PASS


/obj/item/moneybag/vault

/obj/item/moneybag/vault/Initialize(mapload)
	. = ..()
	new /obj/item/coin/silver(src)
	new /obj/item/coin/silver(src)
	new /obj/item/coin/silver(src)
	new /obj/item/coin/silver(src)
	new /obj/item/coin/gold(src)
	new /obj/item/coin/gold(src)

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
