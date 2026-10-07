/*

TODO:
give money an actual use (QM stuff, vending machines)
send money to people (might be worth attaching money to custom database thing for this, instead of being in the ID)
log transactions

*/

#define NO_SCREEN 0
#define CHANGE_SECURITY_LEVEL 1
#define TRANSFER_FUNDS 2
#define VIEW_TRANSACTION_LOGS 3

/obj/item/card/id/var/money = 2000

/obj/machinery/atm
	name = "Automatic Teller Machine"
	desc = "For all your monetary needs!"
	icon = 'icons/obj/terminals_vr.dmi'
	icon_state = "atm"
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	circuit =  /obj/item/circuitboard/atm
	flags = WALL_ITEM
	var/tmp/datum/money_account/authenticated_account
	var/number_incorrect_tries = 0
	var/previous_account_number = 0
	var/max_pin_attempts = 3
	var/ticks_left_locked_down = 0
	var/ticks_left_timeout = 0
	var/machine_id = ""
	var/tmp/obj/item/card/held_card
	var/editing_security_level = 0
	var/view_screen = NO_SCREEN


/obj/machinery/atm/Initialize(mapload)
	machine_id = "[station_name()] RT #[GLOB.num_financial_terminals++]"
	. = ..()


/// Has mains power (NOPOWER clear); the timers and cash dispensing only run while it does.
OM_DERIVE_FIELD(/obj/machinery/atm, has_mains_power, list("stat"))
/obj/machinery/atm/proc/has_mains_power()
	return !power_lost()

/obj/machinery/atm/proc/work_step(datum/act/timer/A)
	if(ticks_left_timeout > 0)
		ticks_left_timeout--
		if(ticks_left_timeout <= 0)
			rel_clear(src, nameof(authenticated_account))
	if(ticks_left_locked_down > 0)
		ticks_left_locked_down--
		if(ticks_left_locked_down <= 0)
			number_incorrect_tries = 0

	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/spacecash/S in contents_of(src)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		S.forceMove(src.loc)
		if(prob(50))
			play_sfx(src, SFX_ITEMS_POLAROID1)
		else
			play_sfx(src, SFX_ITEMS_POLAROID2)
		break
	if(ticks_left_timeout <= 0 && ticks_left_locked_down <= 0 && !(locate_within(src, /obj/item/spacecash)))
		return PROCESS_KILL

DECLARE_EMAG(/obj/machinery/atm, PROC_REF(on_emag), null, null)
/obj/machinery/atm/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	//short out the machine, shoot sparks, spew money!
	set_emagged(1)
	fx_sparks(src, 5, FALSE)
	spawn_money(rand(100,500),src.loc)
	//we don't want to grief people by locking their id in an emagged ATM
	release_held_id(user)

	//display a message to the user
	var/response = pick("Initiating withdraw. Have a nice day!", "CRITICAL ERROR: Activating cash chamber panic siphon.","PIN Code accepted! Emptying account balance.", "Jackpot!")
	to_chat(user, span_warning("[icon2html(src, user.client)] The [src] beeps: \"[response]\""))
	return 1

/obj/machinery/atm/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/atm_insert_card,
		/datum/interaction/machine_item/atm_deposit_cash,
		/datum/interaction/machine_hand/ungated/atm_use,
	)
	..()

/// The old attackby's card branch: emag error, resolve an emag card, or slot an ID.
/datum/interaction/machine_item/atm_insert_card
	id = "atm_insert_card"
	name = "Insert card"
	held_type = /obj/item/card
	effect = /obj/machinery/atm/proc/interaction_atm_insert_card

/obj/machinery/atm/proc/interaction_atm_insert_card(mob/user, obj/item/card/held, datum/interaction/interaction)
	if(emagged() > 0)
		//prevent inserting id into an emagged ATM
		to_chat(user, span_boldwarning("[icon2html(src, user.client)] CARD READER ERROR. This system has been compromised!"))
		return TRUE
	else if(istype(held, /obj/item/card/emag))
		held.resolve_attackby(src, user)
		return TRUE

	if(!istype(held, /obj/item/card/id))
		return TRUE
	var/obj/item/card/id/idcard = held
	if(!held_card())
		if(!own_bring_in(src, nameof(held_card), idcard, null, user, TRUE, null, FALSE))
			return TRUE
		rel_set(src, nameof(held_card), idcard)
		if(authenticated_account() && held_card().associated_account_number != authenticated_account().account_number)
			rel_clear(src, nameof(authenticated_account))
	return TRUE

