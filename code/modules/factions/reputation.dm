GLOBAL_LIST_INIT(reputation_factions, init_reputation_factions())
GLOBAL_DATUM_INIT(station_faction_relations, /datum/station_faction_relations, new())

/proc/reputation_affiliation_choices() as /list
	return list(AFFILIATION_HOSTILE, AFFILIATION_OPPOSED, AFFILIATION_NEUTRAL, AFFILIATION_FRIENDLY, AFFILIATION_MEMBER)

/proc/reputation_for_affiliation(affiliation)
	switch(affiliation)
		if(AFFILIATION_HOSTILE)
			return REPUTATION_HOSTILE
		if(AFFILIATION_OPPOSED)
			return REPUTATION_UNFRIENDLY
		if(AFFILIATION_FRIENDLY)
			return REPUTATION_FRIENDLY
		if(AFFILIATION_MEMBER)
			return REPUTATION_ALLIED
	return REPUTATION_NEUTRAL

/proc/reputation_affiliation_total(list/affiliations)
	if(!islist(affiliations))
		return 0
	var/total = 0
	for(var/faction_id in GLOB.reputation_factions)
		total += reputation_for_affiliation(affiliations[faction_id] || AFFILIATION_NEUTRAL)
	return total

/proc/reputation_rank(value)
	if(value <= REPUTATION_HATED)
		return "Hated"
	if(value <= REPUTATION_HOSTILE)
		return "Hostile"
	if(value <= REPUTATION_UNFRIENDLY)
		return "Unfriendly"
	if(value < REPUTATION_FRIENDLY)
		return "Neutral"
	if(value < REPUTATION_ALLIED)
		return "Friendly"
	if(value < REPUTATION_REVERED)
		return "Allied"
	return "Revered"

/proc/init_reputation_factions()
	var/list/factions = list()
	for(var/datum/reputation_faction/faction_type as anything in subtypesof(/datum/reputation_faction))
		if(is_abstract(faction_type))
			continue
		var/datum/reputation_faction/faction = new faction_type
		factions[faction.id] = faction
	return factions

/datum/reputation_faction
	abstract_type = /datum/reputation_faction
	var/id
	var/name
	var/short_name
	var/acronym
	var/description
	var/color = "#999999"
	var/default_station_reputation = REPUTATION_NEUTRAL
	var/grid_x = 1
	var/grid_y = 1

/datum/reputation_faction/nanotrasen
	id = REPUTATION_FACTION_NANOTRASEN
	name = "NanoTrasen Incorporated"
	short_name = "NanoTrasen"
	acronym = "NT"
	color = "#315b8a"
	default_station_reputation = REPUTATION_ALLIED
	grid_x = 0
	grid_y = 0
	description = "The research giant operating Southern Cross. NanoTrasen built its position on phoron research, early adoption of experimental technology, and unusually comprehensive employee medical benefits."

/datum/reputation_faction/solgov
	id = REPUTATION_FACTION_SOLGOV
	name = "Sol Central Government"
	short_name = "SolGov"
	acronym = "SCG"
	color = "#496b9e"
	default_station_reputation = REPUTATION_FRIENDLY
	grid_x = 0
	grid_y = 1
	description = "The principal human interstellar government, represented by its civil administration, diplomatic service, Fleet, and Army. It regulates much of the space in which NanoTrasen operates."

/datum/reputation_faction/chimera
	id = REPUTATION_FACTION_CHIMERA
	name = "Chimera Genetics Corporation"
	short_name = "Chimera Genetics"
	acronym = "CGC"
	color = "#7b3f95"
	grid_x = 1
	grid_y = 2
	description = "A Titan-based biotechnology corporation specializing in designer flora, fauna, bodies, and extensive genetic modification. Its best-known products include the contract-loyal Drake bioform line."

/datum/reputation_faction/eclipse
	id = REPUTATION_FACTION_ECLIPSE
	name = "Eclipse Corporation"
	short_name = "Eclipse"
	acronym = "EC"
	color = "#59466f"
	grid_x = 2
	grid_y = 2
	description = "A secretive high-technology concern associated with exotic weapons, mecha, and precursor-derived research. This corporate identity is distinct from the combat-AI faction key used by legacy Eclipse hostiles."

