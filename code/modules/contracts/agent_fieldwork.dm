/// World-facing faction agency. The PDA carries the brief; ordinary signed
/// paper, Cargo freight, and forensic tools carry the actual gameplay.

/proc/agent_contact_risk_rank(mode)
	switch(mode)
		if(AGENT_CONTACT_CONFIDENTIAL)
			return 2
		if(AGENT_CONTACT_DENIABLE)
			return 3
	return 1

/proc/agent_contact_mode_name(mode)
	switch(mode)
		if(AGENT_CONTACT_CONFIDENTIAL)
			return "confidential broker"
		if(AGENT_CONTACT_DENIABLE)
			return "deniable lead"
	return "registered contact"

/datum/controller/subsystem/contracts/proc/agent_contract_for_market_key(reservation_key) as /datum/contract/faction_agent
	if(!reservation_key)
		return null
	for(var/datum/contract/faction_agent/contract in active_contracts + grace_contracts)
		if(contract.offer_key == reservation_key)
			return contract
	return null

/datum/controller/subsystem/contracts/proc/agent_contact_contract(account_number, faction_id, reservation_key) as /datum/contract/faction_agent
	if(!account_number)
		return null
	for(var/datum/contract/faction_agent/contract in active_contracts + grace_contracts)
		if(contract.contact_cooperated || contract.contact_account_number != account_number || (faction_id && contract.agent_faction != faction_id) || (reservation_key && contract.offer_key != reservation_key))
			continue
		return contract
	return null

/datum/contract/faction_agent/proc/contact_has_cargo_authority(mob/living/user)
	var/obj/item/card/id/id_card = user?.GetIdCard()
	var/datum/money_account/account = contract_account_for_mob(user)
	return id_card && ((ACCESS_HEADS in id_card.access) || (account?.department_id in contact_departments))

/datum/contract/faction_agent/proc/register_contact(obj/item/paper/paper, mob/living/user, mode, evidence_id)
	if(!requires_contact || state != CONTRACT_ACTIVE || contact_account_number || !contact_has_cargo_authority(user))
		return FALSE
	var/datum/money_account/account = contract_account_for_mob(user)
	if(!account || account.account_number == owner_account_number || agent_contact_risk_rank(mode) < minimum_contact_risk)
		return FALSE
	switch(mode)
		if(AGENT_CONTACT_STANDARD)
			contact_share_percent = AGENT_CONTACT_STANDARD_SHARE
			contact_sales_commission = AGENT_CONTACT_STANDARD_COMMISSION
			contact_exposure = AGENT_CONTACT_STANDARD_EXPOSURE
		if(AGENT_CONTACT_CONFIDENTIAL)
			contact_share_percent = AGENT_CONTACT_CONFIDENTIAL_SHARE
			contact_sales_commission = AGENT_CONTACT_CONFIDENTIAL_COMMISSION
			contact_exposure = AGENT_CONTACT_CONFIDENTIAL_EXPOSURE
		if(AGENT_CONTACT_DENIABLE)
			contact_share_percent = AGENT_CONTACT_DENIABLE_SHARE
			contact_sales_commission = AGENT_CONTACT_DENIABLE_COMMISSION
			contact_exposure = AGENT_CONTACT_DENIABLE_EXPOSURE
		else
			return FALSE
	contact_account_number = account.account_number
	contact_name = account.owner_name
	contact_mode = mode
	contact_evidence_id = evidence_id
	var/datum/faction_agent_record/record = GLOB.station_faction_relations.get_agent_record(owner_account_number)
	if(record && (red_contract || mode != AGENT_CONTACT_STANDARD || agent_faction == REPUTATION_FACTION_SYNDICATE))
		GLOB.station_faction_relations.add_agent_exposure(owner_account_number, agent_faction, contact_exposure, "A signed [agent_contact_mode_name(mode)] agreement created discoverable commercial metadata.", "CONTACT-[id]")
	emit_contract_event(CONTRACT_EVENT_AGENT_CONTACT_SIGNED, list(
		"contract_id" = id,
		"actor_account" = account.account_number,
		"principal_account" = owner_account_number,
		"faction_id" = agent_faction,
		"operation_key" = offer_key,
		"contact_mode" = mode,
		"risk_rank" = agent_contact_risk_rank(mode),
		"share_percent" = contact_share_percent,
		"evidence_ids" = list(evidence_id),
		"detail" = "[account.owner_name] signed as [agent_contact_mode_name(mode)] for a [contact_share_percent]% contract share and [round(contact_sales_commission * 100)]% market-premium commission.",
	), "agent-contact:[id]:[account.account_number]", paper, user, user)
	notify_faction_agent_account(owner_account_number, "[account.owner_name] signed the physical freight agreement for [title] as [agent_contact_mode_name(mode)].")
	to_chat(user, span_notice("You are now personally recorded as [agent_contact_mode_name(mode)] for [title]. Your cut is [contact_share_percent]% of its reward plus [round(contact_sales_commission * 100)]% of qualifying market premiums. The agreement and routed freight can identify you."))
	return TRUE

