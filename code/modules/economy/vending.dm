///
///		A vending machine
///
// A vending machine is declared (doc/rewrite/final_api.html section 16, doc/rewrite/conversion_guide.md): ONE CAPABILITIES list says what it is: a machine
// with a service panel and the wires behind it, an emag that shorts out its product lock, a bolted base, a coin slot, a stock of product records, a
// window and the buttons in it, and the ops that take things in (a coin, stock, a refill cartridge) and show what it keeps (the log). The imperative
// parts below are its own: the product records, the payments and the vend itself, the conditions and effects the list names, and the look.
//
// What the machine core still keeps until the machine track (phase 4): the stat bits (BROKEN, NOPOWER, ...) read through machine_basics()'s one
// bridge contribution, set_use_power(), and the circuit board.
//
//	ALL THE VENDING MACHINES ARE IN vending_machines.dm now!
//

MSG_DEF_SELF(vending/busy, "It is busy!")
MSG_DEF_SELF(vending/denied, "Access denied.")
MSG_DEF_SELF(vending/panel_open, "It cannot dispense products while its service panel is open!")
MSG_DEF_SELF(vending/unavailable, "That is not available.")
MSG_DEF_SELF(vending/no_account, "Vendor account offline. Unable to process transaction.")
MSG_DEF_SELF(vending/no_payment, "Payment failure: you have no ID or other method of payment.")
MSG_DEF_SELF(vending/payment_failed, "Payment failure: unable to process payment.")
MSG_DEF_SELF(vending/lawed, "Lawed unit recognized.  Lawed units cannot complete this transaction.  Purchase canceled.")
MSG_DEF_SELF(vending/no_coin_slot, "It has no coin slot.")
MSG_DEF_SELF(vending/no_coin, "There is no coin in this machine.")
MSG_DEF_SELF(vending/no_refill_port, "It does not have a refill port.")
MSG_DEF_SELF(vending/unsecured, "You cannot refill it while it is not secured.")
MSG_DEF_SELF(vending/wrong_cartridge, "That cartridge does not fit it.")
MSG_DEF_SELF(vending/refilled, "You refill %T% using %I%.")
MSG_DEF_SELF(vending/fake_coin, "%I% doesn't fit into the coin slot on %T%.")
MSG_DEF_SELF(vending/stocked, "You insert %I% in the product receptor.")
MSG_DEF(vending/shorted, "You short out %T%'s product lock.", "%U% shorts out %T%'s product lock.")

/obj/machinery/vending
	name = "Vendomat"
	desc = "A generic vending machine."
	icon = 'icons/obj/vending.dmi'
	icon_state = "generic"
	anchored = TRUE
	density = TRUE
	unacidable = TRUE
	clicksound = SFX_BUTTON

	// Power
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	var/vend_power_usage = 150 //actuators and stuff

	// Vending-related
	active = 1 //No sales pitches if off!
	/// Are we ready to vend?? Is it time??
	var/vend_ready = TRUE
	var/vend_delay = 10 //How long does it take to vend?
	/// Bitmask of cats we're currently showing
	var/categories = CAT_NORMAL
	var/tmp/datum/stored_item/vending_product/currently_vending	// What we're requesting payment for right now
	var/vending_sound = "machines/vending/vending_drop.ogg"

	/*
		Variables used to initialize the product list
		These are used for initialization only, and so are optional if
		product_records is specified. build_inventory() drops them after use.
	*/
	var/list/products // For each, use the following pattern:
	var/list/contraband // list(/type/path = amount,/type/path2 = amount2)
	var/list/premium // No specified amount = only one in stock
	/// Set automatically, allows coin use
	var/has_premium = FALSE
	var/list/prices // Prices for each item, list(/type/path = price), items not in the list don't have a price.
	/// Set automatically, enables pricing
	var/has_prices = FALSE
	// This one is used for refill cartridge use.
	/// Read-only once built: identical tables are shared between vendors (see share_refill_table()).
	var/list/refill // For each, use the following pattern:
	// Enables refilling with appropriate cartridges
	var/refillable = TRUE

	// List of vending_product items available.
	var/list/product_records = list() // ALLOW(instance_list): the vendor's live stock records: edited in place per machine and always filled

	// Variables used to initialize advertising
	var/product_slogans = "" //String of slogans spoken out loud, separated by semicolons
	var/product_ads = "" //String of small ad messages in the vending screen

	var/list/ads_list // Lazy

	// Stuff relating vocalizations
	var/list/slogan_list // Lazy
	var/vend_reply //Thank you for shopping!
	COOLDOWN_DECLARE(reply_cooldown)
	COOLDOWN_DECLARE(slogan_cooldown) //When did we last pitch?
	var/slogan_delay = 6000 //How long until we can pitch again?

	// Things that can go wrong
	var/shoot_inventory_chance = 1

	/// Does it check the customer's ID for the product lock (a wire turns this off).
	var/scan_id = TRUE
	var/obj/item/coin/coin

	/// Stop spouting those godawful pitches!
	var/shut_up = TRUE
	/// Shock customers like an airlock: steps left (-1 for permanently, from a cut wire).
	var/seconds_electrified = 0
	/// Fire items at customers! We're broken!
	var/shoot_inventory = 0

	var/list/log // Lazy: purchase log entries.
	var/req_log_access = ACCESS_CARGO //default access for checking logs is cargo
	var/has_logs = 0 //defaults to 0, set to anything else for vendor to have logs
	var/can_rotate = 1 //Defaults to yes, can be set to 0 for vendors without or with unwanted directionals.

