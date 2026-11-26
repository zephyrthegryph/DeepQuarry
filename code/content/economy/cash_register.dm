/obj/machinery/cash_register
	name = "cash register"
	desc = "Swipe your ID card to make purchases electronically."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "register_idle"
	flags = NOBLUDGEON
	req_access = list(ACCESS_HEADS)
	anchored = TRUE

	var/cash_locked = 1
	var/cash_open = 0
	var/cash_stored = 0
	var/account_to_connect = null
	/// The ticket, the sale and the window's buttons: one till the register owns.
	var/datum/till/register/till

// Claim machine ID
REGISTRY_MEMBERSHIP(/obj/machinery/cash_register, REGISTRY_TRANSACTION_DEVICES)

/obj/machinery/cash_register/proc/set_up_register(datum/act/timer/A)
	till.assign_machine_id()
	set_cash_stored(rand(10, 70)*10)
	if(GLOB.economy_init && account_to_connect)
		till.link_provider(GLOB.department_accounts[account_to_connect])

/obj/machinery/cash_register/examine(mob/user)
	. = ..(user)
	var/pending = till.pending_text()
	if(pending)
		. += pending
	if(cash_open)
		if(cash_stored)
			. += "It holds [cash_stored] Thaler\s."
		else
			. += "It's completely empty."

/obj/machinery/cash_register/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	// Don't be accessible from the wrong side of the machine
	if(get_dir(src, user) & GLOB.reverse_dir[src.dir])
		return OP_OK

	if(cash_open)
		if(cash_stored)
			spawn_money(cash_stored, loc, user)
			set_cash_stored(0)
			return OP_OK
		open_cash_box(user)
		return OP_OK
	tgui_interact(user)
	return OP_OK

/obj/machinery/cash_register/proc/interaction_open_box_alt(datum/act/op/A)
	var/mob/user = A.actor
	open_cash_box(user)
	return OP_OK

/**
 * Old attackby: paying methods (ID/e-wallet/cash) or a price scan for anything else. An emag
 * declined (returns FALSE) so dispatch falls through to `..()`, exactly as the old
 * `else if(istype(O, /obj/item/card/emag)) return ..()` branch did.
 */

/obj/machinery/cash_register/proc/interaction_pay(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	// Check for a method of paying (ID, PDA, e-wallet, cash, ect.)
	var/obj/item/card/id/I = O.GetID()
	if(I)
		till.scan_card(I, O, user)
	else if (istype(O, /obj/item/spacecash/ewallet))
		var/obj/item/spacecash/ewallet/E = O
		till.scan_wallet(E, user)
	else if (istype(O, /obj/item/spacecash))
		var/obj/item/spacecash/SC = O
		if(cash_open)
			to_chat(user, "You neatly sort the cash into the box.")
			set_cash_stored(cash_stored + SC.worth)
			if(ishuman(user))
				var/mob/living/carbon/human/H = user
				H.drop_from_inventory(SC)
			consume(SC, user)
		else
			till.scan_cash(SC, user)
	else if(istype(O, /obj/item/card/emag))
		return OP_DECLINE
	// Not paying: Look up price and add it to transaction_amount
	else
		till.scan_item_price(O, user)
	return OP_OK

/obj/machinery/cash_register/draw(datum/look/look)
	..()
	look.overlay("register_approve", when = cash_open)
	look.overlay("register_open", when = cash_open)
	look.overlay("register_cash", when = cash_open && cash_stored)

CAPABILITIES(/obj/machinery/cash_register)
	owns_one(nameof(till), starts = /datum/till/register)
	after_init(0, then(PROC_REF(set_up_register)))
	interface("RetailScanner", forwards = nameof(till))
	ui_shape(cash_locked = bool())
	without("ui_open")
	op("toggle_cash_lock", ui_act("toggle_cash_lock"), then(PROC_REF(ui_act_toggle_cash_lock)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), claims(), begins(PROC_REF(wrench_begins)), wait(2 SECONDS), then(PROC_REF(wrench_used)))
	op("cash_register_pay", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Pay / scan"), then(PROC_REF(interaction_pay)))
	op("cash_register_open_box_alt", hand(), ungated(), gesture(GESTURE_ALT), priority(OP_PRIORITY_DEFAULT - 1), label("Open cash box"), then(PROC_REF(interaction_open_box_alt)))
	op("cash_register_use", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_use)))
	op("cash_register_open_box_verb", menu(), label("Open Cash Box"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_open_box_verb)))
	op("cash_register_drop", item(/obj), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT - 1), label("Put on the register"), then(PROC_REF(interaction_drop)))
	emag(then(PROC_REF(on_emag)), powered = FALSE)

/// /obj/machinery/cash_register's window data; the till adds the ticket's.
/obj/machinery/cash_register/ui_data(datum/act/eval/A)
	return list("cash_locked" = cash_locked)

/obj/machinery/cash_register/proc/ui_act_toggle_cash_lock(datum/act/op/A)
	if(till.locked)
		return FALSE
	set_cash_locked(!cash_locked)

/obj/machinery/cash_register/proc/wrench_begins(datum/act/op/A)
	return msg_text(anchored ? "You begin unsecuring [src] from the floor." : "You begin securing [src] to the floor.", anchored ? "[A.actor] begins unsecuring [src] from the floor." : "[A.actor] begins securing [src] to the floor.")

/obj/machinery/cash_register/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	if(!anchored)
		act_message(user, src, MSG_SELF(span_notice("You have secured %T% to the floor.")), MSG_OTHERS(span_notice("%U% has secured %T% to the floor.")))
	else
		act_message(user, src, MSG_SELF(span_notice("You have unsecured %T% from the floor.")), \
			MSG_OTHERS(span_warning("%U% has unsecured %T% from the floor.")))
	set_anchored(!anchored)
	return OP_OK

/obj/machinery/cash_register/proc/interaction_drop(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/dropping = A.held
	if(Adjacent(dropping) && Adjacent(user) && !user.stat)
		attackby(dropping, user)
	return OP_OK

/obj/machinery/cash_register/proc/interaction_open_box_verb(datum/act/op/A)
	var/mob/user = A.actor
	open_cash_box(user)
	return TRUE

/obj/machinery/cash_register/proc/open_cash_box(mob/user)
	if(user.stat) return

	if(cash_open)
		set_cash_open(0)
	else if(!cash_locked)
		set_cash_open(1)
	else
		to_chat(user, span_warning("The cash box is locked."))

/obj/machinery/cash_register/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, others = span_danger("%T%'s cash box springs open as %U% swipes the card through the scanner!"))
	play_sfx(src, SFX_SPARKS)
	set_req_access(list())
	set_emagged(1)
	till.set_locked(FALSE)
	set_cash_locked(0)
	open_cash_box(user)
	return OP_OK

//--Premades--//

/obj/machinery/cash_register/command
	account_to_connect = "Command"

/obj/machinery/cash_register/medical
	account_to_connect = "Medical"

/obj/machinery/cash_register/engineering
	account_to_connect = "Engineering"

/obj/machinery/cash_register/science
	account_to_connect = DEPARTMENT_RESEARCH

/obj/machinery/cash_register/security
	account_to_connect = "Security"

/obj/machinery/cash_register/cargo
	account_to_connect = "Cargo"

/obj/machinery/cash_register/civilian
	account_to_connect = "Civilian"