/datum/contract/faction_agent/proc/register_endorsement(obj/item/paper/paper, mob/living/user, evidence_id, list/signers, list/signer_departments)
	if(state != CONTRACT_ACTIVE || required_endorsements <= 0)
		return FALSE
	var/datum/money_account/account = contract_account_for_mob(user)
	var/obj/item/card/id/id_card = user?.GetIdCard()
	var/key = "[account?.account_number]"
	if(!account || account.account_number == owner_account_number || !id_card || !(ACCESS_HEADS in id_card.access) || !(account.department_id in stakeholder_departments) || signers[key] || signer_departments[account.department_id])
		return FALSE
	signers[key] = account.owner_name
	signer_departments[account.department_id] = account.owner_name
	emit_contract_event(CONTRACT_EVENT_AGENT_ENDORSEMENT_SIGNED, list(
		"contract_id" = id,
		"actor_account" = account.account_number,
		"actor_department" = account.department_id,
		"principal_account" = owner_account_number,
		"faction_id" = agent_faction,
		"operation_key" = offer_key,
		"fact_id" = "agent-endorsement:[id]:[account.department_id]",
		"fact_revision" = 1,
		"fact_active" = TRUE,
		"evidence_ids" = list(evidence_id),
		"detail" = "[account.owner_name] signed a departmental endorsement for [title].",
	), "agent-endorsement:[id]:[account.account_number]", paper, user, user)
	to_chat(user, span_notice("Your departmental endorsement is now part of the physical [title] record."))
	return TRUE

