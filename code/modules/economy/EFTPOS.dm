/// Maximum value a single EFTPOS transaction may be set to. Prevents overflow/abuse.
#define EFTPOS_MAX_TRANSACTION 1000000

/obj/item/eftpos
	name = "\improper EFTPOS scanner"
	desc = "Swipe your ID card to make purchases electronically."
	icon = 'icons/obj/device.dmi'
	icon_state = "eftpos"
	var/machine_id = ""
	var/eftpos_name = "Default EFTPOS scanner"
	var/transaction_locked = 0
	var/transaction_paid = 0
	var/transaction_amount = 0
	var/transaction_purpose = "Default charge"
	var/access_code = 0
	var/tmp/datum/money_account/linked_account
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

/obj/item/eftpos/Initialize(mapload)
	. = ..()
	//by default, connect to the station account
	//the user of the EFTPOS device can change the target account though, and no-one will be the wiser (except whoever's being charged)
	rel_set(src, nameof(linked_account), GLOB.station_account)

	machine_id = "[station_name()] EFTPOS #[GLOB.num_financial_terminals++]"
	access_code = rand(1111,111111)
	print_reference()

	//create a short manual as well
	var/obj/item/paper/R = new(src.loc)
	R.name = "Steps to success: Correct EFTPOS Usage"
	//Temptative new manual:
	R.info += span_bold("First EFTPOS setup:") + "<br>"
	R.info += "1. Memorise your EFTPOS command code (provided with all EFTPOS devices).<br>"
	R.info += "2. Connect the EFTPOS to the account in which you want to receive the funds.<br><br>"
	R.info += span_bold("When starting a new transaction:") + "<br>"
	R.info += "1. Enter the amount of money you want to charge and a purpose message for the new transaction.<br>"
	R.info += "2. Lock the new transaction. If you want to modify or cancel the transaction, you simply have to reset your EFTPOS device.<br>"
	R.info += "3. Give the EFTPOS device to your customer, he/she must finish the transaction by swiping their ID card or a charge card with enough funds.<br>"
	R.info += "4. If everything is done correctly, the money will be transferred. To unlock the device you will have to reset the EFTPOS device.<br>"

	//stamp the paper
	var/image/stampoverlay = image('icons/obj/bureaucracy.dmi')
	stampoverlay.icon_state = "paper_stamp-cent"
	if(!R.stamped)
		R.stamped = new
	R.offset_x += 0
	R.offset_y += 0
	LAZYADD(R.ico, "paper_stamp-cent")
	R.stamped += /obj/item/stamp
	R.add_overlay(stampoverlay)
	R.stamps += "<HR><i>This paper has been stamped by the EFTPOS device.</i>"

/obj/item/eftpos/proc/print_reference()
	var/obj/item/paper/R = new(src.loc)
	R.name = "Reference: [eftpos_name]"
	R.info = span_bold("[eftpos_name] reference") + "<br><br>"
	R.info += "Access code: [access_code]<br><br>"
	R.info += span_bold("Do not lose or misplace this code.") + "<br>"

	//stamp the paper
	var/image/stampoverlay = image('icons/obj/bureaucracy.dmi')
	stampoverlay.icon_state = "paper_stamp-cent"
	if(!R.stamped)
		R.stamped = new
	R.stamped += /obj/item/stamp
	R.add_overlay(stampoverlay)
	R.stamps += "<HR><i>This paper has been stamped by the EFTPOS device.</i>"
	var/obj/item/smallDelivery/D = new(R.loc)
	own_set(D, nameof(D.wrapped), R, into = TRUE)
	D.name = "small parcel - 'EFTPOS access code'"

