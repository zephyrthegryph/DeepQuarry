///
///		A vending machine
///

//
//	ALL THE VENDING MACHINES ARE IN vending_machines.dm now!
//

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
	var/vend_ready = 1 //Are we ready to vend?? Is it time??
	var/vend_delay = 10 //How long does it take to vend?
	var/categories = CAT_NORMAL // Bitmask of cats we're currently showing
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
	var/list/product_records = list() // ALLOW(instance_list): d: the vendor's live stock records (C9 turns these into slots)

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

	var/scan_id = 1
	var/obj/item/coin/coin

	var/list/log // Lazy: purchase log entries.
	var/req_log_access = ACCESS_CARGO //default access for checking logs is cargo
	var/has_logs = 0 //defaults to 0, set to anything else for vendor to have logs
	var/can_rotate = 1 //Defaults to yes, can be set to 0 for vendors without or with unwanted directionals.

/// Stop spouting those godawful pitches!
OM_FIELD(/obj/machinery/vending, shut_up, TRUE, CHANGE_MACHINE_SETTINGS)
/// Shock customers like an airlock: steps left (-1 for permanently, from a cut wire).
OM_FIELD(/obj/machinery/vending, seconds_electrified, 0, CHANGE_MACHINE_SETTINGS)
/// Fire items at customers! We're broken!
OM_FIELD(/obj/machinery/vending, shoot_inventory, 0, CHANGE_MACHINE_SETTINGS)
/// Active with something time-dependent to do: electrified, shooting inventory, or advertising.
/// slogan_list is filled once in Initialize() and never changes afterwards, so it is not an input.
OM_DERIVE_FIELD(/obj/machinery/vending, vend_has_timed_work, list("active", "seconds_electrified", "shoot_inventory", "shut_up"))
DECLARE_PERIODIC_WHILE_ALL(/obj/machinery/vending, MACHINE_PIPELINE, list("operable", "vend_has_timed_work"))

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

			own_add(src, "product_records", product)
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


DAMAGE_REACTION(/obj/machinery/vending, DAMAGE_EXPLOSION, PROC_REF(vending_blast_malfunction))

/// A light blast can jolt the vendor into malfunctioning.
/obj/machinery/vending/proc/vending_blast_malfunction(datum/damage_packet/packet)
	if(packet.severity == 3 && prob(25))
		malfunction()

/obj/machinery/vending/capabilities()
	. = ..()
	. += cap_panel(layer = CAP_NO_LAYER) // drawn in draw(): the panel state is "[icon_state]-panel", one per vendor icon
	. += cap_wires(/datum/wires/vending, behind = PANEL, layer = CAP_NO_LAYER)
	. += cap_emag(say = "You short out %T%'s product lock.", mode = EMAG_REPEATABLE)
	. += cap_anchor(delay = 2 SECONDS, needs_floor = FALSE, blocked_by = PANEL)
	. += cap_breakable(repair_tool = NONE, layer = CAP_NO_LAYER)
	. += cap_power(layer = CAP_NO_LAYER)
	// An ID card or cash held to the machine opens it, as the old attackby did.
	. += cap_use_on("Use", /obj/item, PROC_REF(open_window), needs = PROC_REF(wants_hand_dispatch), works_broken = TRUE, works_unpowered = TRUE)
	. += cap_use_on("Refill", /obj/item/refill_cartridge, PROC_REF(refill_from), needs = PROC_REF(refill_ok), blocked_by = PANEL)
	. += cap_use_on("Insert coin", /obj/item/fake_coin, PROC_REF(reject_fake_coin), needs = PROC_REF(has_premium_slot), else_say = "it has no coin slot", works_broken = TRUE, works_unpowered = TRUE)
	. += cap_slot(nameof(coin), /obj/item/coin, needs = PROC_REF(has_premium_slot), else_say = "it has no coin slot", eject_via = SLOT_VIA_NONE, ui_key = null)
	. += cap_insert("Stock", /obj/item, PROC_REF(stock_item), works_broken = TRUE)
	. += cap_hand("Use", PROC_REF(open_window), works_broken = TRUE, works_unpowered = TRUE)
	. += cap_hand("Check vending logs", PROC_REF(check_logs), works_broken = TRUE, works_unpowered = TRUE)

