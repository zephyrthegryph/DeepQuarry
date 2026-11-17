// Haggling with visiting trade ships. A crate on the supply shuttle is appraised at a supply console, then offered to a
// docked ship at a price the player names. The ship values the crate from what the spot market would pay for its
// contents, how much of it the ship wants (the profiles of its buy bids), the station's standing with its faction and
// the ship's mood, then accepts, counters or rejects. An accepted deal ships the crate at once and pays Cargo.

/// A handheld cargo appraiser: held while appraising at a supply console, it narrows the estimate's error.
/obj/item/cargo_appraiser
	name = "cargo appraiser"
	desc = "A handheld freight scanner with live commodity feeds. Hold it while appraising a crate at a supply console for a far tighter estimate."
	icon = 'icons/obj/device.dmi'
	icon_state = "deep_scan_device"
	w_class = ITEMSIZE_SMALL

/obj/structure/closet/crate
	/// The last appraisal of this crate at a supply console: an estimate in Thalers, its claimed error and who made it.
	var/trade_appraisal = 0
	var/trade_appraisal_spread = 0
	var/trade_appraiser
	/// Each appraiser's fixed misjudgement of this crate (name -> -1..1, scaled by their spread): appraising again does not average it away.
	var/list/trade_appraisal_bias

/// One offer to a docked ship for one crate: the ask, the ship's reply, and the ship's patience left for it.
/datum/trade_offer
	var/id
	var/obj/structure/closet/crate/crate
	var/crate_name
	var/offered_by
	var/offered_by_account = 0
	var/ask = 0
	var/counter = 0
	var/status = TRADE_OFFER_OPEN
	var/patience = TRADE_OFFER_PATIENCE
	var/rounds = 0
	var/last_reply
	var/settled_price = 0

CAPABILITIES(/datum/trade_offer)
	ref_one(nameof(crate))

/datum/trade_ship_visit
	/// The ship's mood this visit: scales what it pays, soured by insulting offers.
	var/mood = 1
	/// Offers made to this ship, keyed by offer id.
	var/list/trade_offers

/// The appraisal error a person brings: a fraction of the true value. Cargo staff read freight better; an appraiser in hand reads it far better.
/datum/system/supply/proc/trade_appraisal_spread(mob/living/user)
	var/spread = TRADE_APPRAISAL_SPREAD_UNTRAINED
	if(ishuman(user))
		var/mob/living/carbon/human/human_user = user
		if(human_user.job in list(JOB_QUARTERMASTER, JOB_CARGO_TECHNICIAN))
			spread = TRADE_APPRAISAL_SPREAD_TRAINED
	if(user?.is_holding_item_of_type(/obj/item/cargo_appraiser))
		spread *= TRADE_APPRAISAL_TOOL_FACTOR
	return spread

/// What the spot market would pay for `crate` as it stands, in Thalers: the crate fee plus each sellable thing in it.
/datum/system/supply/proc/trade_crate_spot_value(obj/structure/closet/crate/crate)
	if(!crate)
		return 0
	var/points = crate.points_per_crate
	for(var/obj/thing in crate)
		var/value = thing.scan_profit()
		if(isnum(value) && value > 0)
			points += value
	return export_revenue(points)

/// The share (0..1) of `crate`'s spot value that `visit` wants: things matching one of its open buy bids.
/datum/system/supply/proc/trade_crate_wanted_share(datum/trade_ship_visit/visit, obj/structure/closet/crate/crate)
	var/total = 0
	var/wanted = 0
	for(var/obj/thing in crate)
		var/value = thing.scan_profit()
		if(!isnum(value) || value <= 0)
			continue
		total += value
		for(var/bid_id in visit.bid_ids)
			var/datum/cargo_market_bid/bid = market_bid(bid_id)
			if(bid && bid.profile.matches(thing))
				wanted += value
				break
	return total > 0 ? wanted / total : 0