/datum/reputation_faction/syndicate
	id = REPUTATION_FACTION_SYNDICATE
	name = "Syndicate"
	short_name = "Syndicate"
	acronym = "SYN"
	color = "#9f2828"
	default_station_reputation = REPUTATION_HATED
	grid_x = 2
	grid_y = 0
	description = "A loose clandestine coalition of anti-NanoTrasen interests, criminal operators, mercenaries, and corporate rivals. Its cells vary widely, but Southern Cross treats the organization as an existential security threat."

/datum/reputation_faction/traders_guild
	id = REPUTATION_FACTION_TRADERS_GUILD
	name = "Interstellar Traders' Guild"
	short_name = "Traders' Guild"
	acronym = "ITG"
	color = "#b78932"
	grid_x = 1
	grid_y = 0
	description = "A galaxy-spanning association of independent merchants, pilots, and freeport operators. It inherits the setting role of the older Free Trade Union: mutual protection, open commerce, and Tradeband as a merchant lingua franca."

/datum/reputation_faction/talon
	id = REPUTATION_FACTION_TALON
	name = "TALON"
	short_name = "TALON"
	acronym = "TALON"
	color = "#b36a32"
	grid_x = 1
	grid_y = 1
	description = "The independent expeditionary shipboard organization associated with the ITV Talon and its crews: pilots, engineers, guards, medics, and frontier specialists operating beyond ordinary station departments."

/datum/reputation_faction/workers_union
	id = REPUTATION_FACTION_WORKERS_UNION
	name = "Workers' Union"
	short_name = "Workers' Union"
	acronym = "WU"
	color = "#b04444"
	grid_x = 2
	grid_y = 1
	description = "An interstellar labor movement advocating collective bargaining, workplace safety, fair pay, and worker ownership. Its local chapters range from recognized negotiating bodies to organizations viewed suspiciously by corporate management."

/datum/reputation_faction/veymed
	id = REPUTATION_FACTION_VEYMED
	name = "Vey-Medical"
	short_name = "Vey-Med"
	acronym = "VM"
	color = "#61a9b8"
	grid_x = 0
	grid_y = 2
	description = "A largely Skrell-owned medical technology corporation with market-leading surgical equipment, trauma-response systems, resurrective cloning history, and extremely lifelike premium prosthetics."

/datum/faction_reputation_ledger
	var/list/reputations
	/// Positive in-round adjustments, tracked separately from character-setup
	/// affiliation so agency must be earned through play this round.
	var/list/positive_reputation_earned
	/// Starting affiliations initialize a personal ledger exactly once. New
	/// bodies linked to the same round-stable account must not reset earned rep.
	var/affiliations_initialized = FALSE

/datum/faction_reputation_ledger/New(list/initial_values)
	. = ..()
	reputations = list()
	positive_reputation_earned = list()
	for(var/faction_id in GLOB.reputation_factions)
		reputations[faction_id] = REPUTATION_NEUTRAL
		positive_reputation_earned[faction_id] = 0
	if(initial_values)
		for(var/faction_id in initial_values)
			if(faction_id in GLOB.reputation_factions)
				reputations[faction_id] = CLAMP(round(initial_values[faction_id]), REPUTATION_MINIMUM, REPUTATION_MAXIMUM)

/datum/faction_reputation_ledger/Destroy()
	reputations = null
	positive_reputation_earned = null
	return ..()

/datum/faction_reputation_ledger/proc/get_reputation(faction_id)
	if(!(faction_id in GLOB.reputation_factions))
		return null
	return reputations[faction_id] || REPUTATION_NEUTRAL

/datum/faction_reputation_ledger/proc/set_reputation(faction_id, value)
	if(!(faction_id in GLOB.reputation_factions) || !isnum(value))
		return FALSE
	reputations[faction_id] = CLAMP(round(value), REPUTATION_MINIMUM, REPUTATION_MAXIMUM)
	return TRUE

/datum/faction_reputation_ledger/proc/adjust_reputation(faction_id, delta)
	if(!isnum(delta))
		return FALSE
	var/current = get_reputation(faction_id)
	if(isnull(current))
		return FALSE
	if(!set_reputation(faction_id, current + delta))
		return FALSE
	var/actual_delta = get_reputation(faction_id) - current
	if(actual_delta > 0)
		positive_reputation_earned[faction_id] = (positive_reputation_earned[faction_id] || 0) + actual_delta
	return TRUE

/datum/faction_reputation_ledger/proc/positive_earned(faction_id)
	return max(0, positive_reputation_earned?[faction_id] || 0)