/// No side effects: whether an item held to the machine would open it (an ID or cash).
/obj/machinery/vending/proc/wants_hand_dispatch(mob/user, obj/item/held)
	return !!(held.GetID() || istype(held, /obj/item/spacecash))

/// No side effects.
/obj/machinery/vending/proc/has_premium_slot(mob/user, obj/item/held)
	return has_premium

/// No side effects: the refill port is there, and the machine is bolted down.
/obj/machinery/vending/proc/refill_ok(mob/user, obj/item/held)
	if(!refillable)
		return "it does not have a refill port"
	if(!anchored)
		return "you cannot refill it while it is not secured"
	return TRUE

/obj/machinery/vending/proc/refill_from(mob/user, obj/item/refill_cartridge/held)
	if(!held.can_refill(src))
		return refuse(user, "You cannot refill [src] with [held].")
	to_chat(user, span_notice("You refill [src] using [held]."))
	consume(held, user)
	refill_inventory()
	return TRUE

/// Fake coins are rejected when we take real coins.
/obj/machinery/vending/proc/reject_fake_coin(mob/user, obj/item/held)
	to_chat(user, span_notice("\The [held] doesn't fit into the coin slot on \the [src]."))
	return refuse(user, null)

/// The coin slot's hooks: a coin unlocks the premium products.
/obj/machinery/vending/slot_inserted(slot, obj/item/item, mob/user)
	if(slot == nameof(coin))
		categories |= CAT_COIN

/obj/machinery/vending/slot_ejected(slot, obj/item/item, mob/user)
	if(slot == nameof(coin))
		categories &= ~CAT_COIN

/// The final "anything else" branch: restock a matching product, else decline so the click falls on.
/obj/machinery/vending/proc/stock_item(mob/user, obj/item/held)
	for(var/datum/stored_item/vending_product/R in product_records)
		if(istype(held, R.item_path) && (held.name == R.item_name))
			stock(held, R, user)
			return TRUE
	return FALSE

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
 * Scan a chargecard and deduct payment from it.
 *
 * Takes payment for whatever is the currently_vending item. Returns 1 if
 * successful, 0 if failed.
 */
/obj/machinery/vending/proc/pay_with_ewallet(obj/item/spacecash/ewallet/wallet, mob/user)
	act_message(user, src, others = span_info("%U% swipes %I% through %T%."), item = wallet)
	play_sfx(src, SFX_MACHINES_ID_SWIPE)
	if(currently_vending().price > wallet.worth)
		to_chat(user, span_warning("Insufficient funds on chargecard."))
		return 0
	else
		wallet.worth -= currently_vending().price
		credit_purchase("[wallet.owner_name] (chargecard)")
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

/// The Use entries' handler: the window, and with the panel open the wires, unless the shock gets you.
/obj/machinery/vending/proc/open_window(mob/user, obj/item/held)
	if(!operable())
		return refuse(user, null)
	if(seconds_electrified != 0 && shock(user, 100))
		return refuse(user, null)
	wires_of(src).Interact(user)
	tgui_interact(user)
	return TRUE

/obj/machinery/vending/proc/check_logs(mob/user)
	show_log(user)
	return TRUE

/obj/machinery/vending/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet_batched/vending),
	)

/obj/machinery/vending
	tgui_id = "Vending"

/// The computed window data: products of the shown categories, the coin, the panel and the customer.
/obj/machinery/vending/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	var/list/data = .
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

	if(panel_is_open(src))
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
			var/datum/money_account/A = get_account(C.associated_account_number)
			if(istype(A))
				data["user"] = list(
					"name" = A.owner_name,
					"job" = C.rank ? C.rank : "No Job",
				)
				data["userMoney"] = A.money
			else
				data["guestNotice"] = "Unlinked ID detected. Present cash to pay."

/// The type-wide gate: it has to be working and the customer able to use it.
/obj/machinery/vending/ui_allowed(mob/user, action)
	if(!..())
		return FALSE
	return operable() && !user.stat && !user.restrained()

/obj/machinery/vending/ui_logged()
	return list("vend" = LOG_GAME)

