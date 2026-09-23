/// A reusable description of goods an external buyer will accept. Market
/// demand is expressed as ordinary type paths and economic provenance; it does
/// not require dedicated export items or shipment machinery.
/datum/cargo_market_profile
	abstract_type = /datum/cargo_market_profile
	var/id
	var/name = "General freight"
	var/description = "Commercially useful station freight."
	var/minimum_units = 4
	var/maximum_units = 12
	var/base_price_multiplier = 1.25

/datum/cargo_market_profile/proc/accepted_type_paths() as /list
	return list()

/datum/cargo_market_profile/proc/accepted_departments() as /list
	return list()

/datum/cargo_market_profile/proc/matches(obj/item)
	if(!istype(item))
		return FALSE
	var/list/type_paths = accepted_type_paths()
	if(length(type_paths))
		var/type_match = FALSE
		for(var/type_path in type_paths)
			if(istype(item, type_path))
				type_match = TRUE
				break
		if(!type_match)
			return FALSE
	var/list/departments = accepted_departments()
	if(length(departments) && !(item.economic_department in departments))
		return FALSE
	return length(type_paths) || item.economic_export_value > 0

/datum/cargo_market_profile/materials
	id = "materials"
	name = "Bulk construction materials"
	description = "Processed material stacks suitable for industrial resale."
	minimum_units = 20
	maximum_units = 80
	base_price_multiplier = 1.3

/datum/cargo_market_profile/materials/accepted_type_paths()
	var/static/list/paths = list(/obj/item/stack/material)
	return paths

/datum/cargo_market_profile/research_goods
	id = "research_goods"
	name = "Research prototypes"
	description = "Traceable devices manufactured by the Research department."
	minimum_units = 3
	maximum_units = 8
	base_price_multiplier = 1.45

/datum/cargo_market_profile/research_goods/accepted_departments()
	var/static/list/departments = list(DEPARTMENT_RESEARCH)
	return departments

/datum/cargo_market_profile/engineering_goods
	id = "engineering_goods"
	name = "Engineering assemblies"
	description = "Station-built technical equipment with Engineering provenance."
	minimum_units = 3
	maximum_units = 9
	base_price_multiplier = 1.35

/datum/cargo_market_profile/engineering_goods/accepted_departments()
	var/static/list/departments = list(DEPARTMENT_ENGINEERING)
	return departments

/datum/cargo_market_profile/medical_goods
	id = "medical_goods"
	name = "Medical and biological products"
	description = "Preserved organs, vaccines, and other clinical products."
	minimum_units = 3
	maximum_units = 10
	base_price_multiplier = 1.5

/datum/cargo_market_profile/medical_goods/accepted_type_paths()
	var/static/list/paths = list(
		/obj/item/organ/internal,
		/obj/item/reagent_containers/glass/beaker/vial/vaccine,
	)
	return paths

/datum/cargo_market_profile/food
	id = "food"
	name = "Prepared provisions"
	description = "Prepared meals and packaged food for off-station distribution."
	minimum_units = 6
	maximum_units = 18
	base_price_multiplier = 1.3

/datum/cargo_market_profile/food/accepted_type_paths()
	var/static/list/paths = list(/obj/item/reagent_containers/food)
	return paths

/datum/cargo_market_profile/weapons
	id = "weapons"
	name = "Controlled armaments"
	description = "Weapons and ammunition accepted under the buyer's own end-user certification."
	minimum_units = 2
	maximum_units = 7
	base_price_multiplier = 1.55

/datum/cargo_market_profile/weapons/accepted_type_paths()
	var/static/list/paths = list(
		/obj/item/gun,
		/obj/item/ammo_casing,
		/obj/item/ammo_magazine,
	)
	return paths

/datum/cargo_market_profile/frontier_salvage
	id = "frontier_salvage"
	name = "Frontier salvage and samples"
	description = "Recovered salvage and catalogued research samples."
	minimum_units = 3
	maximum_units = 12
	base_price_multiplier = 1.4

/datum/cargo_market_profile/frontier_salvage/accepted_type_paths()
	var/static/list/paths = list(
		/obj/item/salvage,
		/obj/item/research_sample,
		/obj/item/storage/sample_container,
	)
	return paths

/datum/cargo_market_profile/general_manufactured
	id = "general_manufactured"
	name = "Station-manufactured goods"
	description = "Traceable station products from any operational department."
	minimum_units = 4
	maximum_units = 12
	base_price_multiplier = 1.25

/// One persistent external market participant. Listings and bids are temporary
/// round objects generated from these capabilities.
/datum/cargo_market_counterparty
	abstract_type = /datum/cargo_market_counterparty
	var/id
	var/name
	var/faction_id
	var/description
	var/seller_price_multiplier = 1
	var/buyer_price_multiplier = 1
	var/covert = FALSE
	var/allows_contraband = FALSE
	var/legal_class = CARGO_MARKET_LEGAL_PUBLIC
	var/active_cover_name

/datum/cargo_market_counterparty/proc/seller_groups() as /list
	return list()

/datum/cargo_market_counterparty/proc/buyer_profiles() as /list
	return list()

/datum/cargo_market_counterparty/proc/cover_names() as /list
	return list(name)

/datum/cargo_market_counterparty/proc/rotate_cover()
	var/list/names = cover_names()
	active_cover_name = length(names) ? pick(names) : name

/datum/cargo_market_counterparty/nanotrasen
	id = "nt_logistics"
	name = "NanoTrasen Central Logistics"
	faction_id = REPUTATION_FACTION_NANOTRASEN
	description = "The station operator's broad internal procurement and resale network."
	seller_price_multiplier = 0.95
	buyer_price_multiplier = 1.05

/datum/cargo_market_counterparty/nanotrasen/seller_groups()
	var/static/list/groups = list("Supplies", "Engineering", "Security", "Vendor Refills")
	return groups

/datum/cargo_market_counterparty/nanotrasen/buyer_profiles()
	var/static/list/profiles = list(/datum/cargo_market_profile/general_manufactured, /datum/cargo_market_profile/materials)
	return profiles

/datum/cargo_market_counterparty/solgov
	id = "solgov_procurement"
	name = "SolGov Civil Procurement Office"
	faction_id = REPUTATION_FACTION_SOLGOV
	description = "A regulated public-sector buyer and emergency-equipment supplier."

/datum/cargo_market_counterparty/solgov/seller_groups()
	var/static/list/groups = list("Security", "Medical", "Atmospherics")
	return groups

/datum/cargo_market_counterparty/solgov/buyer_profiles()
	var/static/list/profiles = list(/datum/cargo_market_profile/medical_goods, /datum/cargo_market_profile/food)
	return profiles

