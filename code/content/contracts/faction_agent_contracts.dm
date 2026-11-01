/datum/contract/faction_agent
	var/agent_faction
	var/required_agent_tier = FACTION_AGENT_TIER_ACCREDITED
	var/red_contract = FALSE
	var/list/market_reservation_ids
	var/market_allowance = 0
	var/market_spend = 0
	/// A shipment contact exists only for this commission. Their signed ordinary
	/// paper agreement is both their market credential and discoverable evidence.
	var/contact_account_number = 0
	var/contact_name
	var/contact_mode
	var/contact_share_percent = 0
	var/contact_sales_commission = 0
	var/contact_exposure = 0
	var/contact_evidence_id
	var/contact_cooperated = FALSE
	var/requires_contact = TRUE
	var/minimum_contact_risk = 1
	var/required_endorsements = 0
	var/fieldwork_documents_issued = FALSE
	var/operation_kind
	var/approach
	var/list/stakeholder_departments
	var/list/contact_departments
	var/outcome_grade = CONTRACT_OUTCOME_UNRATED
	var/outcome_score = 0
	var/outcome_finalized = FALSE
	var/discovery_stage = AGENT_DISCOVERY_CLEAN
	var/discovery_detail
	var/failure_reputation_factor = CONTRACT_DEFAULT_FAILURE_REPUTATION_FACTOR
	var/operation_reward_multiplier = 1

/datum/contract/faction_agent/New()
	. = ..()
	market_reservation_ids = list()
	stakeholder_departments = list()
	contact_departments = list(DEPARTMENT_CARGO)

// releases its market reservation.
/datum/contract/faction_agent/on_destroy(force)
	SSsupply?.release_agent_contract_market(src)
	..()

/datum/contract/faction_agent/on_accepted(mob/living/user, atom/source)
	. = ..()
	if(!SSsupply?.reserve_agent_contract_market(src))
		withdraw("The principal's authenticated market route could not be established.")
		return FALSE
	if(red_contract && !GLOB.station_faction_relations.activate_contract_operative(owner_account_number, id, user))
		withdraw("The explicit operative authorization could not be attached to its accepting account.")
		return FALSE
	issue_agent_fieldwork_documents(user, source)

/datum/contract/faction_agent/ui_details(mob/living/user)
	var/datum/reputation_faction/faction = GLOB.reputation_factions[agent_faction]
	return list(
		"kind" = "faction_agent",
		"confidential" = TRUE,
		"principal" = faction?.name || issuer_name,
		"tier" = faction_agent_tier_name(required_agent_tier),
		"red_contract" = red_contract,
		"requires_contact" = requires_contact,
		"contact" = contact_name,
		"contact_mode" = contact_mode,
		"contact_share" = contact_share_percent,
		"contact_cooperated" = contact_cooperated,
		"required_endorsements" = required_endorsements,
		"operation_kind" = operation_kind,
		"approach" = approach,
		"approach_name" = agent_approach_name(approach),
		"stakeholder_departments" = stakeholder_departments.Copy(),
		"outcome_grade" = outcome_grade,
		"outcome_score" = outcome_score,
		"discovery_stage" = discovery_stage,
		"discovery_name" = agent_discovery_name(discovery_stage),
		"notice" = red_contract ? "RED CONTRACT: accepting explicitly registers a bounded antagonist role for this written objective. It grants no authority beyond the objective or server rules." : "This is a confidential personal commission. Agency does not grant legal immunity, special access, or permission to ignore server rules.",
	)

/datum/contract_definition/faction_agent
	abstract_type = /datum/contract_definition/faction_agent
	scope = CONTRACT_SCOPE_PERSONAL
	contract_type = /datum/contract/faction_agent
	offer_duration = 12 MINUTES
	candidate_duration = 12 MINUTES
	offer_cooldown = 1 MINUTE
	repeat_cooldown = 3 MINUTES
	max_simultaneous = 128
	var/required_agent_tier = FACTION_AGENT_TIER_ACCREDITED

