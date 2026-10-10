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

MSG_DEF(nifsoft_shop/shorted, "You short out %T%'s access lock & stock restrictions.", "%U% shorts out %T%'s access lock.")
MSG_DEF_SELF(nifsoft_shop/no_nif, "It seems unable to connect to your NIF...")
MSG_DEF_SELF(nifsoft_shop/unauthorized, "You aren't authorized to buy that software.")

CAPABILITIES(/obj/machinery/vending/nifsoft_shop)
	configure(emag(parts = then(PROC_REF(on_emag)), say = MSG(nifsoft_shop/shorted)))
	owns_one(nameof(entopic), /datum/entopic, starts = PROC_REF(make_entopic))
	// Software goes straight into the buyer's NIF: a buyer needs a working one that can take it, and the software's own access.
	extend("vend", needs(
		req(PROC_REF(nif_ready), because = MSG(nifsoft_shop/no_nif)),
		req(PROC_REF(nif_can_take), because = PROC_REF(nif_take_reason)),
		req(PROC_REF(nif_soft_access), because = MSG(nifsoft_shop/unauthorized))))

/// The projection the shop shows itself as (owned: made with the shop, deleted with it).
/obj/machinery/vending/nifsoft_shop/proc/make_entopic(datum/act/A)
	return new /datum/entopic(aholder = src, aicon = icon, aicon_state = "beacon")

/// The software the purchase names.
/obj/machinery/vending/nifsoft_shop/proc/soft_of(datum/act/op/A)
	var/datum/stored_item/vending_product/R = vend_record_of(A.args["vend"])
	return R?.item_path

/// needs: the buyer has a working NIF.
/obj/machinery/vending/nifsoft_shop/proc/nif_ready(datum/act/op/A)
	var/mob/living/carbon/human/H = A.actor
	return istype(H) && H.nif?.stat == NIF_WORKING

/// needs: the buyer's NIF can take the software.
/obj/machinery/vending/nifsoft_shop/proc/nif_can_take(datum/act/op/A)
	return isnull(nif_take_reason(A))

/// Why the buyer's NIF cannot take the software, or null.
/obj/machinery/vending/nifsoft_shop/proc/nif_take_reason(datum/act/op/A)
	var/mob/living/carbon/human/H = A.actor
	if(!istype(H) || !H.nif)
		return null
	return H.nif.install_refusal(soft_of(A))

/// needs: software with an access of its own goes only to someone with it (unless the shop is emagged or does not scan).
/obj/machinery/vending/nifsoft_shop/proc/nif_soft_access(datum/act/op/A)
	var/datum/nifsoft/path = soft_of(A)
	if(!path || !initial(path.access) || !scan_id || emag_emagged(src))
		return TRUE
	return has_access(list(initial(path.access)), list(), A.actor.GetAccess())

/// A purchase the shop turned away flashes on its projection as well.
/obj/machinery/vending/nifsoft_shop/vend_turned_away(datum/act/notice/A)
	..()
	if(A.refusal in list(/datum/msg/nif/already_installed, /datum/msg/nif/not_for_chassis, /datum/msg/nif/not_for_organics, /datum/msg/nifsoft_shop/unauthorized))
		flick("[icon_state]-deny", entopic.my_image)

/obj/machinery/vending/nifsoft_shop/ui_data(datum/act/eval/A)
	. = ..()
	.["chargesMoney"] = TRUE


/obj/machinery/vending/nifsoft_shop/power_change()
	. = ..()
	if(!entopic) return //Early APC init(), ignore
	if(broken_now())
		entopic.hide()
	else
		if(!power_lost())
			cancel_after(src, "power_loss") // power came back before the projection went out
			entopic.show()
		else
			after(src, rand(0 SECONDS, 1.5 SECONDS), PROC_REF(lose_power), key = "power_loss")

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
			product.set_amount(10)
			product.category = category
			product.item_desc = initial(NS.desc)

			rel_add(src, nameof(product_records), product)

// Also special treatment! The software is written straight into the buyer's NIF once the vend delay is over.
/obj/machinery/vending/nifsoft_shop/start_vend(datum/stored_item/vending_product/R, mob/user)
	set_vend_ready(FALSE) // One thing at a time!!
	rel_set(src, nameof(currently_vending), R)
	if(R.category & CAT_COIN)
		swallow_coin(user)
	if(!COOLDOWN_TIMELEFT(src, reply_cooldown) && vend_reply)
		speak(vend_reply)
		COOLDOWN_START(src, reply_cooldown, vend_delay + 20 SECONDS)
	use_power(vend_power_usage)	//actuators and stuff
	after(src, vend_delay, PROC_REF(finish_nifsoft_vend), key = "vend", with = list(R, user, user))

//Can't throw intangible software at people.
/obj/machinery/vending/nifsoft_shop/throw_item()
	//TODO: Make it throw disks at people with random software? That might be fun. EVEN THE ILLEGAL ONES? ;o
	return 0

/// Its wires can't be hacked for contraband; an emag can (Yeees, YEEES! Give me that black market tech).
/obj/machinery/vending/nifsoft_shop/contraband_wire_pulsed(datum/act/A)
	return

/// The emag's effect (it runs before the emagged key is set): unlock the hidden stock, or decline when it already is.
/obj/machinery/vending/nifsoft_shop/proc/on_emag(datum/act/op/A)
	if(emag_emagged(src) && (categories & CAT_HIDDEN))
		return OP_REFUSED
	set_categories(categories | CAT_HIDDEN)
	return OP_OK

/obj/machinery/vending/nifsoft_shop/proc/lose_power()
	entopic.hide()

/obj/machinery/vending/nifsoft_shop/proc/finish_nifsoft_vend(datum/stored_item/vending_product/R, mob/living/carbon/human/H, mob/user)
	R.set_amount(R.amount - 1)
	new R.item_path(H.nif)
	H.nif.notify("New software installed: [R.item_name]")
	flick("[icon_state]-vend",entopic.my_image)
	if(has_logs)
		do_logging(R, user, 1)

	set_vend_ready(TRUE)
	rel_clear(src, nameof(currently_vending))