/datum/contract/faction_agent/proc/issue_agent_fieldwork_documents(mob/living/user, atom/source)
	if(fieldwork_documents_issued || state != CONTRACT_ACTIVE)
		return FALSE
	fieldwork_documents_issued = TRUE
	var/turf/drop_location = get_turf(source || user)
	if(!drop_location)
		return FALSE
	var/registered_text = red_contract ? "Registered partnership is unavailable for this hostile mandate." : "Registered partnership: declare the relationship to participating departments; 20% of the award funds the station and 20% funds the lead department, with lower failure exposure. <span class=\"paper_field\"></span>"
	var/discreet_text = red_contract ? "Compartmentalized commission: conceal the principal but retain defensible custody records; standard award and trace exposure. <span class=\"paper_field\"></span>" : "Compartmentalized commission: disclose only what participating staff need; standard award and trace exposure. <span class=\"paper_field\"></span>"
	var/hostile_text = red_contract ? "Deniable hostile mandate: no institutional protection; 25% risk premium, strongest evidence and failure penalties. <span class=\"paper_field\"></span>" : "Deniable hostile mandate is unavailable without an explicit red contract."
	var/charter_info = {"<h2>Faction Operation Charter</h2>
		<b>Commission:</b> [title]<br><b>Principal:</b> [issuer_name]<br>
		<p>The commissioned agent must choose and sign exactly one operating approach. This paper is an ordinary physical record and does not itself grant station authority.</p>
		<b>Open:</b> [registered_text]<br>
		<b>Compartmentalized:</b> [discreet_text]<br>
		<b>Deniable:</b> [hostile_text]<br>"}
	create_contract_document(drop_location, "faction operation charter — [id]", charter_info, id, CONTRACT_DOCUMENT_AGENT_CHARTER, issuer_name, list(
		"agent_contract_id" = id,
		"principal_account" = owner_account_number,
		"faction_id" = agent_faction,
	))
	if(requires_contact)
		var/risk_notice = red_contract ? "<p><b>RED CONTRACT:</b> This agreement supports an explicitly hostile commission. Signing makes the contact a discoverable participant.</p>" : ""
		var/contact_info = {"<h2>External Freight Subcontract</h2>
			<b>Commission:</b> [title]<br><b>Principal:</b> [issuer_name]<br>
			<p>An employee from a listed stakeholder department must choose exactly one line and sign it with a pen. For freight work, this ordinary paper must travel inside any outbound contract crate.</p>
			<b>Eligible departments:</b> [english_list(contact_departments)]<br>[risk_notice]
			<b>Registered contact:</b> 35% of the contract reward and 5% of market premiums; ordinary attribution. <span class=\"paper_field\"></span><br>
			<b>Confidential broker:</b> 50% of the contract reward and 10% of market premiums; elevated forensic exposure. <span class=\"paper_field\"></span><br>
			<b>Deniable lead:</b> 65% of the contract reward and 15% of market premiums; the contact accepts primary intermediary exposure. <span class=\"paper_field\"></span><br>
			<hr><b>Contact cooperation declaration:</b> After signing a role above, the named contact may sign here to withdraw the routing credential and preserve this agreement for Security. This forfeits the faction cut; it grants no automatic immunity. <span class=\"paper_field\"></span><br>"}
		create_contract_document(drop_location, "external freight subcontract — [id]", contact_info, id, CONTRACT_DOCUMENT_AGENT_CONTACT, issuer_name, list(
			"agent_contract_id" = id,
			"principal_account" = owner_account_number,
			"faction_id" = agent_faction,
		))
	if(required_endorsements > 0)
		var/endorsement_info = {"<h2>Departmental Supplier Endorsement</h2>
			<b>Commission:</b> [title]<br><b>Requested endorsements:</b> [required_endorsements]<br>
			<p>Department heads may sign separate lines after discussing the proposed relationship with the agent. The paper remains an inspectable station record.</p>
			<b>Endorsement:</b> <span class=\"paper_field\"></span><br>
			<b>Endorsement:</b> <span class=\"paper_field\"></span><br>
			<b>Endorsement:</b> <span class=\"paper_field\"></span><br>"}
		create_contract_document(drop_location, "departmental supplier endorsement — [id]", endorsement_info, id, CONTRACT_DOCUMENT_AGENT_ENDORSEMENT, issuer_name, list(
			"agent_contract_id" = id,
			"principal_account" = owner_account_number,
			"faction_id" = agent_faction,
			"signers" = list(),
			"signer_departments" = list(),
		))
	to_chat(user, span_notice("The principal issued the fieldwork records for [title]. Recruit and negotiate face-to-face; your PDA will summarize only results the principal can authenticate."))
	return TRUE

/datum/contract/faction_agent/receive_event(datum/contract_event/event)
	if(requires_contact && (event?.event_type in list(CONTRACT_EVENT_CARGO_MARKET_PURCHASE, CONTRACT_EVENT_CARGO_MARKET_EXPORT)))
		if(event.value("market_contract_key") == offer_key && (!contact_account_number || event.actor_account != contact_account_number))
			return FALSE
	return ..()

/datum/contract/faction_agent/reward_recipient_weights()
	if(contact_cooperated)
		var/list/cooperation_weights = contributions.Copy()
		cooperation_weights -= "[contact_account_number]"
		if(!length(cooperation_weights))
			cooperation_weights["[owner_account_number]"] = 1
		return cooperation_weights
	if(!contact_account_number || contact_share_percent <= 0)
		return ..()
	var/list/weights = list()
	var/participant_pool = min(25, max(0, 100 - contact_share_percent - 10))
	var/other_contribution = 0
	for(var/key in contributions)
		if(text2num(key) in list(owner_account_number, contact_account_number))
			continue
		other_contribution += contributions[key]
	weights["[contact_account_number]"] = contact_share_percent
	weights["[owner_account_number]"] = 100 - contact_share_percent - (other_contribution > 0 ? participant_pool : 0)
	if(other_contribution > 0)
		for(var/key in contributions)
			if(text2num(key) in list(owner_account_number, contact_account_number))
				continue
			weights[key] = participant_pool * contributions[key] / other_contribution
	return weights

/datum/contract/faction_agent/proc/pay_contact_market_commission(market_premium)
	if(!contact_account_number || contact_sales_commission <= 0 || !isnum(market_premium) || market_premium <= 0)
		return 0
	var/commission = max(1, round(market_premium * contact_sales_commission))
	var/datum/money_account/contact_account = get_account(contact_account_number)
	if(!contact_account?.credit(commission, issuer_name, "Freight contact commission: [title]", "Cargo market", TRUE))
		return 0
	audit(CONTRACT_AUDIT_PAYMENT, "Paid [commission] Thalers of market-premium commission to [contact_name].")
	return commission

/datum/component/contract_document/proc/register_agent_contact_signature(obj/item/paper/paper, mob/living/user, field_id)
	if(document_kind != CONTRACT_DOCUMENT_AGENT_CONTACT || field_id < 1 || field_id > 4)
		return FALSE
	var/datum/contract/faction_agent/contract = SScontracts.contracts_by_id[payload["agent_contract_id"]]
	if(!istype(contract))
		return FALSE
	if(field_id == 4)
		return register_agent_contact_cooperation(paper, user, contract)
	if(payload["signed"])
		return FALSE
	var/mode = AGENT_CONTACT_STANDARD
	if(field_id == 2)
		mode = AGENT_CONTACT_CONFIDENTIAL
	else if(field_id == 3)
		mode = AGENT_CONTACT_DENIABLE
	if(!contract.register_contact(paper, user, mode, evidence_id))
		return FALSE
	payload["signed"] = TRUE
	payload["contact_account"] = contract.contact_account_number
	payload["contact_name"] = contract.contact_name
	payload["contact_mode"] = contract.contact_mode
	payload["signed_at"] = world.time
	paper.name = "signed external freight subcontract — [contract.id]"
	paper.info += "<br><b>Authenticated contact:</b> [html_encode(contract.contact_name)]<br><b>Terms:</b> [agent_contact_mode_name(contract.contact_mode)], [contract.contact_share_percent]% reward share.<br>"
	paper.updateinfolinks()
	return TRUE

/datum/component/contract_document/proc/register_agent_contact_cooperation(obj/item/paper/paper, mob/living/user, datum/contract/faction_agent/contract)
	if(!payload["signed"] || payload["cooperated"] || contract.state != CONTRACT_ACTIVE)
		return FALSE
	var/datum/money_account/account = contract_account_for_mob(user)
	if(account?.account_number != contract.contact_account_number)
		return FALSE
	payload["cooperated"] = TRUE
	payload["cooperated_at"] = world.time
	contract.contact_cooperated = TRUE
	contract.contact_share_percent = 0
	contract.contact_sales_commission = 0
	var/obj/structure/closet/crate/loaded_crate = locate(payload["shipment_ref"])
	if(istype(loaded_crate) && loaded_crate.cargo_market_contract_key == contract.offer_key)
		loaded_crate.cargo_market_bid_id = null
		loaded_crate.cargo_market_router_account = 0
		loaded_crate.cargo_market_contract_key = null
	paper.name = "withdrawn external freight subcontract — [contract.id]"
	paper.info += "<br><b>Authenticated withdrawal:</b> [html_encode(account.owner_name)] withdrew this routing credential and preserved it for potential station review.<br>"
	paper.updateinfolinks()
	to_chat(user, span_warning("You withdrew the route and forfeited its faction payment. Security must physically receive and examine this agreement before it becomes evidence; this declaration promises no immunity."))
	return TRUE

/datum/component/contract_document/proc/register_agent_endorsement(obj/item/paper/paper, mob/living/user)
	if(document_kind != CONTRACT_DOCUMENT_AGENT_ENDORSEMENT)
		return FALSE
	var/datum/contract/faction_agent/contract = SScontracts.contracts_by_id[payload["agent_contract_id"]]
	var/list/signers = payload["signers"]
	var/list/signer_departments = payload["signer_departments"]
	if(!istype(contract) || !islist(signers) || !islist(signer_departments) || !contract.register_endorsement(paper, user, evidence_id, signers, signer_departments))
		return FALSE
	paper.info += "<br><b>Authenticated endorsement:</b> [html_encode(contract_account_for_mob(user)?.owner_name || user.real_name)]<br>"
	paper.updateinfolinks()
	return TRUE

/datum/component/contract_document/proc/register_agent_approach_signature(obj/item/paper/paper, mob/living/user, field_id)
	if(document_kind != CONTRACT_DOCUMENT_AGENT_CHARTER || payload["signed"] || field_id < 1 || field_id > 3)
		return FALSE
	var/datum/contract/faction_agent/contract = SScontracts.contracts_by_id[payload["agent_contract_id"]]
	if(!istype(contract))
		return FALSE
	var/selected_approach = field_id == 1 ? AGENT_APPROACH_REGISTERED : (field_id == 2 ? AGENT_APPROACH_DISCREET : AGENT_APPROACH_HOSTILE)
	if(!contract.select_operation_approach(paper, user, selected_approach, evidence_id))
		return FALSE
	payload["signed"] = TRUE
	payload["approach"] = selected_approach
	payload["signed_at"] = world.time
	paper.name = "signed faction operation charter — [contract.id]"
	paper.info += "<br><b>Authenticated agent:</b> [html_encode(contract_account_for_mob(user)?.owner_name || user.real_name)]<br><b>Operating approach:</b> [agent_approach_name(selected_approach)].<br>"
	paper.updateinfolinks()
	return TRUE

/// The signed agreement is the routing credential. Cargo must physically put
/// it into a crate; reserved agent bids cannot be assigned from the UI.
/proc/process_agent_contract_export(atom/movable/shipment)
	var/obj/structure/closet/crate/crate = shipment
	if(!istype(crate))
		return FALSE
	var/list/all_contents = contract_export_contents(crate)
	for(var/obj/item/paper/paper in all_contents)
		var/datum/component/contract_document/document = paper.GetComponent(/datum/component/contract_document)
		if(document?.document_kind != CONTRACT_DOCUMENT_AGENT_CONTACT || !document.payload["signed"] || document.payload["cooperated"])
			continue
		var/datum/contract/faction_agent/contract = SScontracts.contracts_by_id[document.payload["agent_contract_id"]]
		if(!istype(contract) || !(contract.state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)) || contract.contact_account_number != document.payload["contact_account"])
			continue
		for(var/market_id in contract.market_reservation_ids)
			var/datum/cargo_market_bid/bid = SSsupply.market_bid(market_id)
			if(!bid || bid.completed_at || world.time >= bid.expires_at)
				continue
			crate.cargo_market_bid_id = bid.id
			crate.cargo_market_router_account = contract.contact_account_number
			crate.cargo_market_contract_key = contract.offer_key
			document.payload["loaded_at"] = world.time
			document.payload["shipment_ref"] = REF(crate)
			return TRUE
	return FALSE