/datum/cargo_market_counterparty/chimera
	id = "chimera_biologics"
	name = "Chimera Biologics Exchange"
	faction_id = REPUTATION_FACTION_CHIMERA
	description = "A biotechnology exchange specializing in living products and clinical inputs."
	seller_price_multiplier = 1.05
	buyer_price_multiplier = 1.1

/datum/cargo_market_counterparty/chimera/seller_groups()
	var/static/list/groups = list("Hydroponics", "Medical")
	return groups

/datum/cargo_market_counterparty/chimera/buyer_profiles()
	var/static/list/profiles = list(/datum/cargo_market_profile/medical_goods, /datum/cargo_market_profile/food)
	return profiles

/datum/cargo_market_counterparty/eclipse
	id = "eclipse_acquisitions"
	name = "Eclipse Advanced Acquisitions"
	faction_id = REPUTATION_FACTION_ECLIPSE
	description = "A high-technology broker purchasing prototypes and supplying specialist hardware."
	seller_price_multiplier = 1.15
	buyer_price_multiplier = 1.15
	legal_class = CARGO_MARKET_LEGAL_RESTRICTED

/datum/cargo_market_counterparty/eclipse/seller_groups()
	var/static/list/groups = list("Science", "Robotics", "Munitions")
	return groups

/datum/cargo_market_counterparty/eclipse/buyer_profiles()
	var/static/list/profiles = list(/datum/cargo_market_profile/research_goods, /datum/cargo_market_profile/weapons)
	return profiles

/datum/cargo_market_counterparty/syndicate
	id = "syndicate_brokerage"
	name = "Red Ledger Brokerage"
	faction_id = REPUTATION_FACTION_SYNDICATE
	description = "An encrypted grey-market clearinghouse with no recognized legal identity."
	seller_price_multiplier = 1.25
	buyer_price_multiplier = 1.25
	covert = TRUE
	allows_contraband = TRUE
	legal_class = CARGO_MARKET_LEGAL_COVERT

/datum/cargo_market_counterparty/syndicate/cover_names()
	var/static/list/names = list(
		"Grey Meridian Medical",
		"Helix Transit Cooperative",
		"Kestrel Industrial Recovery",
		"Orpheus Research Brokerage",
		"Redwood Frontier Logistics",
	)
	return names

/datum/cargo_market_counterparty/syndicate/seller_groups()
	var/static/list/groups = list("Munitions", "Miscellaneous", "Supplies")
	return groups

/datum/cargo_market_counterparty/syndicate/buyer_profiles()
	var/static/list/profiles = list(/datum/cargo_market_profile/weapons, /datum/cargo_market_profile/research_goods, /datum/cargo_market_profile/medical_goods)
	return profiles

/datum/cargo_market_counterparty/traders_guild
	id = "itg_exchange"
	name = "Interstellar Traders' Guild Exchange"
	faction_id = REPUTATION_FACTION_TRADERS_GUILD
	description = "A competitive clearinghouse for independent merchants and freeport wholesalers."
	seller_price_multiplier = 0.9
	buyer_price_multiplier = 1.1

/datum/cargo_market_counterparty/traders_guild/seller_groups()
	var/static/list/groups = list("Miscellaneous", "Materials", "Recreation", "Costumes")
	return groups

/datum/cargo_market_counterparty/traders_guild/buyer_profiles()
	var/static/list/profiles = list(/datum/cargo_market_profile/general_manufactured, /datum/cargo_market_profile/frontier_salvage)
	return profiles

/datum/cargo_market_counterparty/talon
	id = "talon_outfitters"
	name = "TALON Frontier Outfitters"
	faction_id = REPUTATION_FACTION_TALON
	description = "A frontier outfitter trading in field equipment, salvage, and expedition supplies."

/datum/cargo_market_counterparty/talon/seller_groups()
	var/static/list/groups = list("Hardsuits", "Voidsuits", "Engineering", "Atmospherics")
	return groups

/datum/cargo_market_counterparty/talon/buyer_profiles()
	var/static/list/profiles = list(/datum/cargo_market_profile/frontier_salvage, /datum/cargo_market_profile/engineering_goods)
	return profiles

/datum/cargo_market_counterparty/workers_union
	id = "union_cooperative"
	name = "Workers' Union Cooperative"
	faction_id = REPUTATION_FACTION_WORKERS_UNION
	description = "A worker-owned purchasing cooperative focused on tools, provisions, and locally made goods."
	seller_price_multiplier = 0.95

/datum/cargo_market_counterparty/workers_union/seller_groups()
	var/static/list/groups = list("Materials", "Supplies", "Hospitality")
	return groups

/datum/cargo_market_counterparty/workers_union/buyer_profiles()
	var/static/list/profiles = list(/datum/cargo_market_profile/food, /datum/cargo_market_profile/engineering_goods, /datum/cargo_market_profile/general_manufactured)
	return profiles

/datum/cargo_market_counterparty/veymed
	id = "veymed_distribution"
	name = "Vey-Medical Distribution"
	faction_id = REPUTATION_FACTION_VEYMED
	description = "Vey-Medical's clinical supply and biological product exchange."
	seller_price_multiplier = 1.05
	buyer_price_multiplier = 1.15

/datum/cargo_market_counterparty/veymed/seller_groups()
	var/static/list/groups = list("Medical", "Robotics")
	return groups

/datum/cargo_market_counterparty/veymed/buyer_profiles()
	var/static/list/profiles = list(/datum/cargo_market_profile/medical_goods, /datum/cargo_market_profile/research_goods)
	return profiles

/datum/cargo_market_listing
	var/id
	var/counterparty_id
	var/datum/supply_pack/pack
	var/unit_price = 0
	var/stock = 0
	var/expires_at = 0
	var/cover_name
	var/reservation_key
	var/reserved_account = 0
	var/retired = FALSE

/datum/cargo_market_listing/Destroy()
	pack = null
	return ..()

/datum/cargo_market_bid
	var/id
	var/counterparty_id
	var/datum/cargo_market_profile/profile
	var/target_units = 0
	var/fulfilled_units = 0
	var/price_multiplier = 1
	var/expires_at = 0
	var/completed_at = 0
	var/cover_name
	var/reservation_key
	var/reserved_account = 0

/datum/cargo_market_bid/Destroy()
	QDEL_NULL(profile)
	return ..()

/datum/cargo_market_bid/proc/remaining_units()
	return max(0, target_units - fulfilled_units)