// What the window shows and what the machine's timed work reads.
TRACKED(/obj/machinery/vending, vend_ready)
TRACKED(/obj/machinery/vending, categories)
TRACKED(/obj/machinery/vending, scan_id)
TRACKED(/obj/machinery/vending, shut_up)
TRACKED(/obj/machinery/vending, seconds_electrified)
TRACKED(/obj/machinery/vending, shoot_inventory)

CAPABILITIES(/obj/machinery/vending)
	machine_basics(repair = NONE)
	panel()
	extend("panel.open", wait(0))
	wires(/datum/wires/vending)
	emag(say = MSG(vending/shorted), repeatable = TRUE)
	anchor()
	extend("anchor.toggle", wait(2 SECONDS), needs(req_panel_closed()))
	owns_one(nameof(coin), /obj/item/coin)
	owns_many(nameof(product_records), /datum/stored_item/vending_product)
	ref_one(nameof(currently_vending), /datum/stored_item/vending_product)
	interface("Vending")
	op("vend", ui_act(arg("vend")),
		needs(req(PROC_REF(vend_listed), because = MSG(vending/unavailable)), req(PROC_REF(vend_idle), because = MSG(vending/busy)), req(PROC_REF(vend_shut), because = MSG(vending/panel_open))),
		asks(/datum/prompt/number, fields = list("question" = "Enter pin code"), when = PROC_REF(pin_wanted)),
		then(PROC_REF(vend_access), early = TRUE),
		then(PROC_REF(ui_vend)), logs(LOG_GAME))
	op("remove_coin", ui_act(), needs(req_full(nameof(coin), because = MSG(vending/no_coin)), req(PROC_REF(actor_is_no_silicon), because = MSG(op/failed))), take_out(nameof(coin)))
	op("toggle_voice", ui_act(), when(PANEL_OPEN), toggles(nameof(shut_up)))
	op("insert_coin", item(/obj/item/coin), when(nameof(has_premium)), needs(req_operable(), req_empty(nameof(coin), because = MSG(bay/full))), put_in(nameof(coin)))
	op("reject_fake_coin", item(/obj/item/fake_coin), when(nameof(has_premium)), then(PROC_REF(fake_coin_rejected)))
	op("refill", item(/obj/item/refill_cartridge),
		needs(req_panel_closed(), req_operable(), req(PROC_REF(refill_port), because = MSG(vending/no_refill_port)), req(PROC_REF(refill_secured), because = MSG(vending/unsecured)), req(PROC_REF(cartridge_fits), because = MSG(vending/wrong_cartridge))),
		then(PROC_REF(refilled)), consumes())
	op("stock", item(/obj/item), when(PROC_REF(stockable)), then(PROC_REF(stocked)))
	op("open_with_item", item(/obj/item), priority(above("stock")), when(PROC_REF(item_opens_window)), needs(req_operable()), opens_ui())
	op("check_logs", hand(), when(PROC_REF(bare_touch)), label("Check vending logs"), priority(below("ui_open")), then(PROC_REF(check_logs_op)))
	extend("ui_open", when(PROC_REF(bare_touch)), needs(req_on_authority(AUTH_PHYSICAL), req_operable()), then(PROC_REF(shock_guard), early = TRUE), then(PROC_REF(open_wires_beside_the_window)))
	extend("open_with_item", then(PROC_REF(shock_guard), early = TRUE), then(PROC_REF(open_wires_beside_the_window)))
	extend(TAG_UI, needs(req_operable(), req(PROC_REF(customer_capable), because = MSG(op/failed))))
	on_notice(/datum/notice/hit/explosion, then(PROC_REF(vending_blast_malfunction)))
	on_change(nameof(coin), ANY, then(PROC_REF(coin_changed)))
	on_change(nameof(shut_up), ANY, then(PROC_REF(timed_work_changed)))
	on_change(nameof(seconds_electrified), ANY, then(PROC_REF(timed_work_changed)))
	on_change(nameof(shoot_inventory), ANY, then(PROC_REF(timed_work_changed)))
	on_change(nameof(stat), ANY, then(PROC_REF(timed_work_changed)))

