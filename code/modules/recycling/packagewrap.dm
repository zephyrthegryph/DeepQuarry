/obj/item/packageWrap
	name = "package wrapper"
	desc = "Like wrapping paper, but less festive."
	icon = 'icons/obj/items.dmi'
	icon_state = "deliveryPaper"
	w_class = ITEMSIZE_NORMAL
	var/amount = 25.0
	drop_sound = SFX_ITEMS_DROP_WRAPPER

/obj/item/packageWrap/afterattack(obj/target, mob/user, proximity)
	if(!proximity) return
	if(!istype(target))	//this really shouldn't be necessary (but it is).	-Pete
		return
	if(istype(target, /obj/item/smallDelivery) || istype(target,/obj/structure/bigDelivery) \
	|| istype(target, /obj/item/gift) || istype(target, /obj/item/evidencebag))
		return
	if(target.anchored)
		return
	if(!isturf(target.loc)) //no wrapping things inside other things, just breaks things, put it on the ground first.
		return
	if(user in target) //no wrapping closets that you are inside - it's not physically possible
		return

	add_attack_logs(user, target, "has been wrapped with [src]")

	if (istype(target, /obj/item) && !(istype(target, /obj/item/storage) && !istype(target,/obj/item/storage/box)))
		var/obj/item/O = target
		if (src.amount < 1)
			to_chat(user, span_warning("You need more paper."))
			return
		var/obj/item/smallDelivery/P = new /obj/item/smallDelivery(get_turf(O.loc))	//Aaannd wrap it up!
		if(!move_into(P, nameof(P.wrapped), O, user)) // out of a hand or bag: its HUD clears
			consumed(P, src)
			return
		P.w_class = O.w_class
		var/i = round(O.w_class)
		if(i in list(1,2,3,4,5))
			P.icon_state = "deliverycrate[i]"
			switch(i)
				if(1) P.name = "tiny parcel"
				if(3) P.name = "normal-sized parcel"
				if(4) P.name = "large parcel"
				if(5) P.name = "huge parcel"
		if(i < 1)
			P.icon_state = "deliverycrate1"
			P.name = "tiny parcel"
		if(i > 5)
			P.icon_state = "deliverycrate5"
			P.name = "huge parcel"
		P.add_fingerprint(user)
		O.add_fingerprint(user)
		src.add_fingerprint(user)
		src.amount -= 1
		wrap_used()
		act_message(user, target, MSG_SELF(span_notice("You wrap %T%, leaving [amount] units of paper on \the [src].")), \
			MSG_OTHERS("%U% wraps %T% with \a [src]."), \
			MSG_BLIND("You hear someone taping paper around a small object."))
		play_sfx(src, SFX_ITEMS_PACKAGE_WRAP)

	else if (istype(target, /obj/structure/closet/crate))
		var/obj/structure/closet/crate/O = target
		if (src.amount < 3)
			to_chat(user, span_warning("You need more paper."))
			return
		if(O.opened)
			return
		var/obj/structure/bigDelivery/P = new /obj/structure/bigDelivery(get_turf(O.loc))
		P.icon_state = "deliverycrate"
		rel_set(P, nameof(P.wrapped), O)
		O.forceMove(P)
		src.amount -= 3
		wrap_used()
		act_message(user, target, MSG_SELF(span_notice("You wrap %T%, leaving [amount] units of paper on \the [src].")), \
			MSG_OTHERS("%U% wraps %T% with \a [src]."), \
			MSG_BLIND("You hear someone taping paper around a large object."))
		play_sfx(src, SFX_ITEMS_PACKAGE_WRAP)

	else if (istype (target, /obj/structure/closet))
		var/obj/structure/closet/O = target
		if (src.amount < 3)
			to_chat(user, span_warning("You need more paper."))
			return
		if(O.opened)
			return
		var/obj/structure/bigDelivery/P = new /obj/structure/bigDelivery(get_turf(O.loc))
		rel_set(P, nameof(P.wrapped), O)
		set_welded(O, TRUE)
		O.forceMove(P)
		src.amount -= 3
		wrap_used()
		act_message(user, target, MSG_SELF(span_notice("You wrap %T%, leaving [amount] units of paper on \the [src].")), \
			MSG_OTHERS("%U% wraps %T% with \a [src]."), \
			MSG_BLIND("You hear someone taping paper around a large object."))
		play_sfx(src, SFX_ITEMS_PACKAGE_WRAP)

	else
		to_chat(user, span_blue("The object you are trying to wrap is unsuitable for the sorting machinery!"))

	if (src.amount <= 0 && !isrobot(loc))
		replace_with(src, /obj/item/c_tube)

/obj/item/packageWrap/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 0)
		. += span_blue("There are [amount] units of package wrap left!")

// Borg version that refills over time
/obj/item/packageWrap/borg
	name = "packaging dispenser"
	desc = "Wraps various items so they can be tagged and shipped through disposals. Refills over time."
	var/recharge_ticker = 0
	/// TRUE while the dispenser is short (wrap_used() sets it): the slow step refills it; full, it parks.
	var/tmp/refilling = FALSE
TRACKED(/obj/item/packageWrap/borg, refilling)

CAPABILITIES(/obj/item/packageWrap/borg)
	every(2 SECONDS, then(PROC_REF(refill_step)), when = nameof(refilling))

/// Refills one sheet per 12 s while short.
/obj/item/packageWrap/borg/proc/refill_step(datum/act/A)
	if(amount >= initial(amount))
		recharge_ticker = 0
		set_refilling(FALSE)
		return
	if(recharge_ticker < 5)
		recharge_ticker ++
		return

	recharge_ticker = 0
	if(amount < initial(amount))
		amount++

/// Called when wrap is used up. A borg dispenser refills over time from here.
/obj/item/packageWrap/proc/wrap_used()
	return

/obj/item/packageWrap/borg/wrap_used()
	set_refilling(TRUE)