/datum/cargo_market_transaction
	var/id
	var/transaction_type
	var/counterparty_id
	var/cover_name
	var/description
	var/value = 0
	var/account_number = 0
	var/principal_account = 0
	var/occurred_at = 0
	var/covert = FALSE
	var/trace_strength = 0
	var/detected = FALSE
	var/detected_account = 0
	var/detected_contact_account = 0
	var/list/audited_accounts
	var/reservation_key

/datum/cargo_market_transaction/New()
	. = ..()
	audited_accounts = list()

/datum/cargo_market_transaction/Destroy()
	audited_accounts = null
	return ..()

/obj/structure/closet/crate
	/// Optional routing selected at the Cargo console. Unmatched contents still
	/// receive the ordinary spot-market price rather than being destroyed.
	var/cargo_market_bid_id
	var/cargo_market_router_account = 0
	var/cargo_market_contract_key

/datum/exported_crate
	var/market_bid_id
	var/market_counterparty_id
	var/market_router_account = 0
	var/market_premium = 0
	var/market_cover_name
	var/market_contract_key

/datum/supply_order
	var/market_listing_id
	var/market_counterparty_id
	var/market_requester_account = 0
	var/quoted_price = 0
	var/market_stock_reserved = FALSE
	var/market_cover_name
	var/market_contract_key
	var/market_contract_funded = FALSE

/datum/controller/subsystem/supply
	var/list/market_counterparties
	var/list/market_listings
	var/list/market_bids
	var/list/market_transactions
	var/next_market_id = 1
	var/next_market_refresh = 0
	var/market_generation = 0

/datum/controller/subsystem/supply/proc/initialize_cargo_market()
	QDEL_LIST(market_counterparties)
	QDEL_LIST(market_listings)
	QDEL_LIST(market_bids)
	QDEL_LIST(market_transactions)
	market_counterparties = list()
	market_listings = list()
	market_bids = list()
	market_transactions = list()
	next_market_id = 1
	market_generation = 0
	for(var/counterparty_type as anything in subtypesof(/datum/cargo_market_counterparty))
		if(is_abstract(counterparty_type))
			continue
		var/datum/cargo_market_counterparty/counterparty = new counterparty_type
		counterparty.rotate_cover()
		market_counterparties[counterparty.id] = counterparty
	refresh_cargo_market()

/datum/controller/subsystem/supply/proc/cargo_market_standing(datum/cargo_market_counterparty/counterparty)
	if(!counterparty?.faction_id)
		return REPUTATION_NEUTRAL
	var/station_standing = get_station_faction_reputation(counterparty.faction_id)
	var/cargo_standing = get_department_faction_reputation(DEPARTMENT_CARGO, counterparty.faction_id)
	if(!isnum(cargo_standing))
		cargo_standing = station_standing
	return round((station_standing + cargo_standing) / 2)

/datum/controller/subsystem/supply/proc/cargo_market_seller_price(datum/cargo_market_counterparty/counterparty, datum/supply_pack/pack)
	var/standing = CLAMP(cargo_market_standing(counterparty), REPUTATION_HATED, REPUTATION_REVERED)
	var/reputation_factor = 1 - (standing / 3000)
	var/market_factor = rand(90, 115) / 100
	return max(1, round(pack_price(pack) * counterparty.seller_price_multiplier * reputation_factor * market_factor))

/datum/controller/subsystem/supply/proc/cargo_market_buyer_multiplier(datum/cargo_market_counterparty/counterparty, datum/cargo_market_profile/profile)
	var/standing = CLAMP(cargo_market_standing(counterparty), REPUTATION_HATED, REPUTATION_REVERED)
	var/reputation_factor = 1 + (standing / 5000)
	var/market_factor = rand(90, 115) / 100
	return max(1.05, round(profile.base_price_multiplier * counterparty.buyer_price_multiplier * reputation_factor * market_factor, 0.01))

/datum/controller/subsystem/supply/proc/refresh_cargo_market()
	var/list/retained_listings = list()
	for(var/listing_id in market_listings)
		var/datum/cargo_market_listing/existing_listing = market_listings[listing_id]
		if(existing_listing.reservation_key && existing_listing.stock > 0 && world.time < existing_listing.expires_at)
			retained_listings[listing_id] = existing_listing
		else
			qdel(existing_listing)
	var/list/retained_bids = list()
	for(var/bid_id in market_bids)
		var/datum/cargo_market_bid/existing_bid = market_bids[bid_id]
		if(existing_bid.reservation_key && !existing_bid.completed_at && world.time < existing_bid.expires_at)
			retained_bids[bid_id] = existing_bid
		else
			qdel(existing_bid)
	market_listings = retained_listings
	market_bids = retained_bids
	market_generation++
	var/expiry = world.time + CARGO_MARKET_REFRESH_INTERVAL
	for(var/counterparty_id in market_counterparties)
		var/datum/cargo_market_counterparty/counterparty = market_counterparties[counterparty_id]
		counterparty.rotate_cover()
		var/list/eligible_packs = list()
		var/list/groups = counterparty.seller_groups()
		for(var/pack_name in supply_pack)
			var/datum/supply_pack/pack = supply_pack[pack_name]
			if(!(pack.group in groups) || (!counterparty.allows_contraband && pack.contraband))
				continue
			eligible_packs += pack
		for(var/listing_index in 1 to min(CARGO_MARKET_LISTINGS_PER_PARTY, length(eligible_packs)))
			var/datum/supply_pack/selected_pack = pick_n_take(eligible_packs)
			var/datum/cargo_market_listing/listing = new
			listing.id = "MKT-L-[next_market_id++]"
			listing.counterparty_id = counterparty.id
			listing.pack = selected_pack
			listing.unit_price = cargo_market_seller_price(counterparty, selected_pack)
			listing.stock = rand(1, 4)
			listing.expires_at = expiry
			listing.cover_name = counterparty.active_cover_name
			market_listings[listing.id] = listing
		var/list/profile_paths = counterparty.buyer_profiles().Copy()
		for(var/bid_index in 1 to min(CARGO_MARKET_BIDS_PER_PARTY, length(profile_paths)))
			var/profile_path = pick_n_take(profile_paths)
			var/datum/cargo_market_profile/profile = new profile_path
			var/datum/cargo_market_bid/bid = new
			bid.id = "MKT-B-[next_market_id++]"
			bid.counterparty_id = counterparty.id
			bid.profile = profile
			bid.target_units = rand(profile.minimum_units, profile.maximum_units)
			bid.price_multiplier = cargo_market_buyer_multiplier(counterparty, profile)
			bid.expires_at = expiry
			bid.cover_name = counterparty.active_cover_name
			market_bids[bid.id] = bid
	next_market_refresh = expiry