/// Active with something time-dependent to do: electrified, shooting inventory, or advertising.
/// slogan_list is filled once in Initialize() and never changes afterwards, so it is not an input.
/obj/machinery/vending/proc/vend_has_timed_work()
	return active && (seconds_electrified > 0 || shoot_inventory || (!shut_up && length(slogan_list)))

/obj/machinery/vending/Initialize(mapload)
	. = ..()
	if(product_slogans)
		LAZYADD(slogan_list, splittext(product_slogans, ";"))

		// So not all machines speak at the exact same time.
		// The first time this machine says something will be at slogantime + this random value,
		// so if slogantime is 10 minutes, it will say it at somewhere between 10 and 20 minutes after the machine is crated.
		COOLDOWN_START(src, slogan_cooldown, slogan_delay + rand(0, slogan_delay))

	if(product_ads)
		LAZYADD(ads_list, splittext(product_ads, ";"))

	build_inventory()
	power_change()

	if(can_rotate) // If we can't change directions, don't bother.
		make_rotatable()
	timed_work_arm()

GLOBAL_LIST_EMPTY(vending_products)
/**
 *  Build produdct_records from the products lists
 *
 *  products, contraband, premium, and prices allow specifying
 *  products that the vending machine is to carry without manually populating
 *  product_records.
 */
/obj/machinery/vending/proc/build_inventory()
	var/list/all_products = list(
		list(products, CAT_NORMAL),
		list(contraband, CAT_HIDDEN),
		list(premium, CAT_COIN))

	for(var/current_list in all_products)
		var/category = current_list[2]

		for(var/entry in current_list[1])
			// list values may be list(count, variant). Resolve them.
			var/list/spec = dq_resolve_spawn_value(current_list[1][entry])
			var/datum/stored_item/vending_product/product = new/datum/stored_item/vending_product(src, entry)

			product.price = (entry in prices) ? prices[entry] : 0
			product.amount = spec["count"] || 1
			product.variant = spec["variant"]
			product.category = category

			own_add(src, nameof(product_records), product)
			GLOB.vending_products[entry] = 1

	if(LAZYLEN(prices))
		has_prices = TRUE
	if(LAZYLEN(premium))
		has_premium = TRUE

	if(!LAZYLEN(refill) && refillable)			// Manually setting refill list prevents the automatic population. By default filled with all entries from normal product.
		refill = products
	share_refill_table()

	// Consumed: drop the references (products may now be the refill table, so don't Cut() it).
	products = null
	contraband = null
	premium = null
	prices = null
	all_products.Cut()

/// Vendors of one type (and the same mapped overrides) carry identical refill
/// tables, so they share one list. Nothing edits refill after init; copy it first if that changes.
/obj/machinery/vending/proc/share_refill_table()
	var/static/list/refill_tables = list()
	if(!LAZYLEN(refill))
		refill = null
		return
	var/key = "[type]|[json_encode(refill)]"
	var/list/shared = refill_tables[key]
	if(shared)
		refill = shared
	else
		refill_tables[key] = refill

/obj/machinery/vending/proc/refill_inventory()
	if(!(LAZYLEN(refill)))		//This shouldn't happen, but just in case...
		return

	for(var/entry in refill)
		var/datum/stored_item/vending_product/current_product
		for(var/datum/stored_item/vending_product/product in product_records)
			if(product.item_path == entry)
				current_product = product
				break
		if(!current_product)
			continue
		else
			// Restocking adds to the latent count; nothing is created.
			var/list/spec = dq_resolve_spawn_value(refill[entry])
			current_product.refill_products(spec["count"])

