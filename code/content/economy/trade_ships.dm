/// A visiting trade ship: a data-only profile of a vessel that docks at the
/// station's trade lanes for a while, sells a cargo of supply packs below the
/// catalog price, buys goods above the spot price, and ships specific goods
/// in on request for a markup. A ship trades under one of the market's fixed
/// counterparties, so its standing, faction and settlement records are that
/// counterparty's. The fixed counterparties keep their own listings and bids.
/datum/trade_ship_profile
	abstract_type = /datum/trade_ship_profile
	var/id
	var/name
	var/description
	/// The fixed counterparty (its `id`) the ship trades for.
	var/counterparty_id
	/// How long the ship stays docked.
	var/stay_time = 15 MINUTES
	/// Its cargo sells at this fraction of the catalog price (before standing).
	var/sell_rate = 0.8
	/// What it wants, it pays this multiple of the spot price for (before standing).
	var/buy_rate = 1.6
	/// A specific pack shipped in on request costs this multiple of the catalog price.
	var/special_markup = 1.5
	var/listing_count = 5
	var/bid_count = 2
	/// Relative chance of being the next ship to call.
	var/weight = 10

/// Supply pack groups the ship's cargo is drawn from.
TYPE_TABLE_DECLARE(/datum/trade_ship_profile, ship_cargo_groups, list())
/// Market profiles (/datum/cargo_market_profile paths) the ship buys.
TYPE_TABLE_DECLARE(/datum/trade_ship_profile, ship_wanted_profiles, list())
/// Supply pack groups the ship will ship in to order.
TYPE_TABLE_DECLARE(/datum/trade_ship_profile, ship_special_groups, list())

/datum/trade_ship_profile/guild_trader
	id = "guild_trader"
	name = "ITV Bountiful Margin"
	description = "A Traders' Guild bulk freighter running a general-goods circuit along the frontier."
	counterparty_id = "itg_exchange"
	weight = 14

TYPE_TABLE(/datum/trade_ship_profile/guild_trader, ship_cargo_groups, list("Materials", "Miscellaneous", "Recreation", "Costumes", "Hospitality"))
TYPE_TABLE(/datum/trade_ship_profile/guild_trader, ship_wanted_profiles, list(/datum/cargo_market_profile/frontier_salvage, /datum/cargo_market_profile/general_manufactured, /datum/cargo_market_profile/materials))
TYPE_TABLE(/datum/trade_ship_profile/guild_trader, ship_special_groups, list("Materials", "Miscellaneous", "Recreation", "Costumes", "Hospitality", "Hydroponics", "Supplies"))

/datum/trade_ship_profile/talon_outfitter
	id = "talon_outfitter"
	name = "Talon Freighter Kestrel's Due"
	description = "A Talon outfitting tender carrying suits and engineering stock for independent crews."
	counterparty_id = "talon_outfitters"
	sell_rate = 0.82
	buy_rate = 1.55

TYPE_TABLE(/datum/trade_ship_profile/talon_outfitter, ship_cargo_groups, list("Hardsuits", "Voidsuits", "Engineering", "Atmospherics"))
TYPE_TABLE(/datum/trade_ship_profile/talon_outfitter, ship_wanted_profiles, list(/datum/cargo_market_profile/frontier_salvage, /datum/cargo_market_profile/engineering_goods))
TYPE_TABLE(/datum/trade_ship_profile/talon_outfitter, ship_special_groups, list("Hardsuits", "Voidsuits", "Engineering", "Atmospherics", "Robotics"))

/datum/trade_ship_profile/veymed_barge
	id = "veymed_barge"
	name = "VMS Gentle Hand"
	description = "A Vey-Med hospital barge restocking clinics and buying medical output."
	counterparty_id = "veymed_distribution"
	sell_rate = 0.78
	buy_rate = 1.65
	weight = 8

TYPE_TABLE(/datum/trade_ship_profile/veymed_barge, ship_cargo_groups, list("Medical", "Robotics"))
TYPE_TABLE(/datum/trade_ship_profile/veymed_barge, ship_wanted_profiles, list(/datum/cargo_market_profile/medical_goods, /datum/cargo_market_profile/research_goods))
TYPE_TABLE(/datum/trade_ship_profile/veymed_barge, ship_special_groups, list("Medical", "Robotics", "Science"))

/datum/trade_ship_profile/union_hauler
	id = "union_hauler"
	name = "Union Hauler Steady Wage"
	description = "A Workers' Union cooperative hauler trading staples and buying food and tools."
	counterparty_id = "union_cooperative"
	sell_rate = 0.75
	buy_rate = 1.5