/// What `visit` thinks `crate` is worth to it, in Thalers.
/datum/system/supply/proc/trade_ship_valuation(datum/trade_ship_visit/visit, obj/structure/closet/crate/crate)
	var/spot = trade_crate_spot_value(crate)
	var/want = 1 + trade_crate_wanted_share(visit, crate) * (visit.profile.buy_rate - 1)
	return round(spot * want * (1 + trade_ship_standing_factor(visit)) * visit.mood)

/// Appraise `crate` for `user`: an estimate that is off by up to the person's spread. Returns the estimate.
/datum/system/supply/proc/appraise_trade_crate(obj/structure/closet/crate/crate, mob/living/user)
	if(!crate_is_on_supply_shuttle(crate))
		return null
	return estimate_trade_crate(crate, user)

/// The appraisal itself, once appraise_trade_crate() has checked the crate is aboard the shuttle.
/datum/system/supply/proc/estimate_trade_crate(obj/structure/closet/crate/crate, mob/living/user)
	var/spread = trade_appraisal_spread(user)
	var/spot = trade_crate_spot_value(crate)
	var/appraiser_key = user?.name || "unknown"
	if(isnull(LAZYACCESS(crate.trade_appraisal_bias, appraiser_key)))
		LAZYSET(crate.trade_appraisal_bias, appraiser_key, rand() * 2 - 1)
	var/error = crate.trade_appraisal_bias[appraiser_key] * spread
	crate.trade_appraisal = max(0, round(spot * (1 + error)))
	crate.trade_appraisal_spread = spread
	crate.trade_appraiser = user?.name
	log_game("Trade offers: [key_name(user)] appraised [crate.name] at [crate.trade_appraisal] Thalers (spot [spot], spread [round(spread * 100)]%).")
	return crate.trade_appraisal

/// The open offer for `crate` to `visit`, if any.
/datum/system/supply/proc/trade_offer_for(datum/trade_ship_visit/visit, obj/structure/closet/crate/crate) as /datum/trade_offer
	for(var/offer_id in visit?.trade_offers)
		var/datum/trade_offer/offer = visit.trade_offers[offer_id]
		if(offer.crate == crate && (offer.status in list(TRADE_OFFER_OPEN, TRADE_OFFER_COUNTERED)))
			return offer
	return null

/datum/system/supply/proc/trade_offer(datum/trade_ship_visit/visit, offer_id) as /datum/trade_offer
	return visit?.trade_offers?[offer_id]

/// `user` offers `crate` to `visit` for `ask` Thalers. The ship accepts (the deal settles at once), counters or rejects.
/// Returns the offer, or null when no offer could be made.
/datum/system/supply/proc/make_trade_offer(datum/trade_ship_visit/visit, obj/structure/closet/crate/crate, ask, mob/living/user)
	if(!visit || trade_ship_visits?[visit.id] != visit || !crate_is_on_supply_shuttle(crate) || crate.anchored)
		return null
	return negotiate_trade_offer(visit, crate, ask, user)