/// The old attackby's spacecash branch: deposit cash into the authenticated account.
/datum/interaction/machine_item/atm_deposit_cash
	id = "atm_deposit_cash"
	name = "Deposit cash"
	held_type = /obj/item/spacecash
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/atm/proc/has_authenticated_account, null))
	effect = /obj/machinery/atm/proc/interaction_atm_deposit_cash

/obj/machinery/atm/proc/has_authenticated_account(mob/actor, atom/target, obj/item/held)
	return !!authenticated_account()

/obj/machinery/atm/proc/interaction_atm_deposit_cash(mob/user, obj/item/spacecash/held, datum/interaction/interaction)
	// Convert physical cash into an audited account deposit.
	var/datum/money_account/account = authenticated_account()
	var/deposit_value = held.worth
	if(!account || account.suspended || !isnum(deposit_value) || deposit_value <= 0)
		return TRUE
	var/cash_name = "[held]"
	if(!consume(held, user))
		return TRUE
	account.credit(deposit_value, user.real_name, "Cash deposit", machine_id)
	if(prob(50))
		play_sfx(src, SFX_ITEMS_POLAROID1)
	else
		play_sfx(src, SFX_ITEMS_POLAROID2)

	to_chat(user, span_info("You insert [cash_name] into [src]."))
	src.attack_hand(user)
	return TRUE

/obj/machinery/atm/tgui_status(mob/user)
	. = ..()
	if(issilicon(user))
		return STATUS_CLOSE

/obj/machinery/atm/tgui_static_data(mob/user)
	var/list/data = ..()
	data["machine_id"] = machine_id
	return data

/// The window's data.
/obj/machinery/atm/ui_data(datum/act/eval/A)
	. = list()
	.["locked_down"] = ticks_left_locked_down
	var/list/part = ui_data_part_atm(A)
	for(var/key in part)
		.[key] = part[key]

/// The computed part of the window's data.
/obj/machinery/atm/proc/ui_data_part_atm(datum/act/eval/A)
	var/list/data = list()

	data["emagged"] = emagged()
	if(emagged() > 0)
		return data

	data["held_card"] = held_card()
	if(ticks_left_locked_down > 0)
		return data

	data["authenticated_account"] = null
	data["suspended"] = FALSE
	if(authenticated_account())
		if(authenticated_account().suspended)
			data["suspended"] = TRUE
			return data

		var/list/transactions = list()
		for(var/datum/transaction/T as anything in authenticated_account().transaction_log)
			UNTYPED_LIST_ADD(transactions, list(
				"date" = T.date,
				"time" = T.time,
				"target_name" = T.target_name,
				"purpose" = T.purpose,
				"amount" = T.amount,
				"source_terminal" = T.source_terminal
			))

		data["authenticated_account"] = list(
			"owner_name" = authenticated_account().owner_name,
			"money" = authenticated_account().money,
			"security_level" = authenticated_account().security_level,
			"transactions" = transactions,
		)

	return data

CAPABILITIES(/obj/machinery/atm)
	started_work(step = PROC_REF(work_step), starts = TRUE, gate = PROC_REF(has_mains_power), wakes_on = list(STAT_OPERABLE), unpowered = TRUE)
	op("insert_card", ui_act(), then(PROC_REF(ui_act_insert_card)))
	op("logout", ui_act(), then(PROC_REF(ui_act_logout)))
	interface("AutomatedTellerMachine")
	op("balance_statement", ui_act("balance_statement"), then(PROC_REF(ui_act_balance_statement)))
	op("print_transaction", ui_act("print_transaction"), then(PROC_REF(ui_act_print_transaction)))
	// lowering the level asks for the PIN again unless the account's own card is in the machine
	op("change_security_level", ui_act("change_security_level", arg("new_security_level", num(0, 2))),
		asks(/datum/prompt/number, fields = list("question" = "Re-enter your account PIN to lower the security level", "title" = "Confirm PIN", "timeout" = 0), step = "k325", when = PROC_REF(lowering_needs_pin)),
		then(PROC_REF(ui_act_change_security_level)))
	op("attempt_auth", ui_act("attempt_auth", arg("account_num", num()), arg("account_pin", num())), then(PROC_REF(ui_act_attempt_auth)))
	op("transfer", ui_act("transfer", arg("funds_amount", num()), arg("purpose"), arg("target_acc_number", num())), then(PROC_REF(ui_act_transfer)))
	op("e_withdrawal", ui_act("e_withdrawal", arg("funds_amount", num())), then(PROC_REF(ui_act_e_withdrawal)))
	op("withdrawal", ui_act("withdrawal", arg("funds_amount", num())), then(PROC_REF(ui_act_withdrawal)))
	display_disconnect_op()