TYPE_TABLE(/datum/trade_ship_profile/union_hauler, ship_cargo_groups, list("Supplies", "Materials", "Hospitality", "Hydroponics"))
TYPE_TABLE(/datum/trade_ship_profile/union_hauler, ship_wanted_profiles, list(/datum/cargo_market_profile/food, /datum/cargo_market_profile/engineering_goods, /datum/cargo_market_profile/materials))
TYPE_TABLE(/datum/trade_ship_profile/union_hauler, ship_special_groups, list("Supplies", "Materials", "Hospitality", "Hydroponics", "Vendor Refills"))

/datum/trade_ship_profile/chimera_tender
	id = "chimera_tender"
	name = "Chimera Biologics Tender Sporeline"
	description = "A Chimera survey tender with seed stock and a standing interest in station research."
	counterparty_id = "chimera_biologics"
	sell_rate = 0.8
	buy_rate = 1.7
	weight = 6

TYPE_TABLE(/datum/trade_ship_profile/chimera_tender, ship_cargo_groups, list("Hydroponics", "Medical", "Science"))
TYPE_TABLE(/datum/trade_ship_profile/chimera_tender, ship_wanted_profiles, list(/datum/cargo_market_profile/food, /datum/cargo_market_profile/research_goods))
TYPE_TABLE(/datum/trade_ship_profile/chimera_tender, ship_special_groups, list("Hydroponics", "Medical", "Science"))

/// One ship's stay at the station. Its listings and bids are ordinary market
/// listings and bids (they carry its id) that expire when it departs.
/datum/trade_ship_visit
	var/id
	var/datum/trade_ship_profile/profile
	var/name
	var/counterparty_id
	var/arrived_at = 0
	COOLDOWN_DECLARE(departs_at)
	/// Market listing and bid ids the ship opened.
	var/list/listing_ids
	var/list/bid_ids

CAPABILITIES(/datum/trade_ship_visit)
	owns_one(nameof(profile), /datum/trade_ship_profile)

/datum/cargo_market_listing
	/// The visiting ship (its visit id) selling this, or null for a fixed counterparty.
	var/visit_id

/datum/cargo_market_bid
	/// The visiting ship (its visit id) buying against this, or null for a fixed counterparty.
	var/visit_id

/datum/system/supply
	/// Docked trade ships, keyed by visit id.
	var/list/trade_ship_visits
	COOLDOWN_DECLARE(next_trade_ship)

/datum/system/supply/proc/initialize_trade_ships()
	rel_clear(src, nameof(trade_ship_visits))
	COOLDOWN_START(src, next_trade_ship, TRADE_SHIP_FIRST_ARRIVAL)

/datum/system/supply/proc/trade_ship(visit_id) as /datum/trade_ship_visit
	return trade_ship_visits?[visit_id]

/// The schedule: depart ships whose stay is over, then call the next one when it is due.
/datum/system/supply/proc/process_trade_ships()
	var/list/visit_ids = trade_ship_visits?.Copy()
	for(var/visit_id in visit_ids)
		var/datum/trade_ship_visit/visit = trade_ship_visits?[visit_id]
		if(COOLDOWN_LAPSED(visit, departs_at))
			depart_trade_ship(visit)
	if(!COOLDOWN_LAPSED(src, next_trade_ship))
		return
	COOLDOWN_START(src, next_trade_ship, rand(TRADE_SHIP_MIN_INTERVAL, TRADE_SHIP_MAX_INTERVAL))
	if(length(trade_ship_visits) >= TRADE_SHIP_MAX_DOCKED)
		log_game("Trade ships: arrival skipped, [length(trade_ship_visits)] ships already docked.")
		return
	var/profile_path = pick_trade_ship_profile()
	if(profile_path)
		arrive_trade_ship(profile_path)

/// A profile not already docked, picked by weight (null when every one is docked).
/datum/system/supply/proc/pick_trade_ship_profile()
	var/list/docked = list()
	for(var/visit_id in trade_ship_visits)
		var/datum/trade_ship_visit/visit = trade_ship_visits[visit_id]
		docked[visit.profile.type] = TRUE
	var/list/weights = list()
	for(var/profile_path in subtypesof(/datum/trade_ship_profile))
		if(is_abstract(profile_path) || docked[profile_path])
			continue
		var/datum/trade_ship_profile/prototype = profile_path
		if(!market_counterparties?[initial(prototype.counterparty_id)])
			continue
		weights[profile_path] = initial(prototype.weight)
	return length(weights) ? pickweight(weights) : null

