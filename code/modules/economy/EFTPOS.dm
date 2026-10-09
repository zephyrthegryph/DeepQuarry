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
	if(!R.stamped)
		R.stamped = new
	R.add_stamp_mark("paper_stamp-cent", 0, 0)
	R.stamped += /obj/item/stamp
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
	move_into(D, nameof(D.wrapped), R)
	D.name = "small parcel - 'EFTPOS access code'"

// TGUI migration. attack_self opens Eftpos.tsx; the
// Topic switch is converted to tgui_act below.

/// Old attack_self.
/obj/item/eftpos/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(get_dist(src, user) > 1)
		SStgui.close_uis(src)
		return TRUE
	tgui_interact(user)
	return TRUE

CAPABILITIES(/obj/item/eftpos)
	interface("Eftpos", title = "EFTPOS scanner")
	without("ui_open")
	op("change_code", ui_act("change_code"), then(PROC_REF(ui_act_change_code)))
	op("change_id", ui_act("change_id"), then(PROC_REF(ui_act_change_id)))
	op("link_account", ui_act("link_account"), then(PROC_REF(ui_act_link_account)))
	op("trans_purpose", ui_act("trans_purpose"), then(PROC_REF(ui_act_trans_purpose)))
	op("trans_value", ui_act("trans_value"), then(PROC_REF(ui_act_trans_value)))
	op("toggle_lock", ui_act("toggle_lock"), then(PROC_REF(ui_act_toggle_lock)))
	op("scan_card", ui_act("scan_card"), then(PROC_REF(ui_act_scan_card)))
	op("reset", ui_act("reset"), then(PROC_REF(ui_act_reset)))
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/obj/item/eftpos/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["eftpos_name"] = eftpos_name
	data["machine_id"] = machine_id
	data["transaction_purpose"] = transaction_purpose
	data["transaction_amount"] = transaction_amount
	var/list/merged_1 = ui_data_obj_item_eftpos(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/eftpos's window data.
/obj/item/eftpos/proc/ui_data_obj_item_eftpos(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["transaction_locked"] = !!transaction_locked
	data["transaction_paid"] = !!transaction_paid
	data["linked_account_name"] = linked_account() ? linked_account().owner_name : ""
	return data

/// Old attackby.
/obj/item/eftpos/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held

	var/obj/item/card/id/I = O.GetID()

	if(I)
		if(linked_account())
			scan_card(I, O, user)
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

						E.set_worth(E.worth - transaction_amount)
						linked_account().credit(transaction_amount, E.owner_name, transaction_purpose || "None supplied.", machine_id)
					else
						to_chat(user, "[icon2html(src, user.client)]" + span_warning("\The [O] doesn't have that much money!"))
			else
				to_chat(user, "[icon2html(src, user.client)]" + span_warning("Connected account has been suspended."))
		else
			to_chat(user, "[icon2html(src, user.client)]" + span_warning("EFTPOS is not connected to an account."))

	else
		return OP_DECLINE
	return OP_PASS

// Topic switch lifted into tgui_act with stable action names.
/obj/item/eftpos/proc/ui_act_change_code(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	return eftpos_change_code_stage(user, ui, list())

/obj/item/eftpos/proc/eftpos_change_code_stage(mob/user, datum/tgui/ui, list/eftpos_answers)
	if(!("k147" in eftpos_answers))
		open_request(src, /datum/prompt/number/eftpos_settings, PROC_REF(eftpos_settings_number_answered), answerer = user, eftpos_ui = ui, eftpos_answers = eftpos_answers, eftpos_action = "change_code", eftpos_key = "k147", eftpos_stage = PROC_REF(eftpos_change_code_stage), question = "Re-enter the current EFTPOS access code", title = "Confirm old EFTPOS code")
		return
	var/attempt_code = eftpos_answers["k147"]
	if(isnull(attempt_code))
		return
	if(attempt_code == access_code)
		if(!("k149" in eftpos_answers))
			open_request(src, /datum/prompt/number/eftpos_settings, PROC_REF(eftpos_settings_number_answered), answerer = user, eftpos_ui = ui, eftpos_answers = eftpos_answers, eftpos_action = "change_code", eftpos_key = "k149", eftpos_stage = PROC_REF(eftpos_change_code_stage), question = "Enter a new access code for this device (4-6 digits, numbers only)", title = "Enter new EFTPOS code", eftpos_max = 999999, eftpos_min = 1000)
			return
		var/trycode = eftpos_answers["k149"]
		if(isnull(trycode))
			return
		if(trycode >= 1000 && trycode <= 999999)
			access_code = trycode
		else
			tgui_alert_async(user, "That is not a valid code!")
		print_reference()
	else
		to_chat(user, "[icon2html(src, user.client)]" + span_warning("Incorrect code entered."))
	return TRUE

/obj/item/eftpos/proc/ui_act_change_id(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	return eftpos_change_id_stage(user, ui, list())

/obj/item/eftpos/proc/eftpos_change_id_stage(mob/user, datum/tgui/ui, list/eftpos_answers)
	if(!("k159" in eftpos_answers))
		open_request(src, /datum/prompt/number/eftpos_settings, PROC_REF(eftpos_settings_number_answered), answerer = user, eftpos_ui = ui, eftpos_answers = eftpos_answers, eftpos_action = "change_id", eftpos_key = "k159", eftpos_stage = PROC_REF(eftpos_change_id_stage), question = "Re-enter the current EFTPOS access code", title = "Confirm EFTPOS code")
		return
	var/attempt_code = eftpos_answers["k159"]
	if(isnull(attempt_code))
		return
	if(attempt_code == access_code)
		if(!("k161" in eftpos_answers))
			open_request(src, /datum/prompt/text/eftpos_settings, PROC_REF(eftpos_settings_text_answered), answerer = user, eftpos_ui = ui, eftpos_answers = eftpos_answers, eftpos_action = "change_id", eftpos_key = "k161", eftpos_stage = PROC_REF(eftpos_change_id_stage), question = "Enter a new terminal ID for this device", title = "Enter new EFTPOS ID", max_len = MAX_NAME_LEN, name_text = TRUE)
			return
		var/_answer_k161 = eftpos_answers["k161"]
		if(isnull(_answer_k161))
			return
		eftpos_name = _answer_k161 + " EFTPOS scanner"
		print_reference()
	else
		to_chat(user, "[icon2html(src, user.client)]" + span_warning("Incorrect code entered."))
	return TRUE

/obj/item/eftpos/proc/ui_act_link_account(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	return eftpos_link_account_stage(user, ui, list())

/obj/item/eftpos/proc/eftpos_link_account_stage(mob/user, datum/tgui/ui, list/eftpos_answers)
	if(!("k167" in eftpos_answers))
		open_request(src, /datum/prompt/number/eftpos_settings, PROC_REF(eftpos_settings_number_answered), answerer = user, eftpos_ui = ui, eftpos_answers = eftpos_answers, eftpos_action = "link_account", eftpos_key = "k167", eftpos_stage = PROC_REF(eftpos_link_account_stage), question = "Enter account number to pay EFTPOS charges into", title = "New account number")
		return
	var/attempt_account_num = eftpos_answers["k167"]
	if(isnull(attempt_account_num))
		return
	if(!("k168" in eftpos_answers))
		open_request(src, /datum/prompt/number/eftpos_settings, PROC_REF(eftpos_settings_number_answered), answerer = user, eftpos_ui = ui, eftpos_answers = eftpos_answers, eftpos_action = "link_account", eftpos_key = "k168", eftpos_stage = PROC_REF(eftpos_link_account_stage), question = "Enter pin code", title = "Account pin")
		return
	var/attempt_pin = eftpos_answers["k168"]
	if(isnull(attempt_pin))
		return
	rel_set(src, nameof(/obj/item/eftpos::linked_account), attempt_account_access(attempt_account_num, attempt_pin, 1))
	if(linked_account())
		if(linked_account().suspended)
			rel_clear(src, nameof(/obj/item/eftpos::linked_account))
			to_chat(user, "[icon2html(src, user.client)]" + span_warning("Account has been suspended."))
	else
		to_chat(user, "[icon2html(src, user.client)]" + span_warning("Account not found."))
	return TRUE

/obj/item/eftpos/proc/ui_act_trans_purpose(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	return eftpos_trans_purpose_stage(user, ui, list())

/obj/item/eftpos/proc/eftpos_trans_purpose_stage(mob/user, datum/tgui/ui, list/eftpos_answers)
	if(!("k178" in eftpos_answers))
		open_request(src, /datum/prompt/text/eftpos_settings, PROC_REF(eftpos_settings_text_answered), answerer = user, eftpos_ui = ui, eftpos_answers = eftpos_answers, eftpos_action = "trans_purpose", eftpos_key = "k178", eftpos_stage = PROC_REF(eftpos_trans_purpose_stage), question = "Enter reason for EFTPOS transaction", title = "Transaction purpose", name_text = FALSE)
		return
	var/choice = eftpos_answers["k178"]
	if(isnull(choice))
		return
	if(choice)
		transaction_purpose = choice
	return TRUE

/obj/item/eftpos/proc/ui_act_trans_value(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	return eftpos_trans_value_stage(user, ui, list())

/obj/item/eftpos/proc/eftpos_trans_value_stage(mob/user, datum/tgui/ui, list/eftpos_answers)
	if(!("k183" in eftpos_answers))
		open_request(src, /datum/prompt/number/eftpos_settings, PROC_REF(eftpos_settings_number_answered), answerer = user, eftpos_ui = ui, eftpos_answers = eftpos_answers, eftpos_action = "trans_value", eftpos_key = "k183", eftpos_stage = PROC_REF(eftpos_trans_value_stage), question = "Enter amount for EFTPOS transaction", title = "Transaction amount")
		return
	var/try_num = eftpos_answers["k183"]
	if(isnull(try_num))
		return
	if(!isnum(try_num) || try_num <= 0 || try_num > EFTPOS_MAX_TRANSACTION)
		tgui_alert_async(user, "That is not a valid amount!")
	else
		transaction_amount = round(try_num)
	return TRUE

/obj/item/eftpos/proc/ui_act_toggle_lock(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	return eftpos_toggle_lock_stage(user, ui, list())

/obj/item/eftpos/proc/eftpos_toggle_lock_stage(mob/user, datum/tgui/ui, list/eftpos_answers)
	if(transaction_locked)
		if(transaction_paid)
			transaction_locked = 0
			transaction_paid = 0
		else
			if(!("k195" in eftpos_answers))
				open_request(src, /datum/prompt/number/eftpos_settings, PROC_REF(eftpos_settings_number_answered), answerer = user, eftpos_ui = ui, eftpos_answers = eftpos_answers, eftpos_action = "toggle_lock", eftpos_key = "k195", eftpos_stage = PROC_REF(eftpos_toggle_lock_stage), question = "Enter EFTPOS access code", title = "Reset Transaction")
				return
			var/attempt_code = eftpos_answers["k195"]
			if(isnull(attempt_code))
				return
			if(attempt_code == access_code)
				transaction_locked = 0
				transaction_paid = 0
	else if(linked_account())
		transaction_locked = 1
	else
		to_chat(user, "[icon2html(src, user.client)]" + span_warning("No account connected to send transactions to."))
	return TRUE

/obj/item/eftpos/proc/ui_act_scan_card(datum/act/op/A)
	var/mob/user = A.actor
	if(linked_account())
		var/obj/item/I = user.get_active_hand()
		if(istype(I, /obj/item/card))
			scan_card(I, user = user)
	else
		to_chat(user, "[icon2html(src, user.client)]" + span_warning("Unable to link accounts."))
	return TRUE

/obj/item/eftpos/proc/ui_act_reset(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = user.get_active_hand()
	if(istype(I, /obj/item/card))
		var/obj/item/card/id/C = I
		if((ACCESS_CENT_CAPTAIN in C.access) || (ACCESS_HOP in C.access) || (ACCESS_CAPTAIN in C.access))
			access_code = 0
			to_chat(user, "[icon2html(src, user.client)]" + span_info("Access code reset to 0."))
	else if(istype(I, /obj/item/card/emag))
		access_code = 0
		to_chat(user, "[icon2html(src, user.client)]" + span_info("Access code reset to 0."))
	return TRUE

/obj/item/eftpos/proc/scan_card(obj/item/card/I, obj/item/ID_container, mob/user)
	return scan_card_stage(I, ID_container, user)

/obj/item/eftpos/proc/scan_card_stage(obj/item/card/I, obj/item/ID_container, mob/user, pin, pin_ready = FALSE)
	if (istype(I, /obj/item/card/id))
		var/obj/item/card/id/C = I
		if(I==ID_container || ID_container == null)
			act_message(user, src, others = span_info("%U% swipes a card through %T%."))
		else
			act_message(user, src, others = span_info("%U% swipes %I% through %T%."), item = ID_container)
		if(transaction_locked && !transaction_paid)
			if(linked_account())
				if(!linked_account().suspended)
					// Snapshot the authoritative amount before any sleeping input; the
					// transaction can't be silently re-priced while the PIN dialog is open.
					var/charge_amount = transaction_amount
					if(charge_amount <= 0 || charge_amount > EFTPOS_MAX_TRANSACTION)
						to_chat(user, "[icon2html(src, user.client)]" + span_warning("Invalid transaction amount."))
						return
					var/mob/swiper = user
					var/attempt_pin = ""
					var/datum/money_account/D = get_account(C.associated_account_number)
					if(D.security_level)
						var/_answer_k244 = pin
						if(!pin_ready)
							open_request(src, /datum/prompt/number/eftpos_pin, PROC_REF(pin_entered), answerer = user, payer_card = I, card_holder = ID_container, operator = user)
							return
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
								to_chat(user, "[icon2html(src, user.client)]" + span_warning("You don't have that much money!"))
						else
							to_chat(user, "[icon2html(src, user.client)]" + span_warning("Your account has been suspended."))
					else
						to_chat(user, "[icon2html(src, user.client)]" + span_warning("Unable to access account. Check security settings and try again."))
				else
					to_chat(user, "[icon2html(src, user.client)]" + span_warning("Connected account has been suspended."))
			else
				to_chat(user, "[icon2html(src, user.client)]" + span_warning("EFTPOS is not connected to an account."))
	else if (istype(I, /obj/item/card/emag))
		if(transaction_locked)
			if(transaction_paid)
				to_chat(user, "[icon2html(src, user.client)]" + span_info("You stealthily swipe \the [I] through \the [src]."))
				transaction_locked = 0
				transaction_paid = 0
			else
				act_message(user, src, others = span_info("%U% swipes a card through %T%."))
				play_sfx(src, SFX_MACHINES_CHIME)
				src.visible_message("[icon2html(src,viewers(src))] \The [src] chimes.")
				transaction_paid = 1

	//emag?

#undef EFTPOS_MAX_TRANSACTION

/// the linked_account this refers to (a relation view: null once it is deleted).
/obj/item/eftpos/proc/linked_account() as /datum/money_account
	return linked_account

/// The original scan arguments stay borrowed while the payer enters the PIN.
/datum/prompt/number/eftpos_pin
	title = "EFTPOS transaction"
	question = "Enter pin code"
	timeout = 0
	var/obj/item/card/payer_card
	var/obj/item/card_holder
	var/mob/operator
	var/payer_card_expected = FALSE
	var/card_holder_expected = FALSE
	var/operator_expected = FALSE

CAPABILITIES(/datum/prompt/number/eftpos_pin)
	ref_one(nameof(payer_card), /obj/item/card)
	ref_one(nameof(card_holder), /obj/item)
	ref_one(nameof(operator), /mob)

/datum/prompt/number/eftpos_pin/prepare(datum/act/A)
	. = ..()
	var/obj/item/card/captured_card = payer_card
	var/obj/item/captured_holder = card_holder
	var/mob/captured_operator = operator
	payer_card_expected = !isnull(captured_card)
	card_holder_expected = !isnull(captured_holder)
	operator_expected = !isnull(captured_operator)
	rel_clear(src, nameof(payer_card))
	rel_clear(src, nameof(card_holder))
	rel_clear(src, nameof(operator))
	if(captured_card && !QDELETED(captured_card))
		rel_set(src, nameof(payer_card), captured_card)
	if(captured_holder && !QDELETED(captured_holder))
		rel_set(src, nameof(card_holder), captured_holder)
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(operator), captured_operator)

/datum/prompt/number/eftpos_pin/recheck_extra()
	if((payer_card_expected && QDELETED(payer_card)) || (card_holder_expected && QDELETED(card_holder)) || (operator_expected && QDELETED(operator)))
		return "gone"

/obj/item/eftpos/proc/pin_entered(datum/act/request/A)
	if(!A.answer)
		return
	. = pin_apply(A)
	SStgui.update_uis(src)

/obj/item/eftpos/proc/pin_apply(datum/act/request/A)
	var/datum/prompt/number/eftpos_pin/ask = A.answer
	return scan_card_stage(ask.payer_card, ask.card_holder, ask.operator, ask.value, TRUE)

/obj/item/eftpos/proc/eftpos_settings_text_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/text/eftpos_settings/ask = context.answer
	var/list/eftpos_answers = ask.eftpos_answers.Copy()
	eftpos_answers[ask.eftpos_key] = ask.value
	return eftpos_settings_resume(ask.eftpos_ui, ask.eftpos_action, eftpos_answers, ask.eftpos_stage)

/obj/item/eftpos/proc/eftpos_settings_number_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/number/eftpos_settings/ask = context.answer
	var/list/eftpos_answers = ask.eftpos_answers.Copy()
	eftpos_answers[ask.eftpos_key] = ask.value
	return eftpos_settings_resume(ask.eftpos_ui, ask.eftpos_action, eftpos_answers, ask.eftpos_stage)

/// Match the original typed UI replay gates; stages have no UI arguments to parse.
/obj/item/eftpos/proc/eftpos_settings_resume(datum/tgui/ui, action, list/eftpos_answers, stage)
	if(QDELETED(src) || !ui || ui.status != STATUS_INTERACTIVE)
		return FALSE
	var/replayed = call(src, stage)(ui.user, ui, eftpos_answers)
	if(replayed)
		SStgui.update_uis(src)
	return replayed

/datum/prompt/text/eftpos_settings
	timeout = 0
	var/datum/tgui/eftpos_ui
	var/eftpos_ui_expected = FALSE
	var/list/eftpos_answers
	var/eftpos_action
	var/eftpos_key
	var/eftpos_stage

CAPABILITIES(/datum/prompt/text/eftpos_settings)
	ref_one(nameof(eftpos_ui), /datum/tgui)

/datum/prompt/text/eftpos_settings/prepare(datum/act/context)
	. = ..()
	var/datum/tgui/captured_ui = eftpos_ui
	eftpos_ui_expected = !isnull(captured_ui)
	rel_clear(src, nameof(eftpos_ui))
	if(captured_ui && !QDELETED(captured_ui))
		rel_set(src, nameof(eftpos_ui), captured_ui)

/// The old text kind stripped name tokens; its max length belonged to the window only.
/datum/prompt/text/eftpos_settings/normalize(given)
	if(!istext(given))
		return null
	return name_text ? strip_name_tokens(given) : given

/datum/prompt/text/eftpos_settings/recheck_extra()
	if(eftpos_ui_expected && QDELETED(eftpos_ui))
		return "gone"
	return null

/datum/prompt/number/eftpos_settings
	timeout = 0
	var/datum/tgui/eftpos_ui
	var/eftpos_ui_expected = FALSE
	var/list/eftpos_answers
	var/eftpos_action
	var/eftpos_key
	var/eftpos_stage
	var/eftpos_min = 0
	var/eftpos_max = INFINITY

CAPABILITIES(/datum/prompt/number/eftpos_settings)
	ref_one(nameof(eftpos_ui), /datum/tgui)

/datum/prompt/number/eftpos_settings/prepare(datum/act/context)
	. = ..()
	var/datum/tgui/captured_ui = eftpos_ui
	eftpos_ui_expected = !isnull(captured_ui)
	rel_clear(src, nameof(eftpos_ui))
	if(captured_ui && !QDELETED(captured_ui))
		rel_set(src, nameof(eftpos_ui), captured_ui)

/datum/prompt/number/eftpos_settings/recheck_extra()
	if(eftpos_ui_expected && QDELETED(eftpos_ui))
		return "gone"
	return null

/datum/prompt/number/eftpos_settings/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default || 0, eftpos_max, eftpos_min, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box