/obj/machinery/atm/proc/ui_act_insert_card(datum/act/op/A)
	if(held_card())
		release_held_id(A.actor)
	else
		if(emagged() > 0)
			to_chat(A.actor, span_boldwarning("[icon2html(src, A.actor.client)] The ATM card reader rejected your ID because this machine has been sabotaged!"))
		else
			var/obj/item/I = A.actor.get_active_hand()
			if(istype(I, /obj/item/card/id))
				A.actor.drop_item(src)
				rel_set(src, nameof(src.held_card), I)
	. = OP_OK
	if(.)
		if(ticks_left_timeout > 0 || ticks_left_locked_down > 0)
			work_start(src)
		play_sfx(src, SFX_KEYBOARD, 1.25, vary = TRUE)

/obj/machinery/atm/proc/ui_act_logout(datum/act/op/A)
	if(held_card())
		release_held_id(A.actor)
	rel_clear(src, nameof(/obj/machinery/atm::authenticated_account))
	. = OP_OK

	// Balance statement
	if(.)
		if(ticks_left_timeout > 0 || ticks_left_locked_down > 0)
			work_start(src)
		play_sfx(src, SFX_KEYBOARD, 1.25, vary = TRUE)

/obj/machinery/atm/proc/ui_act_balance_statement(datum/act/op/A)
	if(!authenticated_account())
		return

	var/obj/item/paper/R = new(loc)
	R.name = "Account balance: [authenticated_account().owner_name]"
	R.info = span_bold("NT Automated Teller Account Statement") + "<br><br>"
	R.info += span_italics("Account holder:") + " [authenticated_account().owner_name]<br>"
	R.info += span_italics("Account number:") + " [authenticated_account().account_number]<br>"
	R.info += span_italics("Balance:") + " $[authenticated_account().money]<br>"
	R.info += span_italics("Date and time:") + " [stationtime2text()], [GLOB.current_date_string]<br><br>"
	R.info += span_italics("Service terminal ID:") + " [machine_id]<br>"

	//stamp the paper
	var/image/stampoverlay = image('icons/obj/bureaucracy.dmi')
	stampoverlay.icon_state = "paper_stamp-cent"
	if(!R.stamped)
		R.stamped = new
	R.stamped += /obj/item/stamp
	R.add_overlay(stampoverlay)
	R.stamps += "<HR>" + span_italics("This paper has been stamped by the Automatic Teller Machine.")

	if(prob(50))
		play_sfx(src, SFX_ITEMS_POLAROID1)
	else
		play_sfx(src, SFX_ITEMS_POLAROID2)
	. = TRUE

	// Transaction logs
	if(.)
		if(ticks_left_timeout > 0 || ticks_left_locked_down > 0)
			work_start(src)
		play_sfx(src, SFX_KEYBOARD, 1.25, vary = TRUE)