/// The standing discount or premium a ship gives the station: -0.15..+0.15 across the reputation range.
/datum/system/supply/proc/trade_ship_standing_factor(datum/trade_ship_visit/visit)
	var/datum/cargo_market_counterparty/counterparty = market_counterparties?[visit?.counterparty_id]
	var/standing = CLAMP(cargo_market_standing(counterparty), REPUTATION_HATED, REPUTATION_REVERED)
	return standing / REPUTATION_REVERED * 0.15

/// The price a docked ship asks for `pack`: its sell rate, better with standing.
/datum/system/supply/proc/trade_ship_sell_price(datum/trade_ship_visit/visit, datum/supply_pack/pack)
	return max(1, round(pack_price(pack) * visit.profile.sell_rate * (1 - trade_ship_standing_factor(visit))))

/// What a ship charges to ship `pack` in on request.
/datum/system/supply/proc/trade_ship_special_price(datum/trade_ship_visit/visit, datum/supply_pack/pack)
	return max(1, round(pack_price(pack) * visit.profile.special_markup * (1 - trade_ship_standing_factor(visit))))

/// Dock a ship of `profile_path`: open its listings and bids until it departs. Returns the visit.
/datum/system/supply/proc/arrive_trade_ship(profile_path) as /datum/trade_ship_visit
	var/datum/trade_ship_profile/profile = new profile_path
	var/datum/cargo_market_counterparty/counterparty = market_counterparties?[profile.counterparty_id]
	if(!counterparty)
		log_game("Trade ships: [profile.name] has no counterparty [profile.counterparty_id]; not docking.")
		spent(profile)
		return null
	var/datum/trade_ship_visit/visit = new
	visit.id = "SHIP-[next_serial(market)]"
	rel_set(visit, nameof(visit.profile), profile)
	visit.name = profile.name
	visit.counterparty_id = counterparty.id
	STAMP(visit, arrived_at, CLOCK_WORLD)
	COOLDOWN_START(visit, departs_at, profile.stay_time)
	rel_add(src, nameof(trade_ship_visits), visit, visit.id)
	var/expiry = visit.departs_at
	var/list/eligible_packs = list()
	var/list/groups = TYPE_TABLE_GET(profile, ship_cargo_groups)
	for(var/pack_name in supply_pack)
		var/datum/supply_pack/pack = supply_pack[pack_name]
		if((pack.group in groups) && !pack.contraband)
			eligible_packs += pack
	for(var/listing_index in 1 to min(profile.listing_count, length(eligible_packs)))
		var/datum/supply_pack/selected_pack = pick_n_take(eligible_packs)
		var/datum/cargo_market_listing/listing = new
		listing.id = "MKT-L-[next_serial(market)]"
		listing.counterparty_id = counterparty.id
		listing.visit_id = visit.id
		listing.pack = selected_pack
		listing.unit_price = trade_ship_sell_price(visit, selected_pack)
		listing.stock = rand(2, 5)
		listing.expires_at = expiry
		listing.cover_name = visit.name
		rel_add(src, nameof(market_listings), listing, listing.id)
		LAZYADD(visit.listing_ids, listing.id)
	var/list/profile_paths = TYPE_TABLE_COPY(profile, ship_wanted_profiles)
	for(var/bid_index in 1 to min(profile.bid_count, length(profile_paths)))
		var/wanted_path = pick_n_take(profile_paths)
		var/datum/cargo_market_profile/wanted = new wanted_path
		var/datum/cargo_market_bid/bid = new
		bid.id = "MKT-B-[next_serial(market)]"
		bid.counterparty_id = counterparty.id
		bid.visit_id = visit.id
		rel_set(bid, nameof(bid.profile), wanted)
		bid.target_units = rand(wanted.minimum_units, wanted.maximum_units)
		bid.price_multiplier = max(1.05, round(profile.buy_rate * (1 + trade_ship_standing_factor(visit)), 0.01))
		bid.expires_at = expiry
		bid.cover_name = visit.name
		rel_add(src, nameof(market_bids), bid, bid.id)
		LAZYADD(visit.bid_ids, bid.id)
	log_game("Trade ships: [visit.name] ([visit.id], for [counterparty.name]) docked for [DisplayTimeText(profile.stay_time)] with [LAZYLEN(visit.listing_ids)] listings and [LAZYLEN(visit.bid_ids)] bids.")
	announce_trade_ship(visit, TRADE_SHIP_ARRIVED)
	return visit