// Stock is a stock slot (roadmap C9, code/datums/containment/stock.dm): each
// product is a record with a latent count, and a real item is made only when
// one is vended. Items stocked by hand stay real when their state is their own.
/obj/machinery/vending/stock_records()
	return product_records

/obj/machinery/vending/on_slot_changed(slot_id, atom/movable/thing, inserted)
	if(!inserted && slot_id == CONTAINER_SLOT_STOCK)
		for(var/datum/stored_item/R as anything in product_records)
			R.forget(thing)

/// A light blast can jolt the vendor into malfunctioning.
/obj/machinery/vending/proc/vending_blast_malfunction(datum/act/A)
	var/datum/notice/hit/explosion/N = A
	if(N.packet?.severity == 3 && prob(25))
		malfunction()

// ---- the coin slot ----

/// A coin went in or came out (or was swallowed): the premium products are shown while there is one.
/obj/machinery/vending/proc/coin_changed(datum/act/A)
	if(coin)
		set_categories(categories | CAT_COIN)
	else
		set_categories(categories & ~CAT_COIN)

/// A fake coin does not fit the slot: it is refused, and kept.
/obj/machinery/vending/proc/fake_coin_rejected(datum/act/op/A)
	A.reason = /datum/msg/vending/fake_coin
	return OP_REFUSED

/// The actor is not a machine of the law (it has hands to take a coin back).
/obj/machinery/vending/proc/actor_is_no_silicon(datum/act/op/A)
	return !issilicon(A.actor)

// ---- stocking and refilling ----

/// The held item is a thing this vendor stocks: it matches a record by type and name.
/obj/machinery/vending/proc/stockable(datum/act/op/A)
	return !isnull(stock_record_for(A.held)) // ALLOW(handlers): a matching condition of an op is asked in the op's own context (held item, arguments), which the engine passes

/obj/machinery/vending/proc/stock_record_for(obj/item/held)
	if(!istype(held))
		return null
	for(var/datum/stored_item/vending_product/R in product_records)
		if(istype(held, R.item_path) && (held.name == R.item_name)) // ALLOW(reads): a record's type and name are fixed when the vendor is built; asked when an item is offered, never cached
			return R
	return null

/// The item goes into the product receptor.
/obj/machinery/vending/proc/stocked(datum/act/op/A)
	var/obj/item/W = A.held
	var/mob/user = A.actor
	var/datum/stored_item/vending_product/R = stock_record_for(W)
	if(!R || !user?.unEquip(W))
		return OP_REFUSED
	R.add_product(W)
	if(has_logs)
		do_logging(R, user)
	return OP_OK

/// The refill port is there.
/obj/machinery/vending/proc/refill_port(datum/act/A)
	return refillable

/// The machine is bolted down.
/obj/machinery/vending/proc/refill_secured(datum/act/A)
	return anchored

/// The cartridge in hand is made for this kind of vendor.
/obj/machinery/vending/proc/cartridge_fits(datum/act/op/A)
	var/obj/item/refill_cartridge/cart = A.held
	return istype(cart) && cart.can_refill(src)

/// The cartridge refills every product.
/obj/machinery/vending/proc/refilled(datum/act/op/A)
	refill_inventory()
	to_chat(A.actor, span_notice("You refill [src] using [A.held]."))
	return OP_OK

// ---- paying ----

/**
 *  Receive payment with cashmoney.
 *
 *  user is the mob who gets the change.
 */
/obj/machinery/vending/proc/pay_with_cash(obj/item/spacecash/cashmoney, mob/user)
	if(currently_vending().price > cashmoney.worth)

		// This is not a status display message, since it's something the character
		// themselves is meant to see BEFORE putting the money in
		to_chat(user, "[icon2html(cashmoney, user.client)] " + span_warning("That is not enough money."))
		return 0

	if(istype(cashmoney, /obj/item/spacecash))

		act_message(user, src, others = span_info("%U% inserts some cash into %T%."))
		cashmoney.worth -= currently_vending().price

		if(cashmoney.worth <= 0)
			consume(cashmoney, user)
		else
			cashmoney.update_icon()

	// Vending machines have no idea who paid with cash
	credit_purchase("(cash)")
	return 1

/**
 * Scan a card and attempt to transfer payment from associated account.
 *
 * Takes payment for whatever is the currently_vending item. Returns 1 if
 * successful, 0 if failed
 */