/// The negotiation itself, once make_trade_offer() has checked the crate is aboard the shuttle.
/datum/system/supply/proc/negotiate_trade_offer(datum/trade_ship_visit/visit, obj/structure/closet/crate/crate, ask, mob/living/user)
	if(!isnum(ask))
		return null
	if(ask < 1)
		return null
	var/datum/trade_offer/offer = trade_offer_for(visit, crate)
	if(!offer)
		for(var/offer_id in visit.trade_offers)
			var/datum/trade_offer/old = visit.trade_offers[offer_id]
			if(old.crate == crate && old.status == TRADE_OFFER_WALKED)
				log_game("Trade offers: [visit.name] refused [key_name(user)]'s new offer for [crate.name]; it walked away from this crate.")
				return old
		offer = new
		offer.id = "OFR-[next_serial(market)]"
		rel_set(offer, nameof(offer.crate), crate)
		offer.crate_name = crate.name
		rel_add(visit, nameof(visit.trade_offers), offer, offer.id)
	offer.offered_by = user?.name
	offer.offered_by_account = contract_account_for_mob(user)?.account_number || 0
	offer.ask = ask
	offer.rounds++
	var/valuation = trade_ship_valuation(visit, crate)
	var/insult_line = valuation * TRADE_OFFER_COUNTER_CEILING
	if(valuation > 0 && ask <= valuation)
		offer.last_reply = "Accepted at [ask] Thalers."
		log_game("Trade offers: [visit.name] accepted [key_name(user)]'s ask of [ask] for [crate.name] (valuation [valuation], round [offer.rounds]).")
		settle_trade_offer(visit, offer, ask, user)
		return offer
	if(valuation > 0 && ask <= insult_line)
		offer.patience--
		// The ship meets a reasonable ask partway, closer to its own number as its patience runs out.
		var/meet = TRADE_OFFER_PATIENCE > 0 ? max(0, offer.patience) / TRADE_OFFER_PATIENCE : 0
		offer.counter = max(1, round(valuation + (ask - valuation) * 0.3 * meet))
		offer.status = TRADE_OFFER_COUNTERED
		offer.last_reply = "Countered at [offer.counter] Thalers."
	else
		offer.patience -= 2
		visit.mood = max(TRADE_SHIP_MOOD_MIN, visit.mood - TRADE_OFFER_INSULT_MOOD)
		offer.counter = 0
		offer.status = TRADE_OFFER_OPEN
		offer.last_reply = valuation > 0 ? "Rejected: that is far above what the ship will pay." : "Rejected: the ship sees nothing of value in that crate."
	if(offer.patience <= 0)
		offer.status = TRADE_OFFER_WALKED
		offer.counter = 0
		offer.last_reply = "The ship has stopped negotiating for this crate."
	log_game("Trade offers: [visit.name] answered [key_name(user)]'s ask of [ask] for [crate.name]: [offer.last_reply] (valuation [valuation], patience [offer.patience], mood [visit.mood]).")
	return offer

/// `user` takes the ship's standing counteroffer on `offer`.
/datum/system/supply/proc/accept_trade_counter(datum/trade_ship_visit/visit, datum/trade_offer/offer, mob/living/user)
	if(!visit || trade_ship_visits?[visit.id] != visit || offer?.status != TRADE_OFFER_COUNTERED || offer.counter <= 0)
		return FALSE
	if(!crate_is_on_supply_shuttle(offer.crate) || offer.crate.anchored)
		return FALSE
	return take_trade_counter(visit, offer, user)

/// Taking the counter, once accept_trade_counter() has checked the crate is aboard the shuttle.
/datum/system/supply/proc/take_trade_counter(datum/trade_ship_visit/visit, datum/trade_offer/offer, mob/living/user)
	if(!visit || trade_ship_visits?[visit.id] != visit || offer?.status != TRADE_OFFER_COUNTERED || offer.counter <= 0 || !offer.crate)
		return FALSE
	log_game("Trade offers: [key_name(user)] took [visit.name]'s counter of [offer.counter] for [offer.crate_name].")
	return settle_trade_offer(visit, offer, offer.counter, user)