/datum/controller/subsystem/supply/proc/process_cargo_market()
	if(world.time >= next_market_refresh)
		refresh_cargo_market()

/datum/controller/subsystem/supply/proc/market_counterparty_visible(datum/cargo_market_counterparty/counterparty, mob/living/user, console_unlocked = FALSE)
	if(!counterparty?.covert)
		return TRUE
	return console_unlocked || has_faction_market_access(user, counterparty.faction_id)

/datum/controller/subsystem/supply/proc/market_true_identity_visible(datum/cargo_market_counterparty/counterparty, mob/living/user)
	if(!counterparty?.covert)
		return TRUE
	var/datum/money_account/account = contract_account_for_mob(user)
	var/datum/faction_agent_record/record = account && GLOB.station_faction_relations.get_agent_record(account.account_number)
	return record?.faction_id == counterparty.faction_id

/datum/controller/subsystem/supply/proc/market_display_name(datum/cargo_market_counterparty/counterparty, mob/living/user, cover_name)
	if(!counterparty)
		return "Spot market"
	if(market_true_identity_visible(counterparty, user))
		return counterparty.name
	return cover_name || counterparty.active_cover_name || "Independent brokerage"

/datum/controller/subsystem/supply/proc/market_reserved_access(reserved_account, mob/living/user, reservation_key)
	if(!reserved_account)
		return TRUE
	var/datum/money_account/account = contract_account_for_mob(user)
	if(!account)
		return FALSE
	if(account.account_number == reserved_account)
		return TRUE
	var/datum/contract/faction_agent/contact_contract = SScontracts?.agent_contact_contract(account.account_number, null, reservation_key)
	return contact_contract?.owner_account_number == reserved_account

/datum/controller/subsystem/supply/proc/market_counterparty_access(datum/cargo_market_counterparty/counterparty, mob/living/user, console_unlocked = FALSE)
	if(!counterparty)
		return FALSE
	if(counterparty.legal_class == CARGO_MARKET_LEGAL_COVERT)
		return console_unlocked || has_faction_market_access(user, counterparty.faction_id)
	return TRUE

/datum/controller/subsystem/supply/proc/market_listing(listing_id) as /datum/cargo_market_listing
	return market_listings?[listing_id]

/datum/controller/subsystem/supply/proc/market_bid(bid_id) as /datum/cargo_market_bid
	return market_bids?[bid_id]

/datum/controller/subsystem/supply/proc/order_price(datum/supply_order/order)
	return order?.quoted_price > 0 ? order.quoted_price : pack_price(order.object)

/datum/controller/subsystem/supply/proc/market_contract_funding(reservation_key, mob/living/user, price) as /datum/contract/faction_agent
	if(!reservation_key || !isnum(price) || price <= 0)
		return null
	var/datum/money_account/account = contract_account_for_mob(user)
	for(var/datum/contract/faction_agent/contract in SScontracts?.active_contracts)
		if(contract.offer_key != reservation_key || !market_reserved_access(contract.owner_account_number, user, reservation_key))
			continue
		if(contract.market_allowance - contract.market_spend >= price && account)
			return contract
	return null

/datum/controller/subsystem/supply/proc/request_market_order(datum/cargo_market_listing/listing, mob/living/user, reason, console_unlocked = FALSE, personal_funding = FALSE, contract_funding = FALSE)
	var/datum/cargo_market_counterparty/counterparty = market_counterparties?[listing?.counterparty_id]
	if(!listing || listing.retired || !counterparty || listing.stock <= 0 || world.time >= listing.expires_at || !market_counterparty_access(counterparty, user, console_unlocked) || !market_reserved_access(listing.reserved_account, user, listing.reservation_key))
		return FALSE
	var/datum/contract/faction_agent/funding_contract
	if(contract_funding)
		funding_contract = market_contract_funding(listing.reservation_key, user, listing.unit_price)
		if(!funding_contract)
			return FALSE
	listing.stock--
	var/datum/supply_order/order = create_order(
		listing.pack,
		user,
		reason,
		personal_funding && !contract_funding,
		listing.id,
		counterparty.id,
		listing.unit_price,
	)
	if(!order)
		listing.stock++
		return FALSE
	order.market_stock_reserved = TRUE
	order.market_cover_name = listing.cover_name
	order.market_contract_key = listing.reservation_key
	if(funding_contract)
		funding_contract.market_spend += listing.unit_price
		order.personal_order = TRUE
		order.funding_account_number = funding_contract.owner_account_number
		order.paid_amount = listing.unit_price
		order.market_contract_funded = TRUE
	for(var/datum/supply_order/admin_order in adm_order_history)
		if(admin_order.ordernum == order.ordernum)
			admin_order.market_stock_reserved = TRUE
			admin_order.market_cover_name = listing.cover_name
			admin_order.market_contract_key = listing.reservation_key
			admin_order.personal_order = order.personal_order
			admin_order.funding_account_number = order.funding_account_number
			admin_order.paid_amount = order.paid_amount
			admin_order.market_contract_funded = order.market_contract_funded
			break
	return order

/datum/controller/subsystem/supply/proc/release_market_contract_funding(datum/supply_order/order)
	if(!order?.market_contract_funded || !order.market_contract_key || order.paid_amount <= 0)
		return FALSE
	for(var/datum/contract/faction_agent/contract in SScontracts?.active_contracts + SScontracts?.grace_contracts)
		if(contract.offer_key != order.market_contract_key)
			continue
		contract.market_spend = max(0, contract.market_spend - order.paid_amount)
		break
	order.market_contract_funded = FALSE
	return TRUE

/datum/controller/subsystem/supply/proc/release_market_order_reservation(datum/supply_order/order)
	if(!order?.market_stock_reserved)
		return FALSE
	var/datum/cargo_market_listing/listing = market_listing(order.market_listing_id)
	if(listing && !listing.retired && world.time < listing.expires_at)
		listing.stock++
	order.market_stock_reserved = FALSE
	return TRUE