/// Security discovers agreements by physically finding and scanning them.
/proc/process_agent_forensic_scan(atom/target, mob/living/user)
	if(!SSsupply?.market_security_auditor(user))
		return FALSE
	if(istype(target, /obj/machinery/computer/supplycomp))
		return SSsupply.audit_next_market_transaction(user)
	var/obj/item/paper/paper = target
	if(!istype(paper))
		return FALSE
	var/datum/component/contract_document/document = paper.GetComponent(/datum/component/contract_document)
	if(!(document?.document_kind in list(CONTRACT_DOCUMENT_AGENT_CONTACT, CONTRACT_DOCUMENT_AGENT_ENDORSEMENT, CONTRACT_DOCUMENT_AGENT_CHARTER)))
		return FALSE
	var/datum/contract/faction_agent/contract = SScontracts.contracts_by_id[document.payload["agent_contract_id"]]
	if(!istype(contract))
		return FALSE
	var/suspicious = contract.red_contract || (contract.approach in list(AGENT_APPROACH_DISCREET, AGENT_APPROACH_HOSTILE)) || contract.agent_faction == REPUTATION_FACTION_SYNDICATE || agent_contact_risk_rank(contract.contact_mode) >= 2
	if(!suspicious)
		to_chat(user, span_notice("The document authenticates a registered agency relationship. Its named parties and fingerprints remain on record, but it contains no encrypted or hostile routing marker."))
		return TRUE
	var/datum/money_account/auditor = contract_account_for_mob(user)
	var/auditor_key = "[auditor?.account_number || user.ckey]"
	var/list/security_scans = document.payload["security_scans"]
	if(!islist(security_scans))
		security_scans = list()
		document.payload["security_scans"] = security_scans
	if(security_scans[auditor_key])
		to_chat(user, span_warning("You already recorded this physical agreement."))
		return TRUE
	security_scans[auditor_key] = TRUE
	var/fact_id = "PAPER-[document.evidence_id]"
	var/datum/faction_agent_record/record = GLOB.station_faction_relations.get_agent_record(contract.owner_account_number)
	if(record)
		record.investigation_facts[fact_id] = list(
			"contact_account" = contract.contact_account_number,
			"detail" = "A physical [document.document_kind] connected [contract.contact_name || "an unidentified contact"] to [contract.issuer_name].",
		)
		GLOB.station_faction_relations.add_agent_exposure(contract.owner_account_number, contract.agent_faction, 20, "Security recovered authenticated physical agency paperwork.", fact_id)
	contract.advance_discovery(AGENT_DISCOVERY_PROVEN, "Security authenticated the operation's physical paperwork and named its participants.", 20)
	if(document.payload["cooperated"] && !document.payload["cooperation_paid"])
		document.payload["cooperation_paid"] = TRUE
		var/datum/money_account/cooperator = get_account(contract.contact_account_number)
		var/cooperation_award = min(750, max(150, round(contract.reward * 0.15)))
		cooperator?.credit(cooperation_award, "NanoTrasen Internal Security", "Authenticated cooperation: [contract.title]", "Security", TRUE)
		adjust_personal_faction_reputation(contract.contact_account_number, contract.agent_faction, -15)
		adjust_personal_faction_reputation(contract.contact_account_number, REPUTATION_FACTION_NANOTRASEN, 10)
		emit_contract_event(CONTRACT_EVENT_AGENT_CONTACT_COOPERATED, list(
			"contract_id" = contract.id,
			"actor_account" = contract.contact_account_number,
			"department" = DEPARTMENT_SECURITY,
			"faction_id" = contract.agent_faction,
			"evidence_ids" = list(document.evidence_id),
			"detail" = "The named contact surrendered an authenticated agreement and withdrew its freight credential.",
		), "agent-cooperation:[contract.id]:[document.evidence_id]", paper, user)
	emit_contract_event(CONTRACT_EVENT_COVERT_MARKET_AUDIT, list(
		"actor_account" = auditor?.account_number,
		"department" = DEPARTMENT_SECURITY,
		"transaction_id" = fact_id,
		"channel" = "physical_document",
		"detected" = TRUE,
		"suspect_account" = contract.owner_account_number,
		"contact_account" = contract.contact_account_number,
		"faction_id" = contract.agent_faction,
		"fact_id" = "agent-evidence:[fact_id]",
		"fact_revision" = length(security_scans),
		"fact_active" = TRUE,
		"detail" = "Authenticated physical agency paperwork identified a principal and freight contact.",
	), "agent-evidence:[fact_id]:[auditor_key]", paper, user, user)
	var/datum/money_account/principal = get_account(contract.owner_account_number)
	to_chat(user, span_warning("The document authenticates principal account [principal?.owner_name || contract.owner_account_number][contract.contact_account_number ? " and freight contact [contract.contact_name]" : ""]. Preserve the paper: it retains identifying fingerprints and may be used as evidence."))
	return TRUE