/datum/faction_reputation_ledger/proc/get_rank(faction_id)
	var/value = get_reputation(faction_id)
	return isnull(value) ? null : reputation_rank(value)

/datum/station_faction_relations
	parent_type = /datum/faction_reputation_ledger
	var/list/department_ledgers
	/// Personal ledgers are keyed by account number so reputation follows the
	/// character's mind through cloning, resleeving, and temporary disconnects.
	var/list/personal_ledgers
	/// One exclusive, opt-in faction principal per account for this round.
	var/list/agent_records

/datum/station_faction_relations/New()
	var/list/defaults = list(
		REPUTATION_FACTION_NANOTRASEN = REPUTATION_ALLIED,
		REPUTATION_FACTION_SOLGOV = REPUTATION_FRIENDLY,
		REPUTATION_FACTION_SYNDICATE = REPUTATION_HATED,
	)
	. = ..(defaults)
	department_ledgers = list()
	personal_ledgers = list()
	agent_records = list()
	for(var/department in get_reputation_departments())
		department_ledgers[department] = new /datum/faction_reputation_ledger(reputations)

/datum/station_faction_relations/Destroy()
	for(var/department in department_ledgers)
		qdel(department_ledgers[department])
	department_ledgers = null
	for(var/account_number in personal_ledgers)
		qdel(personal_ledgers[account_number])
	personal_ledgers = null
	QDEL_LIST(agent_records)
	agent_records = null
	return ..()

/datum/station_faction_relations/proc/get_reputation_departments()
	return list(
		DEPARTMENT_COMMAND,
		DEPARTMENT_SECURITY,
		DEPARTMENT_ENGINEERING,
		DEPARTMENT_MEDICAL,
		DEPARTMENT_RESEARCH,
		DEPARTMENT_CARGO,
		DEPARTMENT_CIVILIAN,
		DEPARTMENT_PLANET,
		DEPARTMENT_SYNTHETIC,
		DEPARTMENT_TALON,
	)

/datum/station_faction_relations/proc/get_department_ledger(department, create = TRUE)
	var/datum/faction_reputation_ledger/ledger = department_ledgers[department]
	if(!ledger && create && istext(department) && length(department))
		ledger = new(reputations)
		department_ledgers[department] = ledger
	return ledger

/datum/station_faction_relations/proc/get_personal_ledger(account_number, create = TRUE, list/initial_values) as /datum/faction_reputation_ledger
	if(!account_number)
		return null
	var/key = "[account_number]"
	var/datum/faction_reputation_ledger/ledger = personal_ledgers[key]
	if(!ledger && create)
		ledger = new(initial_values)
		personal_ledgers[key] = ledger
	return ledger

/proc/get_station_faction_reputation(faction_id)
	return GLOB.station_faction_relations.get_reputation(faction_id)

/proc/adjust_station_faction_reputation(faction_id, delta)
	return GLOB.station_faction_relations.adjust_reputation(faction_id, delta)

/proc/get_department_faction_reputation(department, faction_id)
	var/datum/faction_reputation_ledger/ledger = GLOB.station_faction_relations.get_department_ledger(department, FALSE)
	return ledger?.get_reputation(faction_id)

/proc/adjust_department_faction_reputation(department, faction_id, delta)
	var/datum/faction_reputation_ledger/ledger = GLOB.station_faction_relations.get_department_ledger(department)
	return ledger?.adjust_reputation(faction_id, delta)

/proc/get_personal_faction_reputation(account_number, faction_id)
	var/datum/faction_reputation_ledger/ledger = GLOB.station_faction_relations.get_personal_ledger(account_number, FALSE)
	return ledger?.get_reputation(faction_id)

/proc/adjust_personal_faction_reputation(account_number, faction_id, delta)
	var/datum/faction_reputation_ledger/ledger = GLOB.station_faction_relations.get_personal_ledger(account_number)
	return ledger?.adjust_reputation(faction_id, delta)

/datum/faction_agent_record
	var/account_number = 0
	var/faction_id
	var/datum/mind/agent_mind
	var/tier = FACTION_AGENT_TIER_CANDIDATE
	var/candidate_started_at = 0
	var/appointed_at = 0
	var/contracts_completed = 0
	var/contracts_failed = 0
	var/next_offer_sequence = 1
	var/exposure = 0
	var/operative_contract_id
	var/counter_offer_queued = FALSE
	/// Preserved physical/ledger facts let an investigation accepted after the
	/// discovery use evidence already collected in the world.
	var/list/investigation_facts