/datum/controller/subsystem/supply/proc/complete_market_order(datum/supply_order/order)
	if(!order?.market_counterparty_id)
		return FALSE
	order.market_stock_reserved = FALSE
	var/datum/cargo_market_counterparty/counterparty = market_counterparties[order.market_counterparty_id]
	var/datum/cargo_market_listing/listing = market_listing(order.market_listing_id)
	if(!counterparty)
		return FALSE
	var/datum/cargo_market_transaction/transaction = record_market_transaction(CARGO_MARKET_BUY, counterparty.id, "Purchased [order.object.name] (order #[order.ordernum])", order.paid_amount, order.market_requester_account, order.market_cover_name, order.market_contract_key)
	adjust_station_faction_reputation(counterparty.faction_id, 1)
	adjust_department_faction_reputation(order.funding_department, counterparty.faction_id, 2)
	if(order.market_requester_account)
		adjust_personal_faction_reputation(order.market_requester_account, counterparty.faction_id, 4)
	emit_contract_event(CONTRACT_EVENT_CARGO_MARKET_PURCHASE, list(
		"actor_account" = order.market_requester_account,
		"principal_account" = listing?.reserved_account,
		"department" = order.funding_department,
		"funding_department" = order.funding_department,
		"counterparty_id" = counterparty.id,
		"faction_id" = counterparty.faction_id,
		"listing_id" = order.market_listing_id,
		"market_contract_key" = order.market_contract_key,
		"market_transaction_id" = transaction?.id,
		"market_funding" = order.market_contract_funded ? CARGO_MARKET_FUNDING_CONTRACT : (order.personal_order ? CARGO_MARKET_FUNDING_PERSONAL : CARGO_MARKET_FUNDING_DEPARTMENT),
		"order_id" = order.ordernum,
		"pack_type" = order.object.type,
		"pack_group" = order.object.group,
		"contraband" = !!order.object.contraband,
		"fact_id" = "market-purchase:[order.ordernum]",
		"fact_revision" = 1,
		"fact_active" = TRUE,
		"metrics" = list("value" = order.paid_amount, "quantity" = 1),
		"detail" = "External market order #[order.ordernum] arrived.",
	), "market-purchase:[order.ordernum]")
	return TRUE

/datum/controller/subsystem/supply/proc/record_market_transaction(transaction_type, counterparty_id, description, value, account_number = 0, cover_name, reservation_key) as /datum/cargo_market_transaction
	var/datum/cargo_market_transaction/transaction = new
	transaction.id = "MKT-T-[next_market_id++]"
	transaction.transaction_type = transaction_type
	transaction.counterparty_id = counterparty_id
	transaction.cover_name = cover_name
	transaction.description = description
	transaction.value = max(0, round(value))
	transaction.account_number = account_number
	transaction.occurred_at = world.time
	transaction.reservation_key = reservation_key
	var/datum/cargo_market_counterparty/counterparty = market_counterparties?[counterparty_id]
	var/datum/contract/faction_agent/agent_contract = SScontracts?.agent_contract_for_market_key(reservation_key)
	transaction.principal_account = agent_contract?.owner_account_number || account_number
	transaction.covert = counterparty?.legal_class == CARGO_MARKET_LEGAL_COVERT || agent_contract?.red_contract || agent_contact_risk_rank(agent_contract?.contact_mode) >= 2
	if(transaction.covert)
		var/risk_multiplier = agent_contract ? agent_contact_risk_rank(agent_contract.contact_mode) : 1
		transaction.trace_strength = CLAMP(round((8 + sqrt(max(0, transaction.value)) / 3 + (reservation_key ? 5 : 0)) * risk_multiplier), 1, CARGO_MARKET_TRACE_LIMIT)
		GLOB.station_faction_relations.add_agent_exposure(transaction.principal_account, counterparty.faction_id, max(1, round(transaction.trace_strength / 5)), "Encrypted market traffic accumulated forensic metadata.", transaction.id)
	log_game("Cargo market [transaction.id]: [transaction_type] [transaction.value] Thalers with [counterparty?.name || counterparty_id] by account [account_number || "unknown"] (cover: [transaction.cover_name || "none"], reservation: [reservation_key || "none"]).")
	market_transactions += transaction
	if(length(market_transactions) > CARGO_MARKET_TRANSACTION_LIMIT)
		var/datum/cargo_market_transaction/oldest = market_transactions[1]
		market_transactions.Cut(1, 2)
		qdel(oldest)
	return transaction

/datum/controller/subsystem/supply/proc/apply_market_demand(obj/item, datum/exported_crate/export, list/export_row)
	if(!istype(item) || !export?.market_bid_id || !islist(export_row))
		return FALSE
	var/datum/cargo_market_bid/bid = market_bid(export.market_bid_id)
	var/datum/cargo_market_counterparty/counterparty = market_counterparties?[bid?.counterparty_id]
	if(!bid || !counterparty || bid.completed_at || world.time >= bid.expires_at || !bid.profile.matches(item))
		return FALSE
	var/reported_quantity = export_row["quantity"]
	var/quantity = isnum(reported_quantity) ? max(1, reported_quantity) : 1
	var/matched_quantity = min(quantity, bid.remaining_units())
	if(matched_quantity <= 0)
		return FALSE
	var/base_value = max(0, export_row["value"])
	var/matched_base_value = base_value * matched_quantity / quantity
	var/market_value = round(matched_base_value * bid.price_multiplier)
	var/premium = max(0, market_value - matched_base_value)
	export_row["value"] = base_value + premium
	export_row["buyer"] = bid.cover_name || counterparty.active_cover_name
	export_row["market"] = bid.profile.name
	export_row["premium"] = premium
	export.market_counterparty_id = counterparty.id
	export.market_cover_name = bid.cover_name
	export.market_contract_key = bid.reservation_key
	export.market_premium += premium
	bid.fulfilled_units += matched_quantity
	var/contributor_account = export.market_router_account || item.economic_producer_account
	var/datum/contract/faction_agent/agent_contract = SScontracts?.agent_contract_for_market_key(bid.reservation_key)
	var/contact_commission = 0
	if(agent_contract?.contact_account_number == contributor_account)
		contact_commission = agent_contract.pay_contact_market_commission(export_revenue(premium))
	var/datum/cargo_market_transaction/transaction = record_market_transaction(CARGO_MARKET_SELL, counterparty.id, "Sold [item.name] against [bid.profile.name]", export_revenue(market_value), contributor_account, bid.cover_name, bid.reservation_key)
	emit_contract_event(CONTRACT_EVENT_CARGO_MARKET_EXPORT, list(
		"actor_account" = contributor_account,
		"principal_account" = bid.reserved_account,
		"department" = DEPARTMENT_CARGO,
		"origin_department" = item.economic_department,
		"counterparty_id" = counterparty.id,
		"faction_id" = counterparty.faction_id,
		"bid_id" = bid.id,
		"market_contract_key" = bid.reservation_key,
		"market_transaction_id" = transaction?.id,
		"profile_id" = bid.profile.id,
		"item_type" = item.type,
		"item_name" = item.name,
		"fact_id" = "market-export:[REF(item)]",
		"fact_revision" = 1,
		"fact_active" = TRUE,
		"metrics" = list(
			"quantity" = matched_quantity,
			"value" = export_revenue(market_value),
			"premium" = export_revenue(premium),
			"contact_commission" = contact_commission,
		),
		"detail" = "An external buyer accepted [item.name] against [bid.profile.name].",
	), "market-export:[REF(item)]:[bid.id]", item)
	if(bid.fulfilled_units >= bid.target_units && !bid.completed_at)
		bid.completed_at = world.time
		adjust_station_faction_reputation(counterparty.faction_id, 2)
		adjust_department_faction_reputation(DEPARTMENT_CARGO, counterparty.faction_id, 6)
		if(export.market_router_account)
			adjust_personal_faction_reputation(export.market_router_account, counterparty.faction_id, 8)
	return TRUE

