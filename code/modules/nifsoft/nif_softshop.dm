//Custom vendors
/obj/machinery/vending/nifsoft_shop
	name = "NIFSoft Shop"
	desc = "For all your mindware and mindware accessories."
	product_ads = "Let us get into your head!;Looking for an upgrade?;Surpass Humanity!;Why be normal when you can be SUPERnormal?;Jack in with NIFSoft!"

	icon = 'icons/obj/machines/ar_elements.dmi'
	icon_state = "proj"

	products = list()
	contraband = list()
	premium = list()

	density = FALSE
	opacity = 0
	var/datum/entopic/entopic

/obj/machinery/vending/nifsoft_shop/Initialize(mapload)
	. = ..()

	own_set(src, nameof(entopic), new /datum/entopic(aholder = src, aicon = icon, aicon_state = "beacon"))

MSG_DEF(nifsoft_shop/shorted, "You short out %T%'s access lock & stock restrictions.", "%U% shorts out %T%'s access lock.")

// These wires can't be hacked for contraband; an emag can (Yeees, YEEES! Give me that black market tech).
CAPABILITIES(/obj/machinery/vending/nifsoft_shop)
	configure(wires(kind = /datum/wires/vending/no_contraband))
	configure(emag(parts = then(PROC_REF(on_emag)), say = MSG(nifsoft_shop/shorted)))

/obj/machinery/vending/nifsoft_shop/ui_data(datum/act/eval/A)
	. = ..()
	.["chargesMoney"] = TRUE


/obj/machinery/vending/nifsoft_shop/power_change()
	. = ..()
	if(!entopic) return //Early APC init(), ignore
	if(has_stat(BROKEN))
		entopic.hide()
	else
		if(!has_stat(NOPOWER))
			entopic.show()
		else
			after(src, rand(0, 15), PROC_REF(lose_power))

/obj/machinery/vending/nifsoft_shop/malfunction()
	atom_break()
	entopic.hide()
	return

// Special Treatment!
/obj/machinery/vending/nifsoft_shop/build_inventory()
	//Firsties
	if(!GLOB.starting_legal_nifsoft)
		GLOB.starting_legal_nifsoft = list()
		GLOB.starting_illegal_nifsoft = list()
		for(var/datum/nifsoft/NS as anything in (subtypesof(/datum/nifsoft) - typesof(/datum/nifsoft/package)))
			if(initial(NS.vended))
				switch(initial(NS.illegal))
					if(TRUE)
						GLOB.starting_illegal_nifsoft += NS
					if(FALSE)
						GLOB.starting_legal_nifsoft += NS

	products = GLOB.starting_legal_nifsoft.Copy()
	contraband = GLOB.starting_illegal_nifsoft.Copy()

	var/list/all_products = list(
		list(products, CAT_NORMAL),
		list(contraband, CAT_HIDDEN),
		list(premium, CAT_COIN))

	for(var/current_list in all_products)
		var/category = current_list[CAT_HIDDEN]

		for(var/datum/nifsoft/NS as anything in current_list[CAT_NORMAL])
			var/applies_to = initial(NS.applies_to)
			var/context = ""
			if(!(applies_to & NIF_SYNTHETIC))
				context = " (Org Only)"
			else if(!(applies_to & NIF_ORGANIC))
				context = " (Syn Only)"
			var/name = "[initial(NS.name)][context]"
			var/datum/stored_item/vending_product/product = new/datum/stored_item/vending_product(src, NS, name)

			product.price = initial(NS.cost)
			product.amount = 10
			product.category = category
			product.item_desc = initial(NS.desc)

			own_add(src, nameof(product_records), product)

/obj/machinery/vending/nifsoft_shop/can_buy(datum/stored_item/vending_product/R, mob/user)
	. = ..()
	if(.)
		var/datum/nifsoft/path = R.item_path
		if(!ishuman(user))
			return FALSE

		var/mob/living/carbon/human/H = user
		if(!H.nif || H.nif.stat != NIF_WORKING)
			to_chat(H, span_warning("[src] seems unable to connect to your NIF..."))
			return FALSE

		if(!H.nif.can_install(path))
			flick("[icon_state]-deny", entopic.my_image)
			return FALSE

		if(initial(path.access))
			var/list/soft_access = list(initial(path.access))
			var/list/usr_access = user.GetAccess()
			if(scan_id && !has_access(soft_access, list(), usr_access) && !is_emagged(src))
				to_chat(user, span_warning("You aren't authorized to buy [initial(path.name)]."))
				flick("[icon_state]-deny", entopic.my_image)
				return FALSE

// Also special treatment!
/obj/machinery/vending/nifsoft_shop/vend(datum/stored_item/vending_product/R, mob/user)
	var/mob/living/carbon/human/H = user
	if(!can_buy(R, user))	//For SECURE VENDING MACHINES YEAH
		to_chat(user, span_warning("Purchase not allowed."))	//Unless emagged of course
		flick("[icon_state]-deny",entopic.my_image)
		return
	set_vend_ready(FALSE) //One thing at a time!!

	if(R.category & CAT_COIN)
		if(!coin)
			to_chat(user, span_notice("You need to insert a coin to get this item."))
			return
		if(coin.string_attached)
			if(prob(50))
				to_chat(user, span_notice("You successfully pull the coin out before \the [src] could swallow it."))
			else
				to_chat(user, span_notice("You weren't able to pull the coin out fast enough, the machine ate it, string and all."))
				own_clear(src, nameof(coin), OWN_DELETE)
		else
			own_clear(src, nameof(coin), OWN_DELETE)

	if(!COOLDOWN_TIMELEFT(src, reply_cooldown) && vend_reply)
		speak(vend_reply)
		COOLDOWN_START(src, reply_cooldown, vend_delay + 20 SECONDS)

	use_power(vend_power_usage)	//actuators and stuff
	after(src, vend_delay, PROC_REF(finish_nifsoft_vend), with = list(R, H, user))
	return 1

//Can't throw intangible software at people.
/obj/machinery/vending/nifsoft_shop/throw_item()
	//TODO: Make it throw disks at people with random software? That might be fun. EVEN THE ILLEGAL ONES? ;o
	return 0

/datum/wires/vending/no_contraband

/datum/wires/vending/no_contraband/on_pulse(index) //Can't hack for contraband, need emag.
	if(index != WIRE_CONTRABAND)
		..(index)

/// The emag's effect (it runs before the emagged key is set): unlock the hidden stock, or decline when it already is.
/obj/machinery/vending/nifsoft_shop/proc/on_emag(datum/act/op/A)
	if(emag_emagged(src) && (categories & CAT_HIDDEN))
		return OP_REFUSED
	set_categories(categories | CAT_HIDDEN)
	return OP_OK

/obj/machinery/vending/nifsoft_shop/proc/lose_power()
	entopic.hide()

/obj/machinery/vending/nifsoft_shop/proc/finish_nifsoft_vend(datum/stored_item/vending_product/R, mob/living/carbon/human/H, mob/user)
	R.amount--
	new R.item_path(H.nif)
	H.nif.notify("New software installed: [R.item_name]")
	flick("[icon_state]-vend",entopic.my_image)
	if(has_logs)
		do_logging(R, user, 1)

	set_vend_ready(TRUE)
	rel_clear(src, nameof(currently_vending))