/datum/faction_agent_record/New()
	. = ..()
	investigation_facts = list()

/datum/faction_agent_record/Destroy()
	agent_mind = null
	investigation_facts = null
	return ..()

/proc/faction_agent_tier_name(tier)
	switch(tier)
		if(FACTION_AGENT_TIER_CANDIDATE)
			return "Vetting contact"
		if(FACTION_AGENT_TIER_ACCREDITED)
			return "Accredited agent"
		if(FACTION_AGENT_TIER_TRUSTED)
			return "Trusted agent"
		if(FACTION_AGENT_TIER_OPERATIVE)
			return "Contract operative"
	return "No relationship"

/proc/notify_faction_agent_account(account_number, message)
	if(!account_number || !message)
		return
	for(var/obj/item/pda/device in REGISTRY_MEMBERS(REGISTRY_PDAS))
		if(device.id?.associated_account_number != account_number)
			continue
		var/datum/data/pda/app/contracts/app = device.find_program(/datum/data/pda/app/contracts)
		app?.notify(message)

/datum/station_faction_relations/proc/get_agent_record(account_number) as /datum/faction_agent_record
	return agent_records?["[account_number]"]

/datum/station_faction_relations/proc/account_is_agent(account_number, faction_id)
	var/datum/faction_agent_record/record = get_agent_record(account_number)
	return record && record.tier >= FACTION_AGENT_TIER_ACCREDITED && (!faction_id || record.faction_id == faction_id)

/datum/station_faction_relations/proc/account_has_principal_access(account_number, faction_id)
	var/datum/faction_agent_record/record = get_agent_record(account_number)
	return record && record.tier >= FACTION_AGENT_TIER_CANDIDATE && (!faction_id || record.faction_id == faction_id)

/datum/station_faction_relations/proc/account_is_trusted_agent(account_number, faction_id)
	var/datum/faction_agent_record/record = get_agent_record(account_number)
	return record && record.tier >= FACTION_AGENT_TIER_TRUSTED && (!faction_id || record.faction_id == faction_id)

/datum/station_faction_relations/proc/account_has_market_access(account_number, faction_id)
	if(account_has_principal_access(account_number, faction_id))
		return TRUE
	return !!SScontracts?.agent_contact_contract(account_number, faction_id)

/datum/station_faction_relations/proc/account_agent_eligibility(account_number, faction_id)
	if(!account_number || !(faction_id in GLOB.reputation_factions) || get_agent_record(account_number))
		return FALSE
	var/datum/faction_reputation_ledger/ledger = get_personal_ledger(account_number, FALSE)
	var/required_reputation = faction_id == REPUTATION_FACTION_SYNDICATE ? CARGO_MARKET_SYNDICATE_REPUTATION : CARGO_MARKET_AGENT_REPUTATION
	var/required_earned = faction_id == REPUTATION_FACTION_SYNDICATE ? CARGO_MARKET_SYNDICATE_EARNED_REPUTATION : CARGO_MARKET_AGENT_EARNED_REPUTATION
	if(!ledger || ledger.get_reputation(faction_id) < required_reputation)
		return FALSE
	return ledger.positive_earned(faction_id) >= required_earned

/datum/station_faction_relations/proc/begin_agent_vetting(mob/living/user, faction_id)
	var/datum/money_account/account = contract_account_for_mob(user)
	if(!account || !account_agent_eligibility(account.account_number, faction_id))
		return FALSE
	var/datum/faction_agent_record/record = new
	record.account_number = account.account_number
	record.faction_id = faction_id
	record.agent_mind = user.mind
	record.candidate_started_at = world.time
	agent_records["[account.account_number]"] = record
	var/datum/reputation_faction/faction = GLOB.reputation_factions[faction_id]
	log_game("[key_name(user)] opened exclusive faction vetting with [faction?.name || faction_id].")
	SScontracts?.queue_agent_vetting(account.account_number, faction_id)
	return TRUE

/// Compatibility entry point for callers written before the vetting ladder.
/// It deliberately begins vetting rather than bypassing accreditation.
/datum/station_faction_relations/proc/appoint_agent(mob/living/user, faction_id)
	return begin_agent_vetting(user, faction_id)