/datum/controller/subsystem/supply/proc/crate_is_on_supply_shuttle(obj/structure/closet/crate/crate)
	if(!crate || !shuttle)
		return FALSE
	var/area/crate_area = get_area(crate)
	return crate_area && (crate_area in shuttle.shuttle_area)

/datum/controller/subsystem/supply/proc/route_market_crate(obj/structure/closet/crate/crate, bid_id, mob/living/user, console_unlocked = FALSE)
	if(!crate_is_on_supply_shuttle(crate))
		return FALSE
	if(!bid_id)
		crate.cargo_market_bid_id = null
		crate.cargo_market_router_account = 0
		crate.cargo_market_contract_key = null
		return TRUE
	var/datum/cargo_market_bid/bid = market_bid(bid_id)
	var/datum/cargo_market_counterparty/counterparty = market_counterparties?[bid?.counterparty_id]
	if(!bid || bid.reservation_key || bid.completed_at || world.time >= bid.expires_at || !market_counterparty_access(counterparty, user, console_unlocked) || !market_reserved_access(bid.reserved_account, user, bid.reservation_key))
		return FALSE
	crate.cargo_market_bid_id = bid.id
	crate.cargo_market_router_account = contract_account_for_mob(user)?.account_number || 0
	crate.cargo_market_contract_key = bid.reservation_key
	return TRUE

/datum/controller/subsystem/supply/proc/cargo_market_profile_path(profile_id)
	for(var/profile_path as anything in subtypesof(/datum/cargo_market_profile))
		if(is_abstract(profile_path))
			continue
		var/datum/cargo_market_profile/profile = new profile_path
		if(profile.id == profile_id)
			qdel(profile)
			return profile_path
		qdel(profile)
	return /datum/cargo_market_profile/general_manufactured

/datum/controller/subsystem/supply/proc/create_reserved_market_listing(datum/cargo_market_counterparty/counterparty, reserved_account, reservation_key, expires_at, excluded_group)
	var/list/eligible_packs = list()
	var/list/groups = counterparty.seller_groups()
	for(var/pack_name in supply_pack)
		var/datum/supply_pack/pack = supply_pack[pack_name]
		if((excluded_group && pack.group == excluded_group) || !(pack.group in groups) || (!counterparty.allows_contraband && pack.contraband))
			continue
		eligible_packs += pack
	if(!length(eligible_packs))
		return null
	var/datum/supply_pack/selected_pack = pick(eligible_packs)
	var/datum/cargo_market_listing/listing = new
	listing.id = "MKT-L-[next_market_id++]"
	listing.counterparty_id = counterparty.id
	listing.pack = selected_pack
	listing.unit_price = cargo_market_seller_price(counterparty, selected_pack)
	listing.stock = max(4, CEILING(1300 / max(1, listing.unit_price), 1))
	listing.expires_at = expires_at
	listing.cover_name = counterparty.active_cover_name
	listing.reservation_key = reservation_key
	listing.reserved_account = reserved_account
	market_listings[listing.id] = listing
	return listing

/datum/controller/subsystem/supply/proc/create_reserved_market_bid(datum/cargo_market_counterparty/counterparty, profile_id, reserved_account, reservation_key, expires_at, target_units = 12)
	var/profile_path = cargo_market_profile_path(profile_id)
	var/datum/cargo_market_profile/profile = new profile_path
	var/datum/cargo_market_bid/bid = new
	bid.id = "MKT-B-[next_market_id++]"
	bid.counterparty_id = counterparty.id
	bid.profile = profile
	bid.target_units = max(profile.minimum_units, target_units)
	bid.price_multiplier = cargo_market_buyer_multiplier(counterparty, profile)
	bid.expires_at = expires_at
	bid.cover_name = counterparty.active_cover_name
	bid.reservation_key = reservation_key
	bid.reserved_account = reserved_account
	market_bids[bid.id] = bid
	return bid

/datum/controller/subsystem/supply/proc/reserve_agent_contract_market(datum/contract/faction_agent/contract)
	if(!contract?.offer_key || !contract.agent_faction)
		return FALSE
	var/datum/cargo_market_counterparty/counterparty
	for(var/counterparty_id in market_counterparties)
		var/datum/cargo_market_counterparty/candidate = market_counterparties[counterparty_id]
		if(candidate.faction_id == contract.agent_faction)
			counterparty = candidate
			break
	if(!counterparty)
		return FALSE
	var/expiry = contract.deadline > world.time ? contract.deadline : world.time + 30 MINUTES
	var/needs_purchase_route = FALSE
	var/needs_export_route = FALSE
	for(var/datum/contract_requirement/requirement in contract.requirements)
		needs_purchase_route = needs_purchase_route || (CONTRACT_EVENT_CARGO_MARKET_PURCHASE in requirement.event_types)
		needs_export_route = needs_export_route || (CONTRACT_EVENT_CARGO_MARKET_EXPORT in requirement.event_types)
	if(needs_purchase_route)
		var/datum/cargo_market_listing/first = create_reserved_market_listing(counterparty, contract.owner_account_number, contract.offer_key, expiry)
		if(first)
			contract.market_reservation_ids += first.id
		if(contract.operation_kind == AGENT_OPERATION_SERVICE)
			var/datum/cargo_market_listing/second = create_reserved_market_listing(counterparty, contract.owner_account_number, contract.offer_key, expiry, first?.pack?.group)
			if(second)
				contract.market_reservation_ids += second.id
	if(needs_export_route)
		var/profile_id = contract.offer_context?["profile_id"] || agent_target_profile(contract.agent_faction)
		var/datum/cargo_market_bid/bid = create_reserved_market_bid(counterparty, profile_id, contract.owner_account_number, contract.offer_key, expiry, contract.red_contract ? 18 : 12)
		if(bid)
			contract.market_reservation_ids += bid.id
	return (!needs_purchase_route && !needs_export_route) || length(contract.market_reservation_ids)