/datum/controller/subsystem/supply/proc/audit_next_market_transaction(mob/living/user)
	var/datum/money_account/auditor = contract_account_for_mob(user)
	var/auditor_key = "[auditor?.account_number || user.ckey]"
	for(var/index = length(market_transactions), index >= 1, index--)
		var/datum/cargo_market_transaction/transaction = market_transactions[index]
		if(!transaction.covert || transaction.audited_accounts[auditor_key])
			continue
		if(!audit_market_transaction(transaction.id, user))
			continue
		var/datum/money_account/contact = transaction.account_number ? get_account(transaction.account_number) : null
		if(transaction.detected)
			var/datum/money_account/principal = get_account(transaction.detected_account)
			to_chat(user, span_warning("The console's settlement cache correlates [transaction.id] with principal [principal?.owner_name || transaction.detected_account][contact && contact.account_number != transaction.detected_account ? " through freight contact [contact.owner_name]" : ""]."))
		else
			to_chat(user, span_notice("The console yields an encrypted settlement fragment for [transaction.id], but it is not yet strong enough to identify its principal."))
		return TRUE
	to_chat(user, span_notice("The console contains no unaudited encrypted settlement cache for your account."))
	return TRUE

/proc/agent_red_profile(faction_id)
	switch(faction_id)
		if(REPUTATION_FACTION_SOLGOV, REPUTATION_FACTION_SYNDICATE)
			return "weapons"
		if(REPUTATION_FACTION_CHIMERA, REPUTATION_FACTION_VEYMED)
			return "medical_goods"
		if(REPUTATION_FACTION_ECLIPSE, REPUTATION_FACTION_NANOTRASEN)
			return "research_goods"
		if(REPUTATION_FACTION_TALON)
			return "frontier_salvage"
		if(REPUTATION_FACTION_WORKERS_UNION)
			return "engineering_goods"
	return "general_manufactured"