/datum/contract_definition/faction_agent/is_available(list/context)
	var/account_number = context?["owner_account"]
	var/faction_id = context?["agent_faction"]
	var/datum/faction_agent_record/record = GLOB.station_faction_relations.get_agent_record(account_number)
	if(!record || record.faction_id != faction_id || record.tier < required_agent_tier)
		return FALSE
	for(var/datum/contract/faction_agent/active_contract in SScontracts?.active_contracts)
		if(active_contract.owner_account_number == account_number)
			return FALSE
	for(var/datum/contract/faction_agent/grace_contract in SScontracts?.grace_contracts)
		if(grace_contract.owner_account_number == account_number)
			return FALSE
	return TRUE

/datum/contract_definition/faction_agent/prepare_accept(datum/contract/faction_agent/contract, datum/money_account/accepting_account, mob/living/user, atom/source)
	var/datum/faction_agent_record/record = GLOB.station_faction_relations.get_agent_record(contract.owner_account_number)
	return accepting_account?.account_number == contract.owner_account_number && record?.faction_id == contract.agent_faction && record.tier >= required_agent_tier

/datum/contract_definition/faction_agent/configure_contract(datum/contract/faction_agent/contract, list/context)
	var/faction_id = context?["agent_faction"]
	var/datum/reputation_faction/faction = GLOB.reputation_factions[faction_id]
	contract.owner_account_number = context?["owner_account"]
	contract.agent_faction = faction_id
	contract.required_agent_tier = required_agent_tier
	contract.issuer_faction = faction_id
	contract.issuer_name = "[faction?.name || "Confidential principal"] liaison office"
	contract.station_share = 0
	contract.department_share = 0
	contract.contributor_share = 1
	contract.station_reputation_reward = 0
	contract.department_reputation_reward = 0
	contract.personal_reputation_reward = 30
	contract.deadline_duration = 25 MINUTES
	contract.standing_score = get_personal_faction_reputation(contract.owner_account_number, faction_id) || REPUTATION_NEUTRAL
	contract.standing_tier = reputation_rank(contract.standing_score)
	if(required_agent_tier >= FACTION_AGENT_TIER_ACCREDITED)
		var/datum/contract_requirement/event_count/approach_requirement = new(CONTRACT_EVENT_AGENT_APPROACH_SIGNED, 1, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_CONTRACT)
		approach_requirement.name = "Signed operating charter"
		approach_requirement.description = "The agent must select and sign one physical operating approach before work can settle."
		approach_requirement.unique_field = "actor_account"
		contract.add_requirement(approach_requirement)
		var/datum/contract_requirement/event_count/contact = new(CONTRACT_EVENT_AGENT_CONTACT_SIGNED, 1, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_CONTRACT)
		contact.name = "Signed operational contact"
		contact.description = "An eligible stakeholder must sign one compensation and liability line on the physical contact agreement."
		contact.unique_field = "actor_account"
		contract.add_requirement(contact)

/datum/contract_definition/faction_agent/vetting
	id = "agent_vetting"
	title = "Authenticated Trade Vetting"
	description = "Purchase one reserved shipment with personal funds. Cargo will deliver the crate and establish your private trading relationship with the principal."
	reward = 500
	required_agent_tier = FACTION_AGENT_TIER_CANDIDATE
	offer_duration = 20 MINUTES

/datum/contract_definition/faction_agent/vetting/is_available(list/context)
	var/datum/faction_agent_record/record = GLOB.station_faction_relations.get_agent_record(context?["owner_account"])
	return record?.faction_id == context?["agent_faction"] && record.tier == FACTION_AGENT_TIER_CANDIDATE

/datum/contract_definition/faction_agent/vetting/configure_contract(datum/contract/faction_agent/contract, list/context)
	..()
	contract.requires_contact = FALSE
	var/datum/reputation_faction/faction = GLOB.reputation_factions[contract.agent_faction]
	contract.title = "[faction?.short_name || "Principal"] Authenticated Trade Vetting"
	contract.personal_reputation_reward = 15
	var/datum/contract_requirement/event_count/purchase = new(CONTRACT_EVENT_CARGO_MARKET_PURCHASE, CARGO_MARKET_VETTING_VALUE, null, "value", TRUE, CONTRACT_EVIDENCE_SCOPE_ANY)
	purchase.name = "Authenticated personal settlement"
	purchase.description = "Receive at least [CARGO_MARKET_VETTING_VALUE] Thalers of personally funded goods through the private reserved listing."
	purchase.require_value("actor_account", contract.owner_account_number)
	purchase.require_value("faction_id", contract.agent_faction)
	purchase.require_value("market_contract_key", contract.offer_key)
	contract.add_requirement(purchase)