/obj/machinery/vending/proc/act_remove_coin(mob/user)
	if(issilicon(user))
		return refuse(user, null)
	if(!coin)
		return refuse(user, "There is no coin in this machine.")
	slot_eject(nameof(coin), user)
	return TRUE

/// Why `user` can't start a purchase right now (text, for them), or null. A denied ID flicks and
/// beeps, as it always did.
/obj/machinery/vending/proc/vend_refusal(mob/user)
	if(!vend_ready)
		return "[src] is busy!"
	if(!allowed(user) && !is_emagged(src) && scan_id)
		flick("[icon_state]-deny", src)
		play_sfx(src, SFX_MACHINES_DENIEDBEEP)
		return "Access denied." //Unless emagged of course
	if(panel_is_open(src))
		return "[src] cannot dispense products while its service panel is open!"
	return null

/obj/machinery/vending/proc/act_vend(mob/user, vend)
	var/key = ui_number(vend, round_to = 1)
	if(isnull(key) || key < 1 || key > length(product_records))
		return refuse(user, null)
	var/datum/stored_item/vending_product/R = product_records[key]
	if(!(R.category & categories))
		return refuse(user, null)
	var/refusal = vend_refusal(user)
	if(refusal)
		return refuse(user, refusal)
	if(!can_buy(R, user))
		return refuse(user, null)

	if(R.price <= 0)
		vend(R, user)
		return TRUE

	if(issilicon(user)) //If the item is not free, provide feedback if a synth is trying to buy something.
		to_chat(user, span_danger("Lawed unit recognized.  Lawed units cannot complete this transaction.  Purchase canceled."))
		return refuse(user, null)
	if(!ishuman(user))
		return refuse(user, null)
	var/mob/living/carbon/human/H = user

	// Card payments ask for the PIN first, and the vendor may have moved on by the time it is answered.
	var/pin
	if(!istype(H.get_active_hand(), /obj/item/spacecash))
		var/obj/item/card/id/pin_card = H.GetIdCard()
		if(istype(pin_card) && id_card_needs_pin(pin_card))
			pin = ask_number(H, "Enter pin code", title = "Vendor transaction")
			if(isnull(pin))
				return refuse(user, null)
			refusal = vend_refusal(user)
			if(refusal)
				return refuse(user, refusal)
			if(!can_buy(R, user))
				return refuse(user, null)

	vend_ready = FALSE // From this point onwards, vendor is locked to performing this transaction only, until it is resolved.

	var/obj/item/card/id/C = H.GetIdCard()

	if(!GLOB.vendor_account || GLOB.vendor_account.suspended)
		flick("[icon_state]-deny", src)
		vend_ready = TRUE
		return refuse(user, "Vendor account offline. Unable to process transaction.")

	rel_set(src, nameof(currently_vending), R)

	var/paid = FALSE

	if(istype(H.get_active_hand(), /obj/item/spacecash))
		var/obj/item/spacecash/cash = H.get_active_hand()
		paid = pay_with_cash(cash, H)
	else if(istype(H.get_active_hand(), /obj/item/spacecash/ewallet))
		var/obj/item/spacecash/ewallet/wallet = H.get_active_hand()
		paid = pay_with_ewallet(wallet, H)
	else if(istype(C, /obj/item/card))
		paid = pay_with_card(C, H, pin)
	else
		vend_ready = TRUE
		flick("[icon_state]-deny", src)
		return refuse(user, "Payment failure: you have no ID or other method of payment.")
	if(!paid)
		vend_ready = TRUE
		return refuse(user, "Payment failure: unable to process payment.")
	vend(currently_vending(), H) // vend will handle vend_ready
	return TRUE

/obj/machinery/vending/proc/act_toggle_voice(mob/user)
	if(!panel_is_open(src))
		return refuse(user, null)
	set_shut_up(!shut_up)
	return TRUE

