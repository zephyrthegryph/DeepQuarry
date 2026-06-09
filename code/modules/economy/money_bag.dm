/*****************************Money bag********************************/

/obj/item/moneybag
	icon = 'icons/obj/storage.dmi'
	name = "Money bag"
	icon_state = "moneybag"
	force = 10.0
	throwforce = 2.0
	w_class = ITEMSIZE_LARGE

/obj/item/moneybag/attack_hand(user as mob)
	// structured TGUI Moneybag (see
	// code/modules/admin/moneybag_panel.dm).
	tgui_interact(user)

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

/obj/item/moneybag/attackby(obj/item/W, mob/user)
	..()
	if (istype(W, /obj/item/coin))
		var/obj/item/coin/C = W
		to_chat(user, span_blue("You add the [C.name] into the bag."))
		user.drop_item()
		contents += C
	if (istype(W, /obj/item/moneybag))
		var/obj/item/moneybag/C = W
		for (var/obj/O in C.contents)
			contents += O;
		to_chat(user, span_blue("You empty the [C.name] into the bag."))
	return

/obj/item/moneybag/Topic(href, href_list)
	if(..())
		return 1
	usr.set_machine(src)
	src.add_fingerprint(usr)
	if(href_list["remove"])
		var/obj/item/coin/COIN
		switch(href_list["remove"])
			if(MAT_GOLD)
				COIN = locate(/obj/item/coin/gold,src.contents)
			if(MAT_SILVER)
				COIN = locate(/obj/item/coin/silver,src.contents)
			if(MAT_IRON)
				COIN = locate(/obj/item/coin/iron,src.contents)
			if(MAT_DIAMOND)
				COIN = locate(/obj/item/coin/diamond,src.contents)
			if(MAT_PHORON)
				COIN = locate(/obj/item/coin/phoron,src.contents)
			if(MAT_URANIUM)
				COIN = locate(/obj/item/coin/uranium,src.contents)
		if(!COIN)
			return
		COIN.loc = src.loc
	return



/obj/item/moneybag/vault

/obj/item/moneybag/vault/Initialize(mapload)
	. = ..()
	new /obj/item/coin/silver(src)
	new /obj/item/coin/silver(src)
	new /obj/item/coin/silver(src)
	new /obj/item/coin/silver(src)
	new /obj/item/coin/gold(src)
	new /obj/item/coin/gold(src)