/obj/machinery/vending/proc/pay_with_card(obj/item/card/id/I, mob/M, pin)
	visible_message(span_info("[M] swipes a card through [src]."))
	play_sfx(src, SFX_MACHINES_ID_SWIPE)
	if(!purchase_with_id_card(I, M, GLOB.vendor_account.owner_name, name, "Purchase of [currently_vending().item_name]", currently_vending().price, GLOB.vendor_account, pin))
		return FALSE
	return 1

/**
 *  Add money for current purchase to the vendor account.
 *
 *  Called after the money has already been taken from the customer.
 */
/obj/machinery/vending/proc/credit_purchase(target as text)
	GLOB.vendor_account.credit(currently_vending().price, target, "Purchase of [currently_vending().item_name]", name)

// ---- the window and the touch ----

/// A touch that is shocked: an electrified vendor shocks whoever touches it, and a shock that lands opens nothing.
/obj/machinery/vending/proc/shock_guard(datum/act/op/A)
	if(seconds_electrified != 0 && shock(A.actor, 100))
		return OP_REFUSED
	return OP_OK

/// With the panel open the wires window opens beside the vendor's own.
/obj/machinery/vending/proc/open_wires_beside_the_window(datum/act/op/A)
	var/datum/wires/W = wire_set_of(src)
	if(W)
		W.Interact(A.actor)
	return OP_OK

/// The touch is a bare hand (a hand with something in it is for the item's own use).
/obj/machinery/vending/proc/bare_touch(datum/act/op/A)
	return isnull(A.held) // ALLOW(handlers): a matching condition of an op is asked in the op's own context (held item, arguments), which the engine passes

/// An ID or cash held to the machine opens it (anything else it is given is for stocking).
/obj/machinery/vending/proc/item_opens_window(datum/act/op/A)
	var/obj/item/held = A.held // ALLOW(handlers): a matching condition of an op is asked in the op's own context (held item, arguments), which the engine passes
	return !!(held.GetID() || istype(held, /obj/item/spacecash))

/// The customer can use a window (awake, not restrained).
/obj/machinery/vending/proc/customer_capable(datum/act/op/A)
	var/mob/user = A.actor
	return !user.stat && !user.restrained()

/// The log button: shown to someone whose card has the log access.
/obj/machinery/vending/proc/check_logs_op(datum/act/op/A)
	show_log(A.actor)
	return OP_OK

/obj/machinery/vending/proc/check_logs(mob/user)
	show_log(user)
	return TRUE

/obj/machinery/vending/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet_batched/vending),
	)

/// The window's data: products of the shown categories, the coin, the panel and the customer.
/obj/machinery/vending/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	var/list/listed_products = list()

	data["chargesMoney"] = has_prices ? TRUE : FALSE
	for(var/key = 1 to length(product_records))
		var/datum/stored_item/vending_product/I = product_records[key]

		if(!(I.category & categories))
			continue

		listed_products.Add(list(list(
			"key" = key,
			"name" = I.item_name,
			"desc" = I.item_desc,
			"price" = I.price,
			"color" = I.display_color,
			"isatom" = ispath(I.item_path, /atom),
			"path" = replacetext(replacetext("[I.item_path]", "/obj/item/", ""), "/", "-"),
			"amount" = I.get_amount()
		)))

	data["products"] = listed_products

	data["coin"] = coin ? coin.name : FALSE
	data["actively_vending"] = currently_vending()?.item_name

	if(panel_open(src))
		data["panel"] = 1
		data["speaker"] = shut_up ? 0 : 1
	else
		data["panel"] = 0

	data["guestNotice"] = "No valid ID card detected. Wear your ID, or present cash."
	data["userMoney"] = 0
	data["user"] = null
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		var/obj/item/card/id/C = H.GetIdCard()
		var/obj/item/spacecash/S = H.get_active_hand()
		if(istype(S))
			data["userMoney"] = S.worth
			data["guestNotice"] = "Accepting [S.initial_name]. You have: [S.worth]₮."
		else if(istype(C))
			var/datum/money_account/account = get_account(C.associated_account_number)
			if(istype(account))
				data["user"] = list(
					"name" = account.owner_name,
					"job" = C.rank ? C.rank : "No Job",
				)
				data["userMoney"] = account.money
			else
				data["guestNotice"] = "Unlinked ID detected. Present cash to pay."
	return data