/datum/controller/subsystem/supply/proc/release_agent_contract_market(datum/contract/faction_agent/contract)
	if(!contract)
		return FALSE
	for(var/market_id in contract.market_reservation_ids)
		var/datum/cargo_market_listing/listing = market_listings?[market_id]
		if(listing)
			listing.stock = 0
			listing.retired = TRUE
			listing.reservation_key = null
			listing.reserved_account = 0
			listing.expires_at = min(listing.expires_at, next_market_refresh)
			continue
		var/datum/cargo_market_bid/bid = market_bids?[market_id]
		if(bid)
			bid.completed_at = world.time
			bid.reservation_key = null
			bid.reserved_account = 0
			bid.expires_at = min(bid.expires_at, next_market_refresh)
	contract.market_reservation_ids.Cut()
	return TRUE

/datum/controller/subsystem/supply/proc/market_security_auditor(mob/living/user)
	if(issilicon(user))
		return TRUE
	var/obj/item/card/id/id_card = user?.GetIdCard()
	return id_card && ((ACCESS_SECURITY in id_card.access) || (ACCESS_HEADS in id_card.access))

/datum/controller/subsystem/supply/proc/audit_market_transaction(transaction_id, mob/living/user)
	if(!market_security_auditor(user))
		return FALSE
	var/datum/money_account/auditor = contract_account_for_mob(user)
	var/datum/cargo_market_transaction/transaction
	for(var/datum/cargo_market_transaction/candidate in market_transactions)
		if(candidate.id == transaction_id)
			transaction = candidate
			break
	var/auditor_key = "[auditor?.account_number || user.ckey]"
	if(!transaction?.covert || transaction.audited_accounts[auditor_key])
		return FALSE
	transaction.audited_accounts[auditor_key] = TRUE
	var/datum/cargo_market_counterparty/counterparty = market_counterparties[transaction.counterparty_id]
	var/datum/faction_agent_record/record = GLOB.station_faction_relations.get_agent_record(transaction.principal_account)
	var/datum/contract/faction_agent/agent_contract = SScontracts?.agent_contract_for_market_key(transaction.reservation_key)
	var/score = transaction.trace_strength + (record?.exposure || 0)
	if(score >= FACTION_AGENT_INVESTIGATION_THRESHOLD)
		transaction.detected = TRUE
		transaction.detected_account = record?.account_number || transaction.principal_account
		transaction.detected_contact_account = transaction.account_number != transaction.detected_account ? transaction.account_number : 0
		agent_contract?.advance_discovery(AGENT_DISCOVERY_IDENTIFIED, "A Supply-console forensic audit correlated the settlement with its principal and contact.", 15)
	else if(score >= round(FACTION_AGENT_INVESTIGATION_THRESHOLD * 0.5))
		agent_contract?.advance_discovery(AGENT_DISCOVERY_TRACED, "A Security audit recovered a strong trace but could not yet identify its participants.")
	else
		agent_contract?.advance_discovery(AGENT_DISCOVERY_SUSPECTED, "A Security audit confirmed suspicious settlement metadata without identifying its participants.")
	emit_contract_event(CONTRACT_EVENT_COVERT_MARKET_AUDIT, list(
		"actor_account" = auditor?.account_number,
		"department" = DEPARTMENT_SECURITY,
		"transaction_id" = transaction.id,
		"detected" = transaction.detected,
		"suspect_account" = transaction.detected_account,
		"contact_account" = transaction.detected_contact_account,
		"channel" = "settlement_ledger",
		"faction_id" = transaction.detected ? counterparty?.faction_id : null,
		"fact_id" = "market-audit:[transaction.id]",
		"fact_revision" = length(transaction.audited_accounts),
		"fact_active" = TRUE,
		"metrics" = list("score" = score, "value" = transaction.value),
		"detail" = transaction.detected ? "The audit correlated an encrypted trade with an account identity." : "The audit preserved a trace but could not identify an account.",
	), "market-audit:[transaction.id]:[auditor_key]")
	return TRUE

/// Re-publish already established forensic facts when an investigation is
/// accepted. This makes offer timing irrelevant without making the auditor
/// repeat an IC action or adding a polling requirement.
/datum/controller/subsystem/supply/proc/replay_market_audit_evidence(datum/contract/covert_market_investigation/contract)
	if(!contract?.suspect_account || contract.state != CONTRACT_ACTIVE)
		return FALSE
	var/replayed = 0
	for(var/datum/cargo_market_transaction/transaction in market_transactions)
		if(!transaction.detected || transaction.detected_account != contract.suspect_account)
			continue
		var/datum/cargo_market_counterparty/counterparty = market_counterparties[transaction.counterparty_id]
		emit_contract_event(CONTRACT_EVENT_COVERT_MARKET_AUDIT, list(
			"actor_account" = contract.accepted_by_account,
			"department" = DEPARTMENT_SECURITY,
			"contract_id" = contract.id,
			"transaction_id" = transaction.id,
			"detected" = TRUE,
			"suspect_account" = transaction.detected_account,
			"faction_id" = counterparty?.faction_id,
			"fact_id" = "market-audit:[transaction.id]",
			"fact_revision" = length(transaction.audited_accounts),
			"fact_active" = TRUE,
			"metrics" = list("score" = transaction.trace_strength, "value" = transaction.value),
			"detail" = "A preserved market trace correlates with the investigation target.",
		), "market-audit-replay:[transaction.id]:[contract.id]")
		replayed++
	var/datum/faction_agent_record/record = GLOB.station_faction_relations.get_agent_record(contract.suspect_account)
	for(var/fact_id in record?.investigation_facts)
		var/list/fact = record.investigation_facts[fact_id]
		emit_contract_event(CONTRACT_EVENT_COVERT_MARKET_AUDIT, list(
			"actor_account" = contract.accepted_by_account,
			"department" = DEPARTMENT_SECURITY,
			"contract_id" = contract.id,
			"transaction_id" = fact_id,
			"channel" = "physical_document",
			"detected" = TRUE,
			"suspect_account" = contract.suspect_account,
			"contact_account" = fact["contact_account"],
			"fact_id" = "agent-evidence:[fact_id]",
			"fact_revision" = 1,
			"fact_active" = TRUE,
			"detail" = fact["detail"],
		), "agent-evidence-replay:[fact_id]:[contract.id]")
		replayed++
	return replayed > 0