/obj/machinery/atm/proc/ui_act_print_transaction(datum/act/op/A)
	if(!authenticated_account())
		return

	var/obj/item/paper/R = new(loc)
	R.name = "Transaction logs: [authenticated_account().owner_name]"
	R.info = span_bold("Transaction logs") + "<br>"
	R.info += span_italics("Account holder:") + " [authenticated_account().owner_name]<br>"
	R.info += span_italics("Account number:") + " [authenticated_account().account_number]<br>"
	R.info += span_italics("Date and time:") + " [stationtime2text()], [GLOB.current_date_string]<br><br>"
	R.info += span_italics("Service terminal ID:") + " [machine_id]<br>"
	R.info += "<table border=1 style='width:100%'>"
	R.info += "<tr>"
	R.info += "<td>" + span_bold("Date") + "</td>"
	R.info += "<td>" + span_bold("Time") + "</td>"
	R.info += "<td>" + span_bold("Target") + "</td>"
	R.info += "<td>" + span_bold("Purpose") + "</td>"
	R.info += "<td>" + span_bold("Value") + "</td>"
	R.info += "<td>" + span_bold("Source terminal ID") + "</td>"
	R.info += "</tr>"
	for(var/datum/transaction/T in authenticated_account().transaction_log)
		R.info += "<tr>"
		R.info += "<td>[T.date]</td>"
		R.info += "<td>[T.time]</td>"
		R.info += "<td>[T.target_name]</td>"
		R.info += "<td>[T.purpose]</td>"
		R.info += "<td>$[T.amount]</td>"
		R.info += "<td>[T.source_terminal]</td>"
		R.info += "</tr>"
	R.info += "</table>"

	//stamp the paper
	var/image/stampoverlay = image('icons/obj/bureaucracy.dmi')
	stampoverlay.icon_state = "paper_stamp-cent"
	if(!R.stamped)
		R.stamped = new
	R.stamped += /obj/item/stamp
	R.add_overlay(stampoverlay)
	R.stamps += "<HR>" + span_italics("This paper has been stamped by the Automatic Teller Machine.")

	if(prob(50))
		play_sfx(src, SFX_ITEMS_POLAROID1)
	else
		play_sfx(src, SFX_ITEMS_POLAROID2)
	. = TRUE
	if(.)
		if(ticks_left_timeout > 0 || ticks_left_locked_down > 0)
			work_start(src)
		play_sfx(src, SFX_KEYBOARD, 1.25, vary = TRUE)

/// The PIN is asked when the level goes down and the account's own card is not in the machine.
/obj/machinery/atm/proc/lowering_needs_pin(datum/act/op/A)
	var/datum/money_account/account = QDELETED(authenticated_account) ? null : authenticated_account // ALLOW(reads): the account is read when the button is pressed, never cached
	if(!account || !isnum(A.args["new_security_level"]) || A.args["new_security_level"] >= account.security_level)
		return FALSE
	var/obj/item/card/card = QDELETED(held_card) ? null : held_card // ALLOW(reads): the card is read when the button is pressed, never cached
	return !(card && card.associated_account_number == account.account_number)

/obj/machinery/atm/proc/ui_act_change_security_level(datum/act/op/A, new_security_level)
	var/mob/user = A.actor
	if(authenticated_account())
		var/new_sec_level = new_security_level
		if(!isnum(new_sec_level))
			return
		// Lowering the security level weakens future access controls, so it must
		// be re-authorised: either the matching card is physically inserted, or
		// the account PIN is re-entered and validated. Raising the level is always
		// allowed for the already-authenticated holder.
		if(new_sec_level < authenticated_account().security_level)
			var/card_present = held_card() && held_card().associated_account_number == authenticated_account().account_number
			if(!card_present)
				var/tried_pin = A.step_value("k325")
				if(isnull(tried_pin))
					return
				// Re-validate auth/state after the sleeping input.
				if(!authenticated_account() || QDELETED(src))
					return
				var/datum/money_account/reauth = attempt_account_access(authenticated_account().account_number, tried_pin, 1)
				if(reauth != authenticated_account())
					to_chat(user, "[icon2html(src, user.client)]" + span_warning("Incorrect PIN; security level unchanged."))
					return
		authenticated_account().security_level = new_sec_level
	. = TRUE
	if(.)
		if(ticks_left_timeout > 0 || ticks_left_locked_down > 0)
			work_start(src)
		play_sfx(src, SFX_KEYBOARD, 1.25, vary = TRUE)