/// Ship `offer`'s crate to `visit` for `price`. The contents are sold through the ordinary export path (so department
/// and producer shares are paid as on the shuttle) and the ship's price above that spot value is Cargo's premium. A
/// price below spot pays only the price, to Cargo. The crate is gone afterwards: nothing can be sold twice.
/datum/system/supply/proc/settle_trade_offer(datum/trade_ship_visit/visit, datum/trade_offer/offer, price, mob/living/user)
	var/obj/structure/closet/crate/crate = offer.crate
	if(!crate)
		return FALSE
	var/datum/exported_crate/export = new /datum/exported_crate()
	export.name = "\proper[crate.name]"
	export.set_value(0)
	export.set_rows(list())
	crate.apply_shipping_ledger(export)
	for(var/atom/thing in crate)
		thing.export_sale(export, TRUE)
	var/spot_points = export.value + crate.points_per_crate
	var/spot = export_revenue(spot_points)
	var/premium = 0
	if(price >= spot)
		distribute_export_revenue(export)
		credit_department(DEPARTMENT_CARGO, crate.points_per_crate, "Exported shipping crate")
		premium = price - spot
		if(premium > 0)
			adjust_budget(premium, "Negotiated sale to [visit.name]: [crate.name]")
	else
		adjust_budget(price, "Negotiated sale to [visit.name]: [crate.name]")
	export.set_value(round(price / export_revenue(1), 0.01))
	export.set_market_counterparty_id(visit.counterparty_id)
	export.set_market_cover_name(visit.name)
	export.set_market_premium(round(premium / export_revenue(1), 0.01))
	rel_add(src, nameof(exported_crates), export)
	var/datum/exported_crate/admin_copy = new
	admin_copy.name = export.name
	admin_copy.set_value(export.value)
	admin_copy.set_rows(deepCopyList(export.rows))
	admin_copy.set_market_counterparty_id(export.market_counterparty_id)
	admin_copy.set_market_cover_name(export.market_cover_name)
	admin_copy.set_market_premium(export.market_premium)
	rel_add(src, nameof(adm_export_history), admin_copy)
	var/datum/cargo_market_counterparty/counterparty = market_counterparties?[visit.counterparty_id]
	record_market_transaction(CARGO_MARKET_SELL, visit.counterparty_id, "Negotiated sale of [crate.name] to [visit.name]", price, offer.offered_by_account, visit.name)
	if(counterparty)
		adjust_station_faction_reputation(counterparty.faction_id, 1)
		adjust_department_faction_reputation(DEPARTMENT_CARGO, counterparty.faction_id, 3)
		if(offer.offered_by_account)
			adjust_personal_faction_reputation(offer.offered_by_account, counterparty.faction_id, 3)
	offer.status = TRADE_OFFER_SETTLED
	offer.settled_price = price
	offer.counter = 0
	offer.last_reply = "Sold for [price] Thalers."
	rel_clear(offer, nameof(offer.crate))
	log_game("Trade offers: [visit.name] bought [crate.name] for [price] Thalers (spot [spot], premium [premium]) from [key_name(user)].")
	spent(crate)
	return TRUE

/datum/system/supply/proc/trade_offer_ui_data(datum/trade_ship_visit/visit, mob/living/user)
	var/list/rows = list()
	for(var/offer_id in visit.trade_offers)
		var/datum/trade_offer/offer = visit.trade_offers[offer_id]
		rows.Insert(1, list(list(
			"id" = offer.id,
			"crate" = offer.crate_name,
			"crate_ref" = offer.crate ? handle_of(offer.crate) : null,
			"offered_by" = offer.offered_by,
			"ask" = offer.ask,
			"counter" = offer.counter,
			"status" = offer.status,
			"patience" = max(0, offer.patience),
			"reply" = offer.last_reply,
			"price" = offer.settled_price,
		)))
	return rows

/// The movable crates on the supply shuttle, with their last appraisal, for the haggling panel.
/datum/system/supply/proc/trade_crates_ui_data()
	var/list/crates = list()
	if(!shuttle)
		return crates
	for(var/area/subarea in shuttle.shuttle_area)
		for(var/obj/structure/closet/crate/crate in subarea)
			if(crate.anchored)
				continue
			crates.Add(list(list(
				"ref" = handle_of(crate),
				"name" = crate.name,
				"contents" = length(crate.contents),
				"appraisal" = crate.trade_appraisal,
				"spread" = round(crate.trade_appraisal_spread * 100),
				"appraiser" = crate.trade_appraiser,
			)))
	return crates

/datum/system/supply/proc/trade_ship_mood_text(datum/trade_ship_visit/visit)
	if(visit.mood >= 1.08)
		return "Eager"
	if(visit.mood >= 0.95)
		return "Businesslike"
	if(visit.mood >= 0.82)
		return "Guarded"
	return "Irritated"