// ---- vending ----

/// Why a purchase cannot start now (a /datum/msg type for the customer), or null. No side effects.
/obj/machinery/vending/proc/vend_refusal(mob/user)
	if(!vend_ready)
		return /datum/msg/vending/busy
	if(!vend_access_ok(user))
		return /datum/msg/vending/denied
	if(panel_open(src))
		return /datum/msg/vending/panel_open
	return null

/// The customer's ID gets them the product (or nothing is checked: an emagged vendor, a cut scanner wire, no access requirement).
/obj/machinery/vending/proc/vend_access_ok(mob/user)
	return allowed(user) || emag_emagged(src) || !scan_id

/// The product list entry the window key names, or null for a key that is not a listed product.
/obj/machinery/vending/proc/vend_record_of(key)
	var/number = ui_number(key, round_to = 1)
	if(isnull(number) || number < 1 || number > length(product_records))
		return null
	var/datum/stored_item/vending_product/R = product_records[number]
	if(!(R.category & categories)) // ALLOW(reads): a product record's category is fixed when the vendor is built; asked when a purchase is chosen, never cached
		return null
	return R

/// needs: the key names a product that is listed now.
/obj/machinery/vending/proc/vend_listed(datum/act/op/A)
	return !isnull(vend_record_of(A.args["vend"]))

/// needs: nothing is being vended.
/obj/machinery/vending/proc/vend_idle(datum/act/op/A)
	return vend_ready

/// needs: the service panel is shut.
/obj/machinery/vending/proc/vend_shut(datum/act/op/A)
	return !panel_open(src)

/// A customer without access is turned away with a beep and a flash, before anything is paid.
/obj/machinery/vending/proc/vend_access(datum/act/op/A, vend)
	if(vend_access_ok(A.actor))
		return OP_OK
	flick("[icon_state]-deny", src)
	play_sfx(src, SFX_MACHINES_DENIEDBEEP)
	A.reason = /datum/msg/vending/denied
	return OP_REFUSED

/// The card's account is protected by a PIN, the product costs money and no cash is held: the customer is asked for it.
/obj/machinery/vending/proc/pin_wanted(datum/act/op/A)
	var/datum/stored_item/vending_product/R = vend_record_of(A.args["vend"]) // ALLOW(handlers): a matching condition of an op is asked in the op's own context (held item, arguments), which the engine passes
	var/mob/user = A.actor
	if(!R || R.price <= 0 || !vend_access_for(user))
		return FALSE
	return customer_pays_by_pin_card(user)

/// The customer is let buy (ID access, an emagged vendor, a cut scanner wire, or no access requirement).
/obj/machinery/vending/proc/vend_access_for(mob/user)
	return !!user && vend_access_ok(user)

/// A human whose active hand holds no cash and whose card is of an account that wants its PIN. What the customer holds and wears is legacy mob state
/// and the account registry is a registry: both are read when a purchase is chosen, never cached by a menu.
/proc/customer_pays_by_pin_card(mob/user)
	READS_FROM()
	if(!ishuman(user))
		return FALSE
	var/mob/living/carbon/human/H = user
	if(istype(H.get_active_hand(), /obj/item/spacecash))
		return FALSE
	var/obj/item/card/id/pin_card = H.GetIdCard()
	return istype(pin_card) && id_card_needs_pin(pin_card)