/obj/machinery/atm/proc/ui_act_attempt_auth(datum/act/op/A, account_num, account_pin)
	var/mob/user = A.actor
	if(ticks_left_locked_down)
		return
	var/tried_account_num = held_card() ? held_card().associated_account_number : account_num
	var/tried_pin = account_pin

	// check if they have low security enabled
	if(!tried_account_num)
		scan_user(user)
	else
		rel_set(src, nameof(/obj/machinery/atm::authenticated_account), attempt_account_access(tried_account_num, tried_pin, held_card() && held_card().associated_account_number == tried_account_num ? 2 : 1))

	if(!authenticated_account())
		number_incorrect_tries++
		if(previous_account_number == tried_account_num)
			if(number_incorrect_tries > max_pin_attempts)
				//lock down the atm
				ticks_left_locked_down = 30
				play_sfx(src, SFX_MACHINES_BUZZ_TWO, vary = TRUE)

				//create an entry in the account transaction log
				var/datum/money_account/failed_account = get_account(tried_account_num)
				if(failed_account)
					var/datum/transaction/T = new()
					T.target_name = failed_account.owner_name
					T.purpose = "Unauthorised login attempt"
					T.source_terminal = machine_id
					T.date = GLOB.current_date_string
					T.time = stationtime2text()
					rel_add(failed_account, nameof(/datum/money_account::transaction_log), T)
			else
				to_chat(user, span_warning("[icon2html(src, user.client)] Incorrect pin/account combination entered, [max_pin_attempts - number_incorrect_tries] attempts remaining."))
				previous_account_number = tried_account_num
				play_sfx(src, SFX_MACHINES_BUZZ_SIGH, vary = TRUE)
		else
			to_chat(user, span_warning("[icon2html(src, user.client)] incorrect pin/account combination entered."))
			number_incorrect_tries = 0
	else
		play_sfx(src, SFX_MACHINES_TWOBEEP)
		ticks_left_timeout = 120
		view_screen = NO_SCREEN

		//create a transaction log entry
		var/datum/transaction/T = new()
		T.target_name = authenticated_account().owner_name
		T.purpose = "Remote terminal access"
		T.source_terminal = machine_id
		T.date = GLOB.current_date_string
		T.time = stationtime2text()
		rel_add(authenticated_account(), nameof(/datum/money_account::transaction_log), T)

		to_chat(user, span_notice("[icon2html(src, user.client)] Access granted. Welcome user '[authenticated_account().owner_name].'"))

	previous_account_number = tried_account_num
	. = TRUE
	if(.)
		if(ticks_left_timeout > 0 || ticks_left_locked_down > 0)
			work_start(src)
		play_sfx(src, SFX_KEYBOARD, 1.25, vary = TRUE)

/obj/machinery/atm/proc/ui_act_transfer(datum/act/op/A, funds_amount, purpose, target_acc_number)
	var/mob/user = A.actor
	if(!authenticated_account())
		return
	var/transfer_amount = funds_amount
	transfer_amount = round(transfer_amount, 0.01)
	if(transfer_amount <= 0)
		tgui_alert_async(user, "That is not a valid amount.")
	else if(transfer_amount <= authenticated_account().money)
		var/target_account_number = target_acc_number
		var/transfer_purpose = purpose
		var/datum/money_account/target_account = get_account(target_account_number)
		if(transfer_account_funds(authenticated_account(), target_account, transfer_amount, transfer_purpose, machine_id))
			to_chat(user, "[icon2html(src, user.client)]" + span_info("Funds transfer successful."))
		else
			to_chat(user, "[icon2html(src, user.client)]" + span_warning("Funds transfer failed."))

	else
		to_chat(user, "[icon2html(src, user.client)]" + span_warning("You don't have enough funds to do that!"))
	. = TRUE
	if(.)
		if(ticks_left_timeout > 0 || ticks_left_locked_down > 0)
			work_start(src)
		play_sfx(src, SFX_KEYBOARD, 1.25, vary = TRUE)