/proc/agent_red_brief(faction_id) as /list
	switch(faction_id)
		if(REPUTATION_FACTION_NANOTRASEN)
			return list("title" = "RED: Proprietary Asset Reclamation", "description" = "Recover station-developed prototypes for an undisclosed NanoTrasen program. The written mandate authorizes theft and covert export only as needed for this objective.", "requirement" = "Proprietary prototype portfolio")
		if(REPUTATION_FACTION_SOLGOV)
			return list("title" = "RED: Embargoed Arms Seizure", "description" = "Divert controlled armaments into a sealed SolGov recovery channel without station authorization.", "requirement" = "Embargoed armaments portfolio")
		if(REPUTATION_FACTION_CHIMERA)
			return list("title" = "RED: Restricted Biological Acquisition", "description" = "Acquire restricted biological products for an off-books Chimera program. Theft and concealment are authorized only for the listed recovery.", "requirement" = "Restricted biological portfolio")
		if(REPUTATION_FACTION_ECLIPSE)
			return list("title" = "RED: Competitive Prototype Extraction", "description" = "Remove valuable station prototypes into Eclipse custody before their owner can restrict distribution.", "requirement" = "Competitive prototype portfolio")
		if(REPUTATION_FACTION_SYNDICATE)
			return list("title" = "RED: Controlled Technology Exfiltration", "description" = "Route a significant armaments portfolio to a deniable buyer. Acceptance explicitly registers a bounded contract-operative antagonist role for this objective until it closes.", "requirement" = "Deniable armaments portfolio")
		if(REPUTATION_FACTION_TRADERS_GUILD)
			return list("title" = "RED: Sanctioned Cargo Diversion", "description" = "Divert station property into an unregistered freeport portfolio despite any local claim to the goods.", "requirement" = "Diverted commercial portfolio")
		if(REPUTATION_FACTION_TALON)
			return list("title" = "RED: Contested Salvage Recovery", "description" = "Recover contested salvage and field equipment claimed by TALON before station authorities can retain it.", "requirement" = "Contested salvage portfolio")
		if(REPUTATION_FACTION_WORKERS_UNION)
			return list("title" = "RED: Seized Equipment Reclamation", "description" = "Remove technical equipment into a clandestine worker-controlled supply channel. The mandate permits theft only for that recovery.", "requirement" = "Reclaimed engineering portfolio")
		if(REPUTATION_FACTION_VEYMED)
			return list("title" = "RED: Confidential Clinical Recovery", "description" = "Recover restricted clinical products into VeyMed custody without station authorization.", "requirement" = "Confidential clinical portfolio")
	return list("title" = "RED: Restricted Asset Recovery", "description" = "Recover restricted station property through a covert freight route.", "requirement" = "Restricted asset portfolio")