/obj/machinery/vending/proc/can_buy(datum/stored_item/vending_product/R, mob/user)
	if(!allowed(user) && !is_emagged(src) && scan_id)
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
		vend_ready = TRUE
		return

	vend_ready = FALSE //One thing at a time!!

	if(R.category & CAT_COIN)
		if(!coin)
			to_chat(user, span_notice("You need to insert a coin to get this item."))
			vend_ready = TRUE
			return
		if(coin.string_attached)
			if(prob(50))
				to_chat(user, span_notice("You successfully pull the coin out before \the [src] could swallow it."))
			else
				to_chat(user, span_notice("You weren't able to pull the coin out fast enough, the machine ate it, string and all."))
				consume(coin, user)
				own_take(src, nameof(coin))
				categories &= ~CAT_COIN
		else
			consume(coin)
			own_take(src, nameof(coin))
			categories &= ~CAT_COIN

	if(!COOLDOWN_TIMELEFT(src, reply_cooldown) && vend_reply)
		speak(vend_reply)
		COOLDOWN_START(src, reply_cooldown, vend_delay + 20 SECONDS)

	use_power(vend_power_usage)	//actuators and stuff
	flick("[icon_state]-vend",src)
	after(src, vend_delay, PROC_REF(finish_vend), R, user)

/obj/machinery/vending/proc/bonus_vend(datum/stored_item/vending_product/R)
	if(R.get_product(get_turf(src)))
		visible_message(span_infoplain(span_bold("\The [src]") + " clunks as it vends an additional item."))

/obj/machinery/vending/proc/finish_vend(datum/stored_item/vending_product/R, mob/user)
	if(has_trait(user, TRAIT_UNLUCKY) && prob(10))
		visible_message(span_infoplain(span_bold("\The [src]") + " clunks and fails to dispense any item."))
		playsound(src, "sound/[vending_sound]", 100, TRUE, 1)
		vend_ready = 1
		rel_clear(src, nameof(currently_vending))
		return
	R.get_product(get_turf(src))
	if(has_logs)
		do_logging(R, user, 1)
	if(prob(1))
		after(src, 0.3 SECONDS, PROC_REF(bonus_vend), R)
	playsound(src, "sound/[vending_sound]", 100, 1, 1)

	GLOB.items_sold_shift_roundstat++

	vend_ready = 1
	rel_clear(src, nameof(currently_vending))

/obj/machinery/vending/proc/do_logging(datum/stored_item/vending_product/R, mob/user, vending = 0)
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

/**
 * Add item to the machine
 *
 * Checks if item is vendable in this machine should be performed before
 * calling. W is the item being inserted, R is the associated vending_product entry.
 */
/obj/machinery/vending/proc/stock(obj/item/W, datum/stored_item/vending_product/R, mob/user)
	if(!user.unEquip(W))
		return

	to_chat(user, span_notice("You insert \the [W] in the product receptor."))
	R.add_product(W)
	if(has_logs)
		do_logging(R, user)

/obj/machinery/vending/machine_step()
	// Normal silent vendors have no time-dependent state. Hacked vendors and
	// explicitly enabled advertisers wake through their mutation paths below.
	if(seconds_electrified <= 0 && !shoot_inventory && (shut_up || !length(slogan_list)))
		return PROCESS_KILL

	if(seconds_electrified > 0)
		set_seconds_electrified(seconds_electrified - 1)

	//Pitch to the people!  Really sell it!
	if((COOLDOWN_FINISHED(src, slogan_cooldown)) && length(slogan_list) && (!shut_up) && prob(5))
		var/slogan = pick(slogan_list)
		speak(slogan)
		COOLDOWN_START(src, slogan_cooldown, slogan_delay)

	if(shoot_inventory && prob(shoot_inventory_chance))
		throw_item()

	return

/obj/machinery/vending/proc/speak(message)
	if(has_stat(NOPOWER))
		return

	if(!message)
		return

	for(var/mob/O in hearers(src, null))
		O.show_message(span_npc_say(span_name("\The [src]") + " beeps, \"[message]\""),2)
	return

/obj/machinery/vending/power_change()
	. = ..()
	// machine_step() sleeps on NOPOWER; resume timed work on restore.
	if(!has_stat(BROKEN) && !has_stat(NOPOWER) && vend_has_timed_work())
		MACHINE_WAKE(src)

/// Broken and dark states replace the vendor's face; an open panel lays its own state over it.
/obj/machinery/vending/draw(datum/look/look)
	..()
	var/base = initial(icon_state)
	if(is_broken(src))
		look.state("[base]-broken")
	else if(!cap_powered())
		look.state("[base]-off")
	look.overlay("[base]-panel", when = panel_is_open(src))

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