/// The vend button: a free product goes out, a priced one is paid for first.
/obj/machinery/vending/proc/ui_vend(datum/act/op/A, vend)
	var/mob/user = A.actor
	var/datum/stored_item/vending_product/R = vend_record_of(vend)
	if(!R || R.get_amount() < 1)
		A.reason = /datum/msg/vending/unavailable
		return OP_REFUSED

	if(R.price <= 0)
		vend(R, user)
		return OP_OK

	if(issilicon(user)) //If the item is not free, provide feedback if a synth is trying to buy something.
		A.reason = /datum/msg/vending/lawed
		return OP_REFUSED
	if(!ishuman(user))
		return OP_REFUSED
	var/mob/living/carbon/human/H = user

	// A card whose account needs a PIN was asked for it (the prompt is the op's own step).
	var/pin
	var/datum/prompt/answered = A.answer
	if(answered)
		pin = answered.value
		if(isnull(pin))
			return OP_REFUSED

	set_vend_ready(FALSE) // From this point onwards, vendor is locked to performing this transaction only, until it is resolved.

	var/obj/item/card/id/C = H.GetIdCard()

	if(!GLOB.vendor_account || GLOB.vendor_account.suspended)
		flick("[icon_state]-deny", src)
		set_vend_ready(TRUE)
		A.reason = /datum/msg/vending/no_account
		return OP_REFUSED

	rel_set(src, nameof(currently_vending), R)

	var/paid = FALSE

	if(istype(H.get_active_hand(), /obj/item/spacecash))
		var/obj/item/spacecash/cash = H.get_active_hand()
		paid = pay_with_cash(cash, H)
	else if(istype(C, /obj/item/card))
		paid = pay_with_card(C, H, pin)
	else
		set_vend_ready(TRUE)
		flick("[icon_state]-deny", src)
		A.reason = /datum/msg/vending/no_payment
		return OP_REFUSED
	if(!paid)
		set_vend_ready(TRUE)
		A.reason = /datum/msg/vending/payment_failed
		return OP_REFUSED
	vend(currently_vending(), H) // vend will handle vend_ready
	return OP_OK

/obj/machinery/vending/proc/can_buy(datum/stored_item/vending_product/R, mob/user)
	if(!allowed(user) && !emag_emagged(src) && scan_id)
		to_chat(user, span_warning("Access denied."))	//Unless emagged of course
		flick("[icon_state]-deny",src)
		play_sfx(src, SFX_MACHINES_DENIEDBEEP)
		return FALSE
	if(R.get_amount() < 1)
		return FALSE
	return TRUE

/obj/machinery/vending/proc/vend(datum/stored_item/vending_product/R, mob/user)
	if(!can_buy(R, user))
		return

	if(!R.get_amount())
		to_chat(user, span_warning("[src] has ran out of that product."))
		set_vend_ready(TRUE)
		return

	set_vend_ready(FALSE) //One thing at a time!!

	if(R.category & CAT_COIN)
		if(!coin)
			to_chat(user, span_notice("You need to insert a coin to get this item."))
			set_vend_ready(TRUE)
			return
		if(coin.string_attached)
			if(prob(50))
				to_chat(user, span_notice("You successfully pull the coin out before \the [src] could swallow it."))
			else
				to_chat(user, span_notice("You weren't able to pull the coin out fast enough, the machine ate it, string and all."))
				consume(coin, user)
				own_take(src, nameof(coin))
		else
			consume(coin)
			own_take(src, nameof(coin))

	if(!COOLDOWN_TIMELEFT(src, reply_cooldown) && vend_reply)
		speak(vend_reply)
		COOLDOWN_START(src, reply_cooldown, vend_delay + 20 SECONDS)

	use_power(vend_power_usage)	//actuators and stuff
	flick("[icon_state]-vend",src)
	after(src, vend_delay, PROC_REF(finish_vend), with = list(R, user))

/obj/machinery/vending/proc/bonus_vend(datum/stored_item/vending_product/R)
	if(R && R.get_product(get_turf(src)))
		visible_message(span_infoplain(span_bold("\The [src]") + " clunks as it vends an additional item."))

/// after() callback: R or user may have been deleted during the vend delay and arrive as null; the
/// machine still resets (vend_ready) either way.
/obj/machinery/vending/proc/finish_vend(datum/stored_item/vending_product/R, mob/user)
	if(!R)
		set_vend_ready(TRUE)
		rel_clear(src, nameof(currently_vending))
		return
	if(user && has_trait(user, TRAIT_UNLUCKY) && prob(10))
		visible_message(span_infoplain(span_bold("\The [src]") + " clunks and fails to dispense any item."))
		playsound(src, "sound/[vending_sound]", 100, TRUE, 1)
		set_vend_ready(TRUE)
		rel_clear(src, nameof(currently_vending))
		return
	R.get_product(get_turf(src))
	if(has_logs)
		do_logging(R, user, 1)
	if(prob(1))
		after(src, 0.3 SECONDS, PROC_REF(bonus_vend), with = list(R))
	playsound(src, "sound/[vending_sound]", 100, 1, 1)

	GLOB.items_sold_shift_roundstat++

	set_vend_ready(TRUE)
	rel_clear(src, nameof(currently_vending))