// Reusable operation families. Faction doctrine composes different department
// events and requirements onto the shared physical charter/contact/evidence
// model; only sourcing operations necessarily resolve through freight.
/datum/contract_definition/faction_agent/cross_department_portfolio
	id = "agent_cross_department_portfolio"
	title = "Cross-Department Sourcing"
	description = "Broker a mixed external portfolio by negotiating with several station departments and a physically signed stakeholder."
	reward = 2600

/datum/contract_definition/faction_agent/cross_department_portfolio/configure_contract(datum/contract/faction_agent/contract, list/context)
	..()
	contract.configure_operation(AGENT_OPERATION_SOURCING)
	var/datum/reputation_faction/faction = GLOB.reputation_factions[contract.agent_faction]
	contract.title = "[faction?.short_name || "Principal"] [agent_target_profile_name(contract.offer_context["profile_id"])] Sourcing Operation"

/datum/contract_definition/faction_agent/reciprocal_trade
	id = "agent_reciprocal_trade"
	title = "Reciprocal Trade Mission"
	description = "Establish a measurable service relationship shaped by the principal's doctrine and the station departments it depends upon."
	reward = 3000

/datum/contract_definition/faction_agent/reciprocal_trade/configure_contract(datum/contract/faction_agent/contract, list/context)
	..()
	contract.market_allowance = 600
	contract.configure_operation(AGENT_OPERATION_SERVICE)