/datum/contract_definition/faction_agent/red_exfiltration
	id = "agent_red_exfiltration"
	title = "RED: Controlled Technology Exfiltration"
	description = "Route a significant armaments portfolio to a deniable buyer. Once accepted, the commission authorizes covert action only insofar as required to complete this acquisition."
	reward = 5000
	required_agent_tier = FACTION_AGENT_TIER_TRUSTED

/datum/contract_definition/faction_agent/red_exfiltration/configure_contract(datum/contract/faction_agent/contract, list/context)
	var/profile_id = agent_red_profile(context?["agent_faction"])
	context["profile_id"] = profile_id
	..()
	contract.red_contract = TRUE
	contract.personal_reputation_reward = 60
	contract.deadline_duration = 35 MINUTES
	contract.offer_context["profile_id"] = profile_id
	contract.configure_operation(AGENT_OPERATION_CUSTODY)
	// Replace the ordinary custody specification with the faction's actual red
	// doctrine. The base charter/contact requirements remain shared.
	for(var/datum/contract_requirement/requirement in contract.requirements?.Copy())
		if(requirement.name in list("Signed operating charter", "Signed operational contact"))
			continue
		own_remove(contract, nameof(contract.requirements), requirement)
	contract.configure_red_operation(profile_id)
	var/list/brief = agent_red_brief(contract.agent_faction)
	contract.title = brief["title"]
	contract.description = brief["description"]

/datum/contract/covert_market_investigation
	var/suspect_account = 0

/datum/contract/covert_market_investigation/on_accepted(mob/living/user, atom/source)
	. = ..()
	after(SSsupply, 0.1 SECONDS, TYPE_PROC_REF(/datum/system/supply, replay_market_audit_evidence), with = list(src))

/datum/contract_definition/covert_market_investigation
	id = "covert_market_investigation"
	title = "Encrypted Trade Forensics"
	description = "NanoTrasen Internal Security requests correlation of distinct encrypted Cargo settlements. Audit transactions from the Supply market ledger; only traces that identify the same suspect account qualify."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_SECURITY
	issuer_name = "NanoTrasen Internal Security"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 2400
	contract_type = /datum/contract/covert_market_investigation
	offer_duration = 15 MINUTES
	max_simultaneous = 16

/datum/contract_definition/covert_market_investigation/configure_contract(datum/contract/covert_market_investigation/contract, list/context)
	contract.suspect_account = context?["suspect_account"]
	contract.station_share = 0.25
	contract.department_share = 0.5
	contract.contributor_share = 0.25
	contract.deadline_duration = 25 MINUTES
	contract.station_reputation_reward = 4
	contract.department_reputation_reward = 12
	contract.personal_reputation_reward = 6
	var/datum/contract_requirement/event_count/audits = new(CONTRACT_EVENT_COVERT_MARKET_AUDIT, 2, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	audits.name = "Correlated encrypted settlements"
	audits.description = "Identify two distinct encrypted market settlements tied to the same account."
	audits.unique_field = "transaction_id"
	audits.require_value("detected", TRUE)
	audits.require_value("suspect_account", context?["suspect_account"])
	contract.add_requirement(audits)

/proc/agent_target_profile(faction_id)
	switch(faction_id)
		if(REPUTATION_FACTION_NANOTRASEN)
			return "general_manufactured"
		if(REPUTATION_FACTION_SOLGOV)
			return "medical_goods"
		if(REPUTATION_FACTION_CHIMERA, REPUTATION_FACTION_VEYMED)
			return "medical_goods"
		if(REPUTATION_FACTION_ECLIPSE, REPUTATION_FACTION_SYNDICATE)
			return "research_goods"
		if(REPUTATION_FACTION_TALON)
			return "frontier_salvage"
		if(REPUTATION_FACTION_WORKERS_UNION)
			return "engineering_goods"
	return "general_manufactured"

/proc/agent_target_profile_name(profile_id)
	switch(profile_id)
		if("materials")
			return "Materials"
		if("research_goods")
			return "Prototype"
		if("engineering_goods")
			return "Engineering"
		if("medical_goods")
			return "Biological"
		if("food")
			return "Provision"
		if("weapons")
			return "Armament"
		if("frontier_salvage")
			return "Salvage"
	return "Manufactured Goods"