/datum/controller/subsystem/supply/proc/cargo_market_ui_data(mob/living/user, console_unlocked = FALSE, station_trade_authorized = FALSE)
	var/list/parties = list()
	var/list/listings = list()
	var/list/bids = list()
	var/list/transactions = list()
	var/list/outbound_crates = list()
	var/datum/money_account/viewer_account = contract_account_for_mob(user)
	var/is_auditor = market_security_auditor(user)
	for(var/counterparty_id in market_counterparties)
		var/datum/cargo_market_counterparty/counterparty = market_counterparties[counterparty_id]
		if(!market_counterparty_visible(counterparty, user, console_unlocked))
			continue
		var/datum/reputation_faction/faction = GLOB.reputation_factions[counterparty.faction_id]
		parties.Add(list(list(
			"id" = counterparty.id,
			"name" = market_display_name(counterparty, user, counterparty.active_cover_name),
			"description" = counterparty.covert && !market_true_identity_visible(counterparty, user) ? "An encrypted broker offering privately authenticated commercial routes." : counterparty.description,
			"faction" = counterparty.covert && !market_true_identity_visible(counterparty, user) ? "Private network" : (faction?.short_name || counterparty.faction_id),
			"color" = faction?.color || "#888888",
			"standing" = cargo_market_standing(counterparty),
			"standing_tier" = reputation_rank(cargo_market_standing(counterparty)),
			"covert" = counterparty.covert,
		)))
	for(var/listing_id in market_listings)
		var/datum/cargo_market_listing/listing = market_listings[listing_id]
		var/datum/cargo_market_counterparty/counterparty = market_counterparties[listing.counterparty_id]
		if(listing.retired || listing.stock <= 0 || world.time >= listing.expires_at || !market_counterparty_visible(counterparty, user, console_unlocked) || !market_reserved_access(listing.reserved_account, user, listing.reservation_key))
			continue
		var/can_access_listing = market_counterparty_access(counterparty, user, console_unlocked)
		var/datum/contract/faction_agent/funding_contract = market_contract_funding(listing.reservation_key, user, listing.unit_price)
		listings.Add(list(list(
			"id" = listing.id,
			"counterparty_id" = counterparty.id,
			"counterparty" = market_display_name(counterparty, user, listing.cover_name),
			"name" = listing.pack.name,
			"description" = listing.pack.desc,
			"group" = listing.pack.group,
			"price" = listing.unit_price,
			"stock" = listing.stock,
			"contraband" = !!listing.pack.contraband,
			"reserved" = !!listing.reservation_key,
			"can_department" = can_access_listing && station_trade_authorized,
			"can_personal" = can_access_listing && !!viewer_account,
			"can_contract" = can_access_listing && !!funding_contract,
			"contract_allowance" = funding_contract ? funding_contract.market_allowance - funding_contract.market_spend : 0,
			"expires" = DisplayTimeText(max(0, listing.expires_at - world.time), 1),
		)))
	for(var/bid_id in market_bids)
		var/datum/cargo_market_bid/bid = market_bids[bid_id]
		var/datum/cargo_market_counterparty/counterparty = market_counterparties[bid.counterparty_id]
		if(bid.completed_at || bid.remaining_units() <= 0 || world.time >= bid.expires_at || !market_counterparty_visible(counterparty, user, console_unlocked) || !market_reserved_access(bid.reserved_account, user, bid.reservation_key))
			continue
		bids.Add(list(list(
			"id" = bid.id,
			"counterparty_id" = counterparty.id,
			"counterparty" = market_display_name(counterparty, user, bid.cover_name),
			"name" = bid.profile.name,
			"description" = bid.profile.description,
			"fulfilled" = bid.fulfilled_units,
			"target" = bid.target_units,
			"remaining" = bid.remaining_units(),
			"multiplier" = bid.price_multiplier,
			"reserved" = !!bid.reservation_key,
			"can_route" = !bid.reservation_key && (station_trade_authorized || has_faction_market_access(user, counterparty.faction_id)),
			"expires" = DisplayTimeText(max(0, bid.expires_at - world.time), 1),
		)))
	for(var/datum/cargo_market_transaction/transaction in market_transactions)
		var/datum/cargo_market_counterparty/counterparty = market_counterparties[transaction.counterparty_id]
		var/transaction_visible = market_counterparty_visible(counterparty, user, console_unlocked)
		if(!transaction_visible && !(is_auditor && transaction.covert))
			continue
		var/reveal_identity = transaction_visible && market_true_identity_visible(counterparty, user)
		var/datum/money_account/detected_account = transaction.detected_account ? get_account(transaction.detected_account) : null
		transactions.Insert(1, list(list(
			"id" = transaction.id,
			"type" = transaction.transaction_type,
			"counterparty" = reveal_identity ? counterparty.name : (transaction.cover_name || "Encrypted clearing route"),
			"description" = transaction.covert && !reveal_identity ? "Encrypted external market settlement" : transaction.description,
			"value" = transaction.value,
			"time" = worldtime2stationtime(transaction.occurred_at),
			"covert" = transaction.covert,
			"auditable" = FALSE,
			"detected" = transaction.detected,
			"suspect" = transaction.detected && is_auditor ? (detected_account?.owner_name || "Account [transaction.detected_account]") : null,
			"trace" = 0,
		)))
		if(length(transactions) >= 20)
			break
	if(shuttle)
		for(var/area/subarea in shuttle.shuttle_area)
			for(var/obj/structure/closet/crate/crate in subarea)
				if(crate.anchored)
					continue
				var/datum/cargo_market_bid/assigned_bid = market_bid(crate.cargo_market_bid_id)
				var/datum/cargo_market_counterparty/assigned_counterparty = market_counterparties?[assigned_bid?.counterparty_id]
				var/assigned_visible = assigned_bid && assigned_counterparty && market_counterparty_visible(assigned_counterparty, user, console_unlocked)
				var/assigned_active = assigned_visible && market_reserved_access(assigned_bid.reserved_account, user, assigned_bid.reservation_key) && !assigned_bid.completed_at && world.time < assigned_bid.expires_at
				outbound_crates.Add(list(list(
					"ref" = REF(crate),
					"name" = crate.name,
					"contents" = length(crate.contents) + crate.latent_count(), // latent-ok
					"bid_id" = assigned_active ? assigned_bid.id : null,
					"route" = assigned_active ? "[market_display_name(assigned_counterparty, user, assigned_bid.cover_name)] — [assigned_bid.profile.name]" : (assigned_bid && !assigned_visible ? "Encrypted private route" : "Spot market"),
				)))
	return list(
		"generation" = market_generation,
		"refresh_in" = DisplayTimeText(max(0, next_market_refresh - world.time), 1),
		"counterparties" = parties,
		"listings" = listings,
		"bids" = bids,
		"transactions" = transactions,
		"outbound_crates" = outbound_crates,
		"is_auditor" = is_auditor,
	)