/obj/machinery/vending/proc/do_logging(datum/stored_item/vending_product/R, mob/user, vending = 0)
	if(!R || !user)
		return
	if(user.GetIdCard())
		var/obj/item/card/id/tempid = user.GetIdCard()
		var/list/list_item = list()
		if(vending)
			list_item += "vend"
		else
			list_item += "stock"
		list_item += tempid.registered_name
		list_item += stationtime2text()
		list_item += R.item_name
		LAZYADD(log, list(list_item))

/obj/machinery/vending/proc/show_log(mob/user as mob)
	if(user.GetIdCard())
		var/obj/item/card/id/tempid = user.GetIdCard()
		if(req_log_access in tempid.GetAccess())
			// Vending Log now opens a structured TGUI panel.
			var/datum/dq_vending_log_panel/panel = new(name, user.name, log)
			panel.tgui_interact(user)
	else
		to_chat(user,span_warning("You do not have the required access to view the vending logs for this machine."))

// ---- timed work: electrified, shooting stock, pitching ----

/// Arms the machine's frame when it has timed work and none is pending. The frame re-arms itself while the work lasts, so a vendor with nothing to
/// do holds no timer.
/obj/machinery/vending/proc/timed_work_arm()
	if(QDELETED(src) || after_pending(src, "work"))
		return
	if(operable() && vend_has_timed_work())
		after(src, MACHINE_SERVICE_INTERVAL, PROC_REF(timed_work_frame), key = "work")

/// The machine's work may have started (a setting or its power changed).
/obj/machinery/vending/proc/timed_work_changed(datum/act/A)
	timed_work_arm()

/// One frame of the machine's own work: the shock runs down, it pitches, it shoots.
/obj/machinery/vending/proc/timed_work_frame()
	if(!operable() || !vend_has_timed_work())
		return

	if(seconds_electrified > 0)
		set_seconds_electrified(seconds_electrified - 1)

	//Pitch to the people!  Really sell it!
	if((COOLDOWN_FINISHED(src, slogan_cooldown)) && length(slogan_list) && (!shut_up) && prob(5))
		var/slogan = pick(slogan_list)
		speak(slogan)
		COOLDOWN_START(src, slogan_cooldown, slogan_delay)

	if(shoot_inventory && prob(shoot_inventory_chance))
		throw_item()

	timed_work_arm()

/obj/machinery/vending/proc/speak(message)
	if(has_stat(NOPOWER))
		return

	if(!message)
		return

	for(var/mob/O in hearers(src, null))
		O.show_message(span_npc_say(span_name("\The [src]") + " beeps, \"[message]\""),2)
	return

/// Broken and dark states replace the vendor's face; an open panel lays its own state over it.
/obj/machinery/vending/draw(datum/look/look)
	..()
	// A vendor draws these in its own states below, not as the capabilities' standard parts.
	look.hide(LOOK_PANEL_OPEN)
	look.hide(LOOK_WIRES)
	look.hide(LOOK_BROKEN)
	look.hide(LOOK_DARK)
	var/base = initial(icon_state)
	if(has_stat(BROKEN))
		look.state("[base]-broken")
	else if(!cap_powered())
		look.state("[base]-off")
	look.overlay("[base]-panel", when = panel_open(src))

//Oh no we're malfunctioning!  Dump out some product and break.
/obj/machinery/vending/proc/malfunction()
	for(var/datum/stored_item/vending_product/R in product_records)
		while(R.get_amount()>0)
			R.get_product(loc)
		break

	atom_break()
	return

//Somebody cut an important wire and now we're following a new definition of "pitch."
/obj/machinery/vending/proc/throw_item(forced_target)
	var/obj/item/throw_item = null
	var/mob/living/target = locate_in_list(view(7,src), /mob/living)
	if(forced_target && isliving(forced_target))
		target = forced_target

	if(!target)
		return 0

	if(target.is_incorporeal()) // Don't shoot at things that aren't there.
		return 0

	for(var/datum/stored_item/vending_product/R in shuffle(product_records))
		throw_item = R.get_product(loc)
		if(!throw_item)
			continue
		break
	if(!throw_item)
		return FALSE
	throw_item.vendor_action(src)
	throw_item.throw_at(target, rand(3, 10), rand(1, 3), src)
	visible_message(span_warning("\The [src] launches \a [throw_item] at \the [target]!"))
	return 1

//Actual machines are in vending_machines.dm

/// What we're requesting payment for right now (a relation view: null once it is deleted).
/obj/machinery/vending/proc/currently_vending() as /datum/stored_item/vending_product
	return currently_vending