// TGUI migration. attack_self opens Eftpos.tsx; the
// Topic switch is converted to tgui_act below.
DECLARE_INTERACTIONS(/obj/item/eftpos, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/eftpos/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(get_dist(src, user) > 1)
		SStgui.close_uis(src)
		return TRUE
	tgui_interact(user)
	return TRUE

DECLARE_UI(/obj/item/eftpos, "Eftpos", UI_TITLE("EFTPOS scanner"))

UI_DATA_REPLACE(/obj/item/eftpos, "eftpos_name:text", "machine_id:text", "transaction_purpose:text", "transaction_amount:num", "merge:ui_data_obj_item_eftpos{transaction_locked:bool,transaction_paid:bool,linked_account_name:text}")

/// The computed part of /obj/item/eftpos's window data (declared on its UI_DATA row).
/obj/item/eftpos/proc/ui_data_obj_item_eftpos(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["transaction_locked"] = !!transaction_locked
	data["transaction_paid"] = !!transaction_paid
	data["linked_account_name"] = linked_account() ? linked_account().owner_name : ""
	return data

/// Old attackby.
/obj/item/eftpos/proc/interaction_item(mob/user, obj/item/O, datum/interaction/interaction)

	var/obj/item/card/id/I = O.GetID()

	if(I)
		if(linked_account())
			scan_card(I, O)
		else
			to_chat(user, "[icon2html(src, user.client)]" + span_warning("Unable to connect to linked account."))
	else if (istype(O, /obj/item/spacecash/ewallet))
		var/obj/item/spacecash/ewallet/E = O
		if (linked_account())
			if(!linked_account().suspended)
				if(transaction_locked && !transaction_paid)
					if(transaction_amount <= 0 || transaction_amount > EFTPOS_MAX_TRANSACTION)
						to_chat(user, "[icon2html(src, user.client)]" + span_warning("Invalid transaction amount."))
					else if(transaction_amount <= E.worth)
						play_sfx(src, SFX_MACHINES_CHIME)
						src.visible_message("[icon2html(src,viewers(src))] \The [src] chimes.")
						transaction_paid = 1

						E.worth -= transaction_amount
						linked_account().credit(transaction_amount, E.owner_name, transaction_purpose || "None supplied.", machine_id)
					else
						to_chat(user, "[icon2html(src, user.client)]" + span_warning("\The [O] doesn't have that much money!"))
			else
				to_chat(user, "[icon2html(src, user.client)]" + span_warning("Connected account has been suspended."))
		else
			to_chat(user, "[icon2html(src, user.client)]" + span_warning("EFTPOS is not connected to an account."))

	else
		return FALSE
	return INTERACTION_HANDLED_PASS

// Topic switch lifted into tgui_act with stable action names.
UI_ACT(/obj/item/eftpos, "change_code", ui_act_change_code)
UI_ACT_PROC(/obj/item/eftpos, ui_act_change_code)
	var/attempt_code = act_ask(usr, action, params, ui, "k147", /datum/om/prompt/number, message = "Re-enter the current EFTPOS access code", title = "Confirm old EFTPOS code")
	if(isnull(attempt_code))
		return
	if(attempt_code == access_code)
		var/trycode = act_ask(usr, action, params, ui, "k149", /datum/om/prompt/number, message = "Enter a new access code for this device (4-6 digits, numbers only)", title = "Enter new EFTPOS code", max = 999999, min = 1000)
		if(isnull(trycode))
			return
		if(trycode >= 1000 && trycode <= 999999)
			access_code = trycode
		else
			tgui_alert_async(usr, "That is not a valid code!")
		print_reference()
	else
		to_chat(usr, "[icon2html(src, usr.client)]" + span_warning("Incorrect code entered."))
	return TRUE

UI_ACT(/obj/item/eftpos, "change_id", ui_act_change_id)
UI_ACT_PROC(/obj/item/eftpos, ui_act_change_id)
	var/attempt_code = act_ask(usr, action, params, ui, "k159", /datum/om/prompt/number, message = "Re-enter the current EFTPOS access code", title = "Confirm EFTPOS code")
	if(isnull(attempt_code))
		return
	if(attempt_code == access_code)
		var/_answer_k161 = act_ask(usr, action, params, ui, "k161", /datum/om/prompt/text, message = "Enter a new terminal ID for this device", title = "Enter new EFTPOS ID", max_length = MAX_NAME_LEN)
		if(isnull(_answer_k161))
			return
		eftpos_name = _answer_k161 + " EFTPOS scanner"
		print_reference()
	else
		to_chat(usr, "[icon2html(src, usr.client)]" + span_warning("Incorrect code entered."))
	return TRUE

UI_ACT(/obj/item/eftpos, "link_account", ui_act_link_account)
UI_ACT_PROC(/obj/item/eftpos, ui_act_link_account)
	var/attempt_account_num = act_ask(usr, action, params, ui, "k167", /datum/om/prompt/number, message = "Enter account number to pay EFTPOS charges into", title = "New account number")
	if(isnull(attempt_account_num))
		return
	var/attempt_pin = act_ask(usr, action, params, ui, "k168", /datum/om/prompt/number, message = "Enter pin code", title = "Account pin")
	if(isnull(attempt_pin))
		return
	rel_set(src, nameof(/obj/item/eftpos::linked_account), attempt_account_access(attempt_account_num, attempt_pin, 1))
	if(linked_account())
		if(linked_account().suspended)
			rel_clear(src, nameof(/obj/item/eftpos::linked_account))
			to_chat(usr, "[icon2html(src, usr.client)]" + span_warning("Account has been suspended."))
	else
		to_chat(usr, "[icon2html(src, usr.client)]" + span_warning("Account not found."))
	return TRUE

UI_ACT(/obj/item/eftpos, "trans_purpose", ui_act_trans_purpose)
UI_ACT_PROC(/obj/item/eftpos, ui_act_trans_purpose)
	var/choice = act_ask(usr, action, params, ui, "k178", /datum/om/prompt/text, message = "Enter reason for EFTPOS transaction", title = "Transaction purpose")
	if(isnull(choice))
		return
	if(choice)
		transaction_purpose = choice
	return TRUE

UI_ACT(/obj/item/eftpos, "trans_value", ui_act_trans_value)
UI_ACT_PROC(/obj/item/eftpos, ui_act_trans_value)
	var/try_num = act_ask(usr, action, params, ui, "k183", /datum/om/prompt/number, message = "Enter amount for EFTPOS transaction", title = "Transaction amount")
	if(isnull(try_num))
		return
	if(!isnum(try_num) || try_num <= 0 || try_num > EFTPOS_MAX_TRANSACTION)
		tgui_alert_async(usr, "That is not a valid amount!")
	else
		transaction_amount = round(try_num)
	return TRUE

UI_ACT(/obj/item/eftpos, "toggle_lock", ui_act_toggle_lock)
UI_ACT_PROC(/obj/item/eftpos, ui_act_toggle_lock)
	if(transaction_locked)
		if(transaction_paid)
			transaction_locked = 0
			transaction_paid = 0
		else
			var/attempt_code = act_ask(usr, action, params, ui, "k195", /datum/om/prompt/number, message = "Enter EFTPOS access code", title = "Reset Transaction")
			if(isnull(attempt_code))
				return
			if(attempt_code == access_code)
				transaction_locked = 0
				transaction_paid = 0
	else if(linked_account())
		transaction_locked = 1
	else
		to_chat(usr, "[icon2html(src, usr.client)]" + span_warning("No account connected to send transactions to."))
	return TRUE

UI_ACT(/obj/item/eftpos, "scan_card", ui_act_scan_card)
UI_ACT_PROC(/obj/item/eftpos, ui_act_scan_card)
	if(linked_account())
		var/obj/item/I = usr.get_active_hand()
		if(istype(I, /obj/item/card))
			scan_card(I)
	else
		to_chat(usr, "[icon2html(src, usr.client)]" + span_warning("Unable to link accounts."))
	return TRUE

UI_ACT(/obj/item/eftpos, "reset", ui_act_reset)
UI_ACT_PROC(/obj/item/eftpos, ui_act_reset)
	var/obj/item/I = usr.get_active_hand()
	if(istype(I, /obj/item/card))
		var/obj/item/card/id/C = I
		if((ACCESS_CENT_CAPTAIN in C.access) || (ACCESS_HOP in C.access) || (ACCESS_CAPTAIN in C.access))
			access_code = 0
			to_chat(usr, "[icon2html(src, usr.client)]" + span_info("Access code reset to 0."))
	else if(istype(I, /obj/item/card/emag))
		access_code = 0
		to_chat(usr, "[icon2html(src, usr.client)]" + span_info("Access code reset to 0."))
	return TRUE

/obj/item/eftpos/proc/scan_card(obj/item/card/I, obj/item/ID_container)
	if (istype(I, /obj/item/card/id))
		var/obj/item/card/id/C = I
		if(I==ID_container || ID_container == null)
			act_message(usr, src, others = span_info("%U% swipes a card through %T%."))
		else
			act_message(usr, src, others = span_info("%U% swipes %I% through %T%."), item = ID_container)
		if(transaction_locked && !transaction_paid)
			if(linked_account())
				if(!linked_account().suspended)
					// Snapshot the authoritative amount before any sleeping input; the
					// transaction can't be silently re-priced while the PIN dialog is open.
					var/charge_amount = transaction_amount
					if(charge_amount <= 0 || charge_amount > EFTPOS_MAX_TRANSACTION)
						to_chat(usr, "[icon2html(src, usr.client)]" + span_warning("Invalid transaction amount."))
						return
					var/mob/swiper = usr
					var/attempt_pin = ""
					var/datum/money_account/D = get_account(C.associated_account_number)
					if(D.security_level)
						var/_answer_k244 = rerun_ask(usr, "k244", PROC_REF(scan_card), args, /datum/om/prompt/number, message = "Enter pin code", title = "EFTPOS transaction")
						if(isnull(_answer_k244))
							return
						attempt_pin = _answer_k244
						D = null
						// Re-validate card presence/adjacency and transaction state after the sleep.
						if(QDELETED(C) || QDELETED(src) || !swiper || !(C in swiper) || !swiper.Adjacent(src))
							return
						if(!transaction_locked || transaction_paid || charge_amount != transaction_amount)
							return
					D = attempt_account_access(C.associated_account_number, attempt_pin, 2)
					if(D)
						if(!D.suspended)
							if(charge_amount <= D.money)
								play_sfx(src, SFX_MACHINES_CHIME)
								src.visible_message("[icon2html(src,viewers(src))] \The [src] chimes.")
								transaction_paid = 1

								if(!transfer_account_funds(D, linked_account(), charge_amount, transaction_purpose, machine_id))
									transaction_paid = 0
									return
							else
								to_chat(usr, "[icon2html(src, usr.client)]" + span_warning("You don't have that much money!"))
						else
							to_chat(usr, "[icon2html(src, usr.client)]" + span_warning("Your account has been suspended."))
					else
						to_chat(usr, "[icon2html(src, usr.client)]" + span_warning("Unable to access account. Check security settings and try again."))
				else
					to_chat(usr, "[icon2html(src, usr.client)]" + span_warning("Connected account has been suspended."))
			else
				to_chat(usr, "[icon2html(src, usr.client)]" + span_warning("EFTPOS is not connected to an account."))
	else if (istype(I, /obj/item/card/emag))
		if(transaction_locked)
			if(transaction_paid)
				to_chat(usr, "[icon2html(src, usr.client)]" + span_info("You stealthily swipe \the [I] through \the [src]."))
				transaction_locked = 0
				transaction_paid = 0
			else
				act_message(usr, src, others = span_info("%U% swipes a card through %T%."))
				play_sfx(src, SFX_MACHINES_CHIME)
				src.visible_message("[icon2html(src,viewers(src))] \The [src] chimes.")
				transaction_paid = 1

	//emag?

#undef EFTPOS_MAX_TRANSACTION

/// the linked_account this refers to (a relation view: null once it is deleted).
/obj/item/eftpos/proc/linked_account() as /datum/money_account
	return linked_account