/datum/station_faction_relations/proc/accredit_agent(account_number)
	var/datum/faction_agent_record/record = get_agent_record(account_number)
	if(!record || record.tier != FACTION_AGENT_TIER_CANDIDATE)
		return FALSE
	record.tier = FACTION_AGENT_TIER_ACCREDITED
	record.appointed_at = world.time
	SScontracts?.queue_agent_offers(record.account_number, record.faction_id)
	return TRUE

/datum/station_faction_relations/proc/refresh_agent_tier(datum/faction_agent_record/record)
	if(!record || record.tier != FACTION_AGENT_TIER_ACCREDITED)
		return FALSE
	if(record.contracts_completed < FACTION_AGENT_TRUSTED_COMPLETIONS || get_personal_faction_reputation(record.account_number, record.faction_id) < FACTION_AGENT_TRUSTED_REPUTATION)
		return FALSE
	record.tier = FACTION_AGENT_TIER_TRUSTED
	return TRUE

/datum/station_faction_relations/proc/add_agent_exposure(account_number, faction_id, amount, reason, transaction_id)
	var/datum/faction_agent_record/record = get_agent_record(account_number)
	if(!record || record.faction_id != faction_id)
		var/datum/contract/faction_agent/contact_contract = SScontracts?.agent_contact_contract(account_number, faction_id)
		record = contact_contract && get_agent_record(contact_contract.owner_account_number)
	if(!record || !isnum(amount) || amount <= 0)
		return FALSE
	record.exposure = CLAMP(record.exposure + round(amount), 0, FACTION_AGENT_MAX_EXPOSURE)
	emit_contract_event(CONTRACT_EVENT_COVERT_MARKET_ACTIVITY, list(
		"actor_account" = account_number,
		"principal_account" = record.account_number,
		"faction_id" = faction_id,
		"transaction_id" = transaction_id,
		"fact_id" = "covert-activity:[transaction_id]",
		"fact_revision" = record.exposure,
		"fact_active" = TRUE,
		"metrics" = list("exposure" = record.exposure, "increase" = amount),
		"detail" = reason,
	), "covert-activity:[transaction_id]")
	return TRUE

/datum/station_faction_relations/proc/activate_contract_operative(account_number, contract_id, mob/living/current_owner)
	var/datum/faction_agent_record/record = get_agent_record(account_number)
	if(!record || record.tier < FACTION_AGENT_TIER_TRUSTED || record.operative_contract_id)
		return FALSE
	if(current_owner?.mind)
		record.agent_mind = current_owner.mind
	var/datum/mind/owner_mind = record.agent_mind
	var/datum/antagonist/operative_role = SSantag_job?.get_antag_data(CONTRACT_OPERATIVE_ANTAG_ID)
	if(!owner_mind?.current || owner_mind.special_role || !operative_role || !operative_role.add_antagonist(owner_mind, TRUE, TRUE, FALSE, FALSE, TRUE))
		return FALSE
	record.tier = FACTION_AGENT_TIER_OPERATIVE
	record.operative_contract_id = contract_id
	return TRUE

/datum/station_faction_relations/proc/deactivate_contract_operative(account_number, contract_id)
	var/datum/faction_agent_record/record = get_agent_record(account_number)
	if(!record || record.operative_contract_id != contract_id)
		return FALSE
	var/datum/antagonist/operative_role = SSantag_job?.get_antag_data(CONTRACT_OPERATIVE_ANTAG_ID)
	if(record.agent_mind && operative_role)
		operative_role.remove_antagonist(record.agent_mind, TRUE)
	record.operative_contract_id = null
	record.tier = FACTION_AGENT_TIER_TRUSTED
	return TRUE

/proc/is_faction_agent(mob/living/user, faction_id)
	var/datum/money_account/account = contract_account_for_mob(user)
	return account && GLOB.station_faction_relations.account_is_agent(account.account_number, faction_id)

/proc/has_faction_market_access(mob/living/user, faction_id)
	var/datum/money_account/account = contract_account_for_mob(user)
	return account && GLOB.station_faction_relations.account_has_market_access(account.account_number, faction_id)