/datum/contract_definition/faction_agent/rush_brokerage
	id = "agent_rush_brokerage"
	title = "Time-Critical Brokerage"
	description = "Organize a time-critical, machine- or department-authenticated demonstration before the principal's observation window closes."
	reward = 2800

/datum/contract_definition/faction_agent/rush_brokerage/configure_contract(datum/contract/faction_agent/contract, list/context)
	..()
	contract.deadline_duration = 15 MINUTES
	contract.configure_operation(AGENT_OPERATION_DEMONSTRATION)

/datum/contract_definition/faction_agent/confidential_brokerage
	id = "agent_confidential_brokerage"
	title = "Confidential Brokerage Premium"
	description = "Recruit a contact willing to accept elevated personal exposure, then complete the faction's custody or transfer objective."
	reward = 3400

/datum/contract_definition/faction_agent/confidential_brokerage/configure_contract(datum/contract/faction_agent/contract, list/context)
	..()
	contract.minimum_contact_risk = 2
	var/datum/contract_requirement/event_count/risk_contact = new(CONTRACT_EVENT_AGENT_CONTACT_SIGNED, 1, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_CONTRACT)
	risk_contact.name = "Risk-premium contact"
	risk_contact.description = "An eligible stakeholder must sign either the confidential or deniable compensation line."
	risk_contact.require_number("risk_rank", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 2)
	contract.add_requirement(risk_contact)
	contract.configure_operation(AGENT_OPERATION_CUSTODY)

/datum/contract_definition/faction_agent/department_endorsement
	id = "agent_department_endorsement"
	title = "Departmental Supplier Endorsement"
	description = "Persuade department heads to accept institutional liability, then prove the endorsed relationship through real departmental outcomes."
	reward = 3200

/datum/contract_definition/faction_agent/department_endorsement/configure_contract(datum/contract/faction_agent/contract, list/context)
	..()
	contract.configure_operation(AGENT_OPERATION_INFLUENCE)