/// Undock `visit`: its listings and bids close. Orders already placed keep their quoted price.
/datum/system/supply/proc/depart_trade_ship(datum/trade_ship_visit/visit)
	if(!visit || trade_ship_visits?[visit.id] != visit)
		return FALSE
	for(var/listing_id in visit.listing_ids)
		if(market_listings?[listing_id])
			rel_add(src, nameof(market_listings), null, listing_id) // disposes of the owned listing
	for(var/bid_id in visit.bid_ids)
		if(market_bids?[bid_id])
			rel_add(src, nameof(market_bids), null, bid_id) // disposes of the owned bid
	log_game("Trade ships: [visit.name] ([visit.id]) departed.")
	announce_trade_ship(visit, TRADE_SHIP_DEPARTED)
	rel_add(src, nameof(trade_ship_visits), null, visit.id) // disposes of the owned visit
	return TRUE

/datum/system/supply/proc/announce_trade_ship(datum/trade_ship_visit/visit, event)
	var/message = event == TRADE_SHIP_ARRIVED ? "[visit.name] has entered the trade lane and is taking orders at the supply console for [DisplayTimeText(visit.profile.stay_time)]." : "[visit.name] has left the trade lane."
	GLOB.global_announcer?.autosay(message, "Traffic Control", CHANNEL_SUPPLY)

/// A ship's listing or bid stays through market refreshes while the ship is docked.
/datum/system/supply/proc/trade_ship_holds(visit_id)
	return visit_id && trade_ship_visits?[visit_id]

/// The packs `visit` will ship in to order.
/datum/system/supply/proc/trade_ship_special_packs(datum/trade_ship_visit/visit)
	var/list/packs = list()
	var/list/groups = TYPE_TABLE_GET(visit.profile, ship_special_groups)
	for(var/pack_name in supply_pack)
		var/datum/supply_pack/pack = supply_pack[pack_name]
		if((pack.group in groups) && !pack.contraband)
			packs += pack
	return packs

/// Order `pack` shipped in by `visit`: an ordinary supply order at the ship's special-order price.
/datum/system/supply/proc/request_special_order(datum/trade_ship_visit/visit, datum/supply_pack/pack, mob/living/user, reason, personal_funding = FALSE)
	if(!visit || trade_ship_visits?[visit.id] != visit || !(pack in trade_ship_special_packs(visit)))
		return FALSE
	var/price = trade_ship_special_price(visit, pack)
	var/datum/supply_order/order = create_order(pack, user, reason, personal_funding, null, visit.counterparty_id, price)
	if(!order)
		log_game("Trade ships: special order of [pack.name] from [visit.name] by [key_name(user)] failed (funding).")
		return FALSE
	order.set_market_cover_name(visit.name)
	for(var/datum/supply_order/admin_order in adm_order_history)
		if(admin_order.ordernum == order.ordernum)
			admin_order.set_market_cover_name(visit.name)
			break
	log_game("Trade ships: [key_name(user)] special-ordered [pack.name] from [visit.name] for [price] Thalers (order #[order.ordernum], [personal_funding ? "personal" : "department"]).")
	return order

/datum/system/supply/proc/trade_ship_ui_data(mob/living/user, station_trade_authorized = FALSE)
	var/list/ships = list()
	var/datum/money_account/viewer_account = contract_account_for_mob(user)
	for(var/visit_id in trade_ship_visits)
		var/datum/trade_ship_visit/visit = trade_ship_visits[visit_id]
		var/datum/cargo_market_counterparty/counterparty = market_counterparties?[visit.counterparty_id]
		var/list/specials = list()
		for(var/datum/supply_pack/pack as anything in trade_ship_special_packs(visit))
			specials.Add(list(list(
				"name" = pack.name,
				"group" = pack.group,
				"price" = trade_ship_special_price(visit, pack),
				"catalog" = pack_price(pack),
			)))
		ships.Add(list(list(
			"id" = visit.id,
			"name" = visit.name,
			"description" = visit.profile.description,
			"counterparty" = counterparty?.name,
			"standing" = cargo_market_standing(counterparty),
			"standing_tier" = reputation_rank(cargo_market_standing(counterparty)),
			"departs" = DisplayTimeText(max(0, visit.departs_at - world.time), 1),
			"sell_rate" = visit.profile.sell_rate,
			"buy_rate" = visit.profile.buy_rate,
			"special_markup" = visit.profile.special_markup,
			"specials" = specials,
			"can_department" = station_trade_authorized,
			"can_personal" = !!viewer_account,
		)))
	return list(
		"ships" = ships,
		"next_ship" = DisplayTimeText(max(0, next_trade_ship - world.time), 1),
	)