/obj/machinery/atm/proc/ui_act_e_withdrawal(datum/act/op/A, funds_amount)
	var/mob/user = A.actor
	var/amount = max(funds_amount,0)
	amount = round(amount, 0.01)
	if(amount <= 0)
		tgui_alert_async(user, "That is not a valid amount.")
		return

	if(!authenticated_account())
		return

	if(authenticated_account().debit(amount, authenticated_account().owner_name, "E-wallet withdrawal", machine_id))
		play_sfx(src, SFX_MACHINES_CHIME)
		spawn_ewallet(amount,src.loc,user)
	else
		to_chat(user, "[icon2html(src, user.client)]" + span_warning("You don't have enough funds to do that!"))
	. = TRUE
	if(.)
		if(ticks_left_timeout > 0 || ticks_left_locked_down > 0)
			work_start(src)
		play_sfx(src, SFX_KEYBOARD, 1.25, vary = TRUE)

/obj/machinery/atm/proc/ui_act_withdrawal(datum/act/op/A, funds_amount)
	var/mob/user = A.actor
	var/amount = max(funds_amount,0)
	amount = round(amount, 0.01)
	if(amount <= 0)
		tgui_alert_async(user, "That is not a valid amount.")
		return

	if(!authenticated_account())
		return

	if(authenticated_account().debit(amount, authenticated_account().owner_name, "Cash withdrawal", machine_id))
		play_sfx(src, SFX_MACHINES_CHIME)
		spawn_money(amount,src.loc,user)
	else
		to_chat(user, "[icon2html(src, user.client)]" + span_warning("You don't have enough funds to do that!"))
	. = TRUE
	if(.)
		if(ticks_left_timeout > 0 || ticks_left_locked_down > 0)
			work_start(src)
		play_sfx(src, SFX_KEYBOARD, 1.25, vary = TRUE)

/datum/interaction/machine_hand/ungated/atm_use
	id = "atm_use"
	name = "Use"
	requires = list(REQ_BECAUSE(REQ_TARGET_STATE(/obj/machinery/atm/proc/not_silicon_user), "a firewall prevents you from interfacing with this device"))
	effect = /obj/machinery/atm/proc/interaction_atm_use

/// Requirement: silicons are firewalled out.
/obj/machinery/atm/proc/not_silicon_user(mob/user, atom/target, obj/item/held)
	return !istype(user, /mob/living/silicon)

/obj/machinery/atm/proc/interaction_atm_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(get_dist(src,user) <= 1)
		tgui_interact(user)
	return TRUE

//stolen wholesale and then edited a bit from newscasters, which are awesome and by Agouri
/obj/machinery/atm/proc/scan_user(mob/living/carbon/human/human_user as mob)
	if(!authenticated_account())
		if(human_user.get_equipped_item(SLOT_ID_ID))
			var/obj/item/card/id/I
			if(istype(human_user.get_equipped_item(SLOT_ID_ID), /obj/item/card/id) )
				I = human_user.get_equipped_item(SLOT_ID_ID)
			else if(istype(human_user.get_equipped_item(SLOT_ID_ID), /obj/item/pda) )
				var/obj/item/pda/P = human_user.get_equipped_item(SLOT_ID_ID)
				I = P.id
			if(I)
				rel_set(src, nameof(authenticated_account), attempt_account_access(I.associated_account_number))

// put the currently held id on the ground or in the hand of the user
/obj/machinery/atm/proc/release_held_id(mob/living/carbon/human/human_user as mob)
	if(!held_card())
		return

	held_card().forceMove(src.loc)
	rel_clear(src, nameof(authenticated_account))

	if(ishuman(human_user) && !human_user.get_active_hand())
		human_user.put_in_hands(held_card())
	rel_clear(src, nameof(held_card))

/obj/machinery/atm/proc/spawn_ewallet(sum, loc, mob/living/carbon/human/human_user as mob)
	var/obj/item/spacecash/ewallet/E = new /obj/item/spacecash/ewallet(loc)
	if(ishuman(human_user) && !human_user.get_active_hand())
		human_user.put_in_hands(E)
	E.worth = sum
	E.owner_name = authenticated_account().owner_name

#undef NO_SCREEN
#undef CHANGE_SECURITY_LEVEL
#undef TRANSFER_FUNDS
#undef VIEW_TRANSACTION_LOGS

/// the held_card this refers to (a relation view: null once it is deleted).
/obj/machinery/atm/proc/held_card() as /obj/item/card
	return held_card

/// the authenticated_account this refers to (a relation view: null once it is deleted).
/obj/machinery/atm/proc/authenticated_account() as /datum/money_account
	return authenticated_account
