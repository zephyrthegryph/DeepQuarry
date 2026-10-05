// RES_CREDITS: money a customer pays for an op (doc/rewrite/final_api.html, section 9 "Resource transactions (X2)").
//
//   op("vend", ui_act(...), needs(...), asks(/datum/prompt/number, ..., when = PROC_REF(pin_wanted)), costs(RES_CREDITS, PROC_REF(price)), then(...))
//
// The customer pays with the cash pile in the active hand, else from the account behind the ID they wear (credits_source()). The price is a
// cost: its Require half asks whether there is enough, it is reserved after the last answer (an account that wants a PIN is opened with the
// PIN the op asked for, so a wrong PIN refuses here, before anything happens), and it is spent only when the op's effects went through, into
// the account the op's holder names (credits_payee()). A refused or interrupted op, or one whose effects refused, pays nothing. A price of 0 is
// free: nothing is reserved from anyone and nothing is needed to pay with.

MSG_DEF_SELF(credits/no_payment, "Payment failure: you have no ID or other method of payment.")
MSG_DEF_SELF(credits/not_enough, "Payment failure: unable to process payment.")
MSG_DEF_SELF(credits/credentials, "Unable to access account: incorrect credentials.")
MSG_DEF(credits/cash_in, "You insert some cash into %T%.", "%U% inserts some cash into %T%.")
MSG_DEF(credits/card_swiped, "You swipe a card through %T%.", "%U% swipes a card through %T%.")

/// What `user` pays with: the cash pile in the active hand, else the open account behind the ID they wear, else null. Reads only.
/proc/credits_source(mob/user)
	READS_FROM() // what a customer holds and wears is legacy mob state and the accounts are a registry: asked when a purchase is chosen, never cached
	if(!ishuman(user))
		return null
	var/mob/living/carbon/human/H = user
	var/obj/item/spacecash/cash = H.get_active_hand()
	if(istype(cash))
		return cash
	var/obj/item/card/id/card = H.GetIdCard()
	if(!istype(card))
		return null
	var/datum/money_account/account = get_account(card.associated_account_number)
	return (account && !account.suspended) ? account : null

/// The account a sale on this machine is paid into (null: the money only leaves the customer).
/obj/machinery/proc/credits_payee(datum/act/op/A)
	return null

/// What a sale on this machine is called on the customer's statement.
/obj/machinery/proc/credits_purpose(datum/act/op/A)
	return "Purchase from [name]"

/// One customer's payment, set aside for one op: where it goes and what it is for.
/datum/reservation/credits
	var/datum/money_account/payee
	var/purpose
	/// The machine sold through: named on the statement, the one the customer is seen paying.
	var/atom/till

/datum/resource/credits
	res_id = RES_CREDITS
	name = "credits"

/// The payment source, else the customer (who then has nothing to pay with: a free op still reserves its nothing from someone).
/datum/resource/credits/holder_of(datum/act/op/A)
	return credits_source(A.actor) || A.actor

/datum/resource/credits/available(datum/act/op/A)
	var/datum/source = holder_of(A)
	if(istype(source, /obj/item/spacecash))
		var/obj/item/spacecash/cash = source
		return cash.worth
	if(istype(source, /datum/money_account))
		var/datum/money_account/account = source
		return account.money
	return 0

/// The account a reservation may take from: the customer's, opened with the PIN the op asked for when it wants one. Null when it does not open.
/datum/resource/credits/proc/opened_account(datum/act/op/A, datum/money_account/account)
	if(!account.security_level)
		return account
	var/datum/prompt/pin = A.answer
	if(isnull(pin?.value))
		return null
	return attempt_account_access(account.account_number, pin.value, 2)

/datum/resource/credits/reserve(datum/act/op/A, n)
	var/datum/source = n > 0 ? credits_source(A.actor) : A.actor
	if(!source || QDELETED(source))
		return null
	if(n > 0)
		if(istype(source, /datum/money_account) && !opened_account(A, source))
			return null
		if(available(A) - reserved_total(source, res_id) < n)
			return null
	var/datum/reservation/credits/R = new
	R.res_id = res_id
	R.holder = source // ALLOW(ownership): a reservation lives until its op ends, then the engine drops it
	R.amount = max(n, 0)
	R.op_key = A.key
	R.actor = A.actor // ALLOW(ownership): a reservation lives until its op ends, then the engine drops it
	var/obj/machinery/till = A.holder
	if(istype(till))
		R.till = till // ALLOW(ownership): a reservation lives until its op ends, then the engine drops it
		R.payee = till.credits_payee(A) // ALLOW(ownership): a reservation lives until its op ends, then the engine drops it
		R.purpose = till.credits_purpose(A)
	LAZYADD(rx_of(source).reservations, R)
	return R

/datum/resource/credits/refusal(datum/act/op/A, n)
	var/datum/source = credits_source(A.actor)
	if(!source)
		return /datum/msg/credits/no_payment
	if(istype(source, /datum/money_account) && !opened_account(A, source))
		return /datum/msg/credits/credentials
	return /datum/msg/credits/not_enough

/datum/resource/credits/commit(datum/reservation/credits/R)
	if(R.amount <= 0)
		return OP_OK
	var/mob/user = R.actor
	var/terminal = R.till ? "[R.till.name]" : "Terminal"
	if(istype(R.holder, /obj/item/spacecash))
		var/obj/item/spacecash/cash = R.holder
		if(QDELETED(cash) || cash.worth < R.amount)
			return OP_FAILED
		if(user && R.till)
			act_message_t(user, R.till, /datum/msg/credits/cash_in)
		if(cash.worth - R.amount <= 0)
			consume(cash, user)
		else
			cash.adjust_worth(-R.amount)
		R.payee?.credit(R.amount, "(cash)", R.purpose, terminal) // a machine has no idea who paid with cash
		return OP_OK
	var/datum/money_account/account = R.holder
	if(!istype(account) || account.suspended || account.money < R.amount)
		return OP_FAILED
	if(user && R.till)
		act_message_t(user, R.till, /datum/msg/credits/card_swiped)
		play_sfx(R.till, SFX_MACHINES_ID_SWIPE)
	if(R.payee)
		return transfer_account_funds(account, R.payee, R.amount, R.purpose, terminal) ? OP_OK : OP_FAILED
	return account.debit(R.amount, R.purpose, R.purpose, terminal) ? OP_OK : OP_FAILED