/proc/faction_agent_ui_rows(datum/money_account/account) as /list
	var/list/rows = list()
	if(!account)
		return rows
	var/datum/faction_agent_record/active_record = GLOB.station_faction_relations.get_agent_record(account.account_number)
	var/datum/faction_reputation_ledger/ledger = GLOB.station_faction_relations.get_personal_ledger(account.account_number, FALSE)
	for(var/faction_id in GLOB.reputation_factions)
		var/datum/reputation_faction/faction = GLOB.reputation_factions[faction_id]
		var/standing = ledger?.get_reputation(faction_id) || REPUTATION_NEUTRAL
		var/earned = ledger?.positive_earned(faction_id) || 0
		var/required_standing = faction_id == REPUTATION_FACTION_SYNDICATE ? CARGO_MARKET_SYNDICATE_REPUTATION : CARGO_MARKET_AGENT_REPUTATION
		var/required_earned = faction_id == REPUTATION_FACTION_SYNDICATE ? CARGO_MARKET_SYNDICATE_EARNED_REPUTATION : CARGO_MARKET_AGENT_EARNED_REPUTATION
		var/is_active = active_record?.faction_id == faction.id
		rows.Add(list(list(
			"id" = faction.id,
			"name" = faction.name,
			"short_name" = faction.short_name,
			"description" = faction.description,
			"color" = faction.color,
			"standing" = standing,
			"standing_tier" = reputation_rank(standing),
			"earned" = earned,
			"required_standing" = required_standing,
			"required_earned" = required_earned,
			"eligible" = GLOB.station_faction_relations.account_agent_eligibility(account.account_number, faction.id),
			"active" = is_active,
			"locked" = !!active_record && active_record.faction_id != faction.id,
			"tier" = is_active ? active_record.tier : 0,
			"tier_name" = is_active ? faction_agent_tier_name(active_record.tier) : "No relationship",
			"exposure" = is_active ? active_record.exposure : 0,
			"contracts_completed" = is_active ? active_record.contracts_completed : 0,
			"contracts_failed" = is_active ? active_record.contracts_failed : 0,
		)))
	return rows

/mob/living
	var/datum/faction_reputation_ledger/faction_reputation
	var/list/faction_affiliations

/mob/living/proc/ensure_faction_reputation() as /datum/faction_reputation_ledger
	var/account_number = mind?.initial_account?.account_number
	if(account_number)
		var/datum/faction_reputation_ledger/stable_ledger = GLOB.station_faction_relations.get_personal_ledger(account_number, FALSE)
		if(!stable_ledger)
			stable_ledger = GLOB.station_faction_relations.get_personal_ledger(account_number, TRUE, faction_reputation?.reputations)
			stable_ledger.affiliations_initialized = faction_reputation?.affiliations_initialized || FALSE
			if(faction_reputation?.positive_reputation_earned)
				stable_ledger.positive_reputation_earned = faction_reputation.positive_reputation_earned.Copy()
		faction_reputation = stable_ledger
	if(!faction_reputation)
		faction_reputation = new()
	return faction_reputation

/mob/living/proc/get_faction_reputation(faction_id)
	return ensure_faction_reputation().get_reputation(faction_id)

/mob/living/proc/adjust_faction_reputation(faction_id, delta)
	return ensure_faction_reputation().adjust_reputation(faction_id, delta)

/mob/living/proc/set_faction_affiliations(list/affiliations)
	faction_affiliations = list()
	var/datum/faction_reputation_ledger/ledger = ensure_faction_reputation()
	for(var/faction_id in GLOB.reputation_factions)
		var/affiliation = affiliations?[faction_id]
		if(!(affiliation in reputation_affiliation_choices()))
			affiliation = AFFILIATION_NEUTRAL
		faction_affiliations[faction_id] = affiliation
		if(!ledger.affiliations_initialized)
			ledger.set_reputation(faction_id, reputation_for_affiliation(affiliation))
	ledger.affiliations_initialized = TRUE

/mob/living/proc/get_faction_affiliation_summary()
	var/list/summary = list()
	for(var/faction_id in faction_affiliations)
		var/affiliation = faction_affiliations[faction_id]
		if(affiliation == AFFILIATION_NEUTRAL)
			continue
		var/datum/reputation_faction/faction = GLOB.reputation_factions[faction_id]
		if(faction)
			summary += "[faction.short_name] ([affiliation])"
	return length(summary) ? english_list(summary) : "Unaffiliated"

/mob/living/carbon/human/set_faction_affiliations(list/affiliations)
	// Affiliations describe relationships; NanoTrasen employment remains independent.
	return ..()
