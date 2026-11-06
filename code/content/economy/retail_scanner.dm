/obj/item/retail_scanner
	name = "retail scanner"
	desc = "Swipe your ID card to make purchases electronically."
	icon = 'icons/obj/device.dmi'
	icon_state = "retail_idle"
	flags = NOBLUDGEON
	req_access = list(ACCESS_HEADS)
	w_class = ITEMSIZE_SMALL

	var/emagged = 0
	var/account_to_connect = null
	/// The ticket, the sale and the window's buttons: one till the scanner owns.
	var/datum/till/till
	var/list/freight_form_paper

// Claim machine ID
REGISTRY_MEMBERSHIP(/obj/item/retail_scanner, REGISTRY_TRANSACTION_DEVICES)

/obj/item/retail_scanner/proc/set_up_scanner(datum/act/timer/A)
	till.assign_machine_id()
	if(locate_within(loc, /obj/structure/table))
		set_pixel_y(3)
	if(GLOB.economy_init && account_to_connect)
		till.link_provider(GLOB.department_accounts[account_to_connect])

// Always face the user when put on a table
/obj/item/retail_scanner/afterattack(atom/movable/AM, mob/user, proximity)
	if(!proximity)	return
	if(istype(AM, /obj/structure/table))
		set_pixel_y(3) // Shift it up slightly to look better on table
		set_dir(get_dir(src, user))
	else if(istype(AM, /obj/structure/closet/crate))
		var/obj/structure/closet/crate/crate = AM
		certify_freight_crate(crate, user)
	else
		till.scan_item_price(AM, user)

// Reset dir when picked back up
/obj/item/retail_scanner/pickup(mob/user)
	set_dir(SOUTH)
	set_pixel_y(0)

CAPABILITIES(/obj/item/retail_scanner)
	owns_one(nameof(till), starts = /datum/till)
	configure(item_worn(slots = SLOT_BELT))
	after_init(0, then(PROC_REF(set_up_scanner)))
	op("controls", in_hand(), label("Open retail scanner"), then(PROC_REF(retail_scanner_controls_opened)))
	interface("RetailScanner", forwards = nameof(till))
	without("ui_open")
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Alternate use"), then(PROC_REF(interaction_alt)))
	emag(then(PROC_REF(on_emag)), powered = FALSE)
	ref_many(nameof(freight_form_paper))

/obj/item/retail_scanner/proc/retail_scanner_controls_opened(datum/act/op/A)
	var/mob/user = A.actor
	tgui_interact(user)
	return OP_OK

/// Old click_alt.
/obj/item/retail_scanner/proc/interaction_alt(datum/act/op/A)
	var/mob/user = A.actor
	if(Adjacent(user))
		tgui_interact(user)
	return TRUE

/obj/item/retail_scanner/examine(mob/user)
	. = ..()
	var/pending = till.pending_text()
	if(pending)
		. += pending
	. += "Its freight printer contains [length(freight_form_paper)] blank sheet\s. Use it on a closed crate to certify a shipment."

/// Old attackby.
/obj/item/retail_scanner/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/O = A.held
	if(istype(O, /obj/item/paper))
		var/obj/item/paper/form = O
		if(form.info || form.shipping_ledger_data)
			to_chat(user, span_warning("The freight printer accepts only blank ordinary paper."))
			return OP_PASS
		if(!user.drop_from_inventory(form, src))
			return OP_PASS
		rel_add(src, nameof(freight_form_paper), form)
		to_chat(user, span_notice("You load [form] into [src]'s freight printer."))
		return OP_PASS
	// Check for a method of paying (ID, PDA, e-wallet, cash, ect.)
	var/obj/item/card/id/I = O.GetID()
	if(I)
		till.scan_card(I, O, user)
	else if (istype(O, /obj/item/spacecash/ewallet))
		var/obj/item/spacecash/ewallet/E = O
		till.scan_wallet(E, user)
	else if (istype(O, /obj/item/spacecash))
		to_chat(user, span_warning("This device does not accept cash."))

	else if(istype(O, /obj/item/card/emag))
		return OP_DECLINE
	// Not paying: Look up price and add it to transaction_amount
	else
		till.scan_item_price(O, user)
	return OP_PASS

/obj/item/retail_scanner/showoff(mob/user)
	for (var/mob/M in view(user))
		M.show_message("[user] holds up [src]. <a HREF='byond://?src=[REF(M)];clickitem=[REF(src)]'>Swipe card or item.</a>",1)

/obj/item/retail_scanner/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_danger("You stealthily swipe the cryptographic sequencer through \the [src]."))
	play_sfx(src, SFX_SPARKS)
	set_req_access(list())
	emagged = 1
	return OP_OK

//--Premades--//

/obj/item/retail_scanner/command
	account_to_connect = "Command"

/obj/item/retail_scanner/medical
	account_to_connect = "Medical"

/obj/item/retail_scanner/engineering
	account_to_connect = "Engineering"

/obj/item/retail_scanner/service
	name = "service sales scanner"
	account_to_connect = DEPARTMENT_CIVILIAN

/obj/item/retail_scanner/science
	name = "research sales scanner"
	desc = "A departmental checkout scanner for selling R&D prototypes and other Research products to crewmembers."
	account_to_connect = DEPARTMENT_RESEARCH

/obj/item/retail_scanner/security
	account_to_connect = "Security"

/obj/item/retail_scanner/cargo
	name = "cargo sales scanner"
	desc = "A departmental checkout scanner for selling materials, imports, and Cargo stock to crewmembers."
	account_to_connect = "Cargo"

/obj/item/retail_scanner/civilian
	account_to_connect = "Civilian"
