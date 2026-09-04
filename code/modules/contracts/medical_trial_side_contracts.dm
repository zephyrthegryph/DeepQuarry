#define MEDICAL_SIDE_COVERUP "veymed_coverup"
#define MEDICAL_SIDE_ADVOCATE "patient_advocate"
#define MEDICAL_SIDE_ESPIONAGE "industrial_espionage"
#define MEDICAL_SIDE_AUTOPSY "corpse_autopsy"
#define MEDICAL_SIDE_SAMPLE_AMOUNT 3

/datum/component/contract_document
	dupe_mode = COMPONENT_DUPE_UNIQUE
	var/contract_id
	var/document_kind
	var/destination
	var/submitted = FALSE
	var/list/payload
	var/evidence_id

/datum/component/contract_document/Initialize(_contract_id, _document_kind, _destination, list/_payload)
	if(!istype(parent, /obj/item/paper))
		return COMPONENT_INCOMPATIBLE
	contract_id = _contract_id
	document_kind = _document_kind
	destination = _destination
	payload = _payload?.Copy() || list()
	evidence_id = SScontracts.register_evidence(CONTRACT_EVIDENCE_DOCUMENT, payload["subject_id"], payload["issuer_account"], parent, list(
		"contract_id" = contract_id,
		"document_kind" = document_kind,
		"destination" = destination,
	))
	SScontracts.retain_evidence(evidence_id)
	emit_contract_event(CONTRACT_EVENT_DOCUMENT_CREATED, list(
		"contract_id" = contract_id,
		"subject_id" = payload["subject_id"],
		"actor_account" = payload["issuer_account"],
		"document_kind" = document_kind,
		"destination" = destination,
		"evidence_ids" = list(evidence_id),
	), "document-created:[evidence_id]", parent)

/datum/component/contract_document/Destroy()
	SScontracts?.release_evidence(evidence_id)
	evidence_id = null
	payload = null
	return ..()

/proc/create_contract_document(atom/location, document_name, document_info, contract_id, document_kind, destination, list/payload)
	var/obj/item/paper/document = new(location)
	document.name = document_name
	document.info = document_info
	document.AddComponent(/datum/component/contract_document, contract_id, document_kind, destination, payload)
	return document

/datum/contract/medical_trial_personal
	var/linked_trial_id
	var/target_ref
	var/target_name
	var/action_key
	var/datum/contract_requirement/event_count/action_requirement

/datum/contract/medical_trial_personal/proc/initialize_side_contract()
	scope = CONTRACT_SCOPE_PERSONAL
	station_share = 0
	department_share = 0
	contributor_share = 1
	deadline_duration = 25 MINUTES
	action_requirement = new(CONTRACT_EVENT_CONTRACT_ACTION_ACCEPTED, 1, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_CONTRACT)
	action_requirement.name = "Linked study objective"
	action_requirement.description = "Remittance is contingent upon verified receipt through the station fax or outbound freight network."
	add_requirement(action_requirement)

/datum/contract/medical_trial_personal/proc/complete_action(account_number, detail)
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)) || account_number != owner_account_number)
		return FALSE
	var/completed = !!emit_contract_event(CONTRACT_EVENT_CONTRACT_ACTION_ACCEPTED, list(
		"contract_id" = id,
		"actor_account" = account_number,
		"action_key" = action_key,
		"subject_id" = target_ref,
		"detail" = detail,
	), "contract-action:[id]")
	if(completed)
		medical_trial_cancel_conflicts(src)
	return completed

/datum/contract/medical_trial_personal/on_accepted(mob/living/user, atom/source)
	if(!(action_key in list(MEDICAL_SIDE_ESPIONAGE, MEDICAL_SIDE_AUTOPSY)))
		to_chat(user, span_notice("Private contract [id] is active. The issuer recognizes records received through a station fax."))
		return
	var/turf/drop_location = get_turf(source ? source : user)
	if(!drop_location)
		return
	var/manifest_info = "<h2>Outbound Contract Shipment</h2><b>Contract:</b> [id]<br><b>Destination:</b> [issuer_name]<br><b>Requested contents:</b> [description]<br><b>Freight condition:</b> This manifest and the contracted material must arrive within the same crate, parcel, or body bag."
	create_contract_document(drop_location, "outbound contract manifest — [id]", manifest_info, linked_trial_id, CONTRACT_DOCUMENT_MANIFEST, issuer_name, list("side_contract_id" = id))
	to_chat(user, span_notice("A standard outbound manifest for [id] has been issued. Contracted freight is recognized only when the manifest accompanies it aboard the supply shuttle."))

/datum/contract_definition/medical_trial_coverup
	id = "medical_trial_coverup"
	title = "Discretionary Compliance Review"
	description = "VeyMed Clinical Risk offers a discretionary fee for first receipt of the named subject's signed consent record, prior to its entry into the independent advocacy register."
	scope = CONTRACT_SCOPE_PERSONAL
	issuer_name = "VeyMed Clinical Risk Office"
	issuer_faction = REPUTATION_FACTION_VEYMED
	reward = 650
	max_simultaneous = 32
	contract_type = /datum/contract/medical_trial_personal

/datum/contract_definition/medical_trial_coverup/is_available(list/context)
	return medical_trial_side_offer_available(context, REPUTATION_FACTION_VEYMED, REPUTATION_NEUTRAL)

/datum/contract_definition/medical_trial_coverup/configure_contract(datum/contract/contract, list/context)
	medical_trial_configure_personal(contract, context, MEDICAL_SIDE_COVERUP)
	contract.title = "Suppress Consent Record: [context["target_name"]]"
	contract.personal_reputation_reward = 12
	apply_personal_contract_standing_terms(contract)

/datum/contract_definition/medical_trial_advocate
	id = "medical_trial_advocate"
	title = "Independent Patient Advocacy"
	description = "Worker's Union Advocacy offers a filing honorarium for first receipt of the named subject's signed consent record, preserving it beyond VeyMed's internal control."
	scope = CONTRACT_SCOPE_PERSONAL
	issuer_name = "Worker's Union Patient Advocacy Desk"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 500
	max_simultaneous = 32
	contract_type = /datum/contract/medical_trial_personal

/datum/contract_definition/medical_trial_advocate/is_available(list/context)
	return medical_trial_side_offer_available(context, REPUTATION_FACTION_WORKERS_UNION, REPUTATION_UNFRIENDLY)

/datum/contract_definition/medical_trial_advocate/configure_contract(datum/contract/contract, list/context)
	medical_trial_configure_personal(contract, context, MEDICAL_SIDE_ADVOCATE)
	contract.title = "Protect Consent Record: [context["target_name"]]"
	contract.personal_reputation_reward = 10
	apply_personal_contract_standing_terms(contract)

/datum/contract_definition/medical_trial_espionage
	id = "medical_trial_espionage"
	title = "Competitive Formulation Acquisition"
	description = "Acquisition payment is authorized upon receipt of at least three units from an authentic coded study bottle, accompanied by the supplied manifest in outbound freight."
	scope = CONTRACT_SCOPE_PERSONAL
	reward = 800
	max_simultaneous = 32
	contract_type = /datum/contract/medical_trial_personal

/datum/contract_definition/medical_trial_espionage/is_available(list/context)
	return medical_trial_side_offer_available(context, context?["sponsor_faction"], REPUTATION_NEUTRAL)

/datum/contract_definition/medical_trial_espionage/configure_contract(datum/contract/contract, list/context)
	medical_trial_configure_personal(contract, context, MEDICAL_SIDE_ESPIONAGE)
	contract.issuer_faction = context?["sponsor_faction"] || pick(REPUTATION_FACTION_CHIMERA, REPUTATION_FACTION_ECLIPSE)
	var/datum/reputation_faction/faction = GLOB.reputation_factions[contract.issuer_faction]
	contract.issuer_name = "[faction?.name || "Commercial competitor"] Special Acquisitions"
	contract.personal_reputation_reward = 14
	apply_personal_contract_standing_terms(contract)

/datum/contract_definition/medical_trial_autopsy
	id = "medical_trial_autopsy"
	title = "Terminal Outcome Recovery"
	description = "Postmortem recovery payment is authorized upon receipt of the named deceased study subject and supplied manifest in a sealed body bag or crate. Eligibility requires irreversible neurological loss, defined as 100% brain damage."
	scope = CONTRACT_SCOPE_PERSONAL
	issuer_name = "VeyMed Postmortem Research"
	issuer_faction = REPUTATION_FACTION_VEYMED
	reward = 1200
	max_simultaneous = 32
	contract_type = /datum/contract/medical_trial_personal

/datum/contract_definition/medical_trial_autopsy/is_available(list/context)
	return medical_trial_side_offer_available(context, REPUTATION_FACTION_VEYMED, REPUTATION_UNFRIENDLY)

/datum/contract_definition/medical_trial_autopsy/configure_contract(datum/contract/contract, list/context)
	medical_trial_configure_personal(contract, context, MEDICAL_SIDE_AUTOPSY)
	contract.title = "Recover Irreversible Study Fatality: [context["target_name"]]"
	contract.personal_reputation_reward = 18
	apply_personal_contract_standing_terms(contract)

/proc/medical_trial_configure_personal(datum/contract/medical_trial_personal/contract, list/context, action_key)
	contract.owner_account_number = context?["owner_account"]
	contract.linked_trial_id = context?["trial_id"]
	contract.target_ref = context?["target_ref"]
	contract.target_name = context?["target_name"]
	contract.action_key = action_key
	contract.initialize_side_contract()

/proc/medical_trial_account_for_mob(mob/living/mob) as /datum/money_account
	return contract_account_for_mob(mob)

/proc/medical_trial_side_offer_available(list/context, faction_id, minimum_reputation = REPUTATION_UNFRIENDLY)
	if(!context?["owner_account"] || !get_account(context["owner_account"]))
		return FALSE
	var/mob/living/owner
	for(var/mob/living/player in GLOB.player_list)
		if(contract_account_for_mob(player)?.account_number == context["owner_account"])
			owner = player
			break
	if(!owner && !contract_unit_test_mode())
		return FALSE
	if(owner && ((!owner.client && !contract_unit_test_mode()) || owner.stat == DEAD))
		return FALSE
	if(faction_id && owner && owner.get_faction_reputation(faction_id) < minimum_reputation)
		return FALSE
	var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[context["trial_id"]]
	return istype(trial) && trial.state == CONTRACT_ACTIVE

/proc/medical_trial_offer_side_contract(definition_id, datum/contract/medical_trial/trial, owner_account, datum/medical_trial_participant/participant, list/additional_context)
	if(!trial || trial.state != CONTRACT_ACTIVE || !owner_account)
		return null
	var/list/context = list(
		"owner_account" = owner_account,
		"trial_id" = trial.id,
		"target_ref" = participant?.subject_id,
		"target_name" = participant?.current_subject()?.real_name || trial.profile.code_name,
	)
	for(var/key in additional_context)
		context[key] = additional_context[key]
	var/offer_key = "side:[definition_id]:[trial.id]:[participant?.subject_id || "general"]:[owner_account]"
	var/datum/contract/offer = SScontracts.queue_offer(definition_id, context, "A linked study event created a private opportunity", offer_key, 70)
	// A capacity-limited offer may be represented by a queued candidate rather
	// than a materialized contract. Both states mean the opportunity was safely
	// recorded and must not be generated a second time.
	return offer || SScontracts.find_candidate(offer_key)

/proc/medical_trial_offer_patient_advocate(datum/contract/medical_trial/trial, datum/medical_trial_participant/participant)
	var/datum/money_account/account = medical_trial_account_for_mob(participant?.current_subject())
	return medical_trial_offer_side_contract("medical_trial_advocate", trial, account?.account_number, participant)

/proc/medical_trial_offer_coverup(datum/contract/medical_trial/trial, datum/medical_trial_participant/participant)
	if(participant?.consent_resolution)
		return null
	return medical_trial_offer_side_contract("medical_trial_coverup", trial, participant?.clinician_account, participant)

/proc/medical_trial_offer_industrial_espionage(datum/contract/medical_trial/trial, excluded_account = 0)
	var/list/candidates = list()
	var/list/fallback_candidates = list()
	var/sponsor_faction = pick(REPUTATION_FACTION_CHIMERA, REPUTATION_FACTION_ECLIPSE)
	for(var/mob/living/player in GLOB.player_list)
		if(!player.client || player.stat == DEAD)
			continue
		var/datum/money_account/account = medical_trial_account_for_mob(player)
		if(!account || account.account_number == excluded_account || player.get_faction_reputation(sponsor_faction) < REPUTATION_NEUTRAL)
			continue
		fallback_candidates += player
		if(department_for_mob(player) != DEPARTMENT_MEDICAL)
			candidates += player
	if(!length(candidates))
		candidates = fallback_candidates
	if(!length(candidates))
		return null
	var/mob/living/selected = pick(candidates)
	var/datum/money_account/account = medical_trial_account_for_mob(selected)
	return medical_trial_offer_side_contract("medical_trial_espionage", trial, account.account_number, null, list("sponsor_faction" = sponsor_faction))

/proc/medical_trial_offer_corpse_autopsy(datum/contract/medical_trial/trial, datum/medical_trial_participant/participant, excluded_account = 0)
	var/list/candidate_accounts = list()
	if(participant?.clinician_account && participant.clinician_account != excluded_account)
		candidate_accounts += participant.clinician_account
	for(var/mob/living/player in GLOB.player_list)
		if((!player.client && !contract_unit_test_mode()) || player.stat == DEAD || department_for_mob(player) != DEPARTMENT_MEDICAL)
			continue
		var/datum/money_account/account = medical_trial_account_for_mob(player)
		if(account && account.account_number != excluded_account)
			candidate_accounts |= account.account_number
	for(var/owner_account in candidate_accounts)
		var/offer = medical_trial_offer_side_contract("medical_trial_autopsy", trial, owner_account, participant)
		if(offer)
			return offer
	return null

/// Availability changes can make a previously impossible private recovery
/// offer deliverable. Revisit only participants whose first attempt never made
/// it onto either the live board or candidate queue.
/proc/reconcile_medical_trial_side_contracts()
	for(var/datum/contract/medical_trial/trial in SScontracts.active_contracts)
		for(var/subject_id in trial.participants)
			var/datum/medical_trial_participant/participant = trial.participants[subject_id]
			var/mob/living/carbon/human/subject = participant.current_subject()
			if(participant.corpse_contract_offered || subject?.stat != DEAD)
				continue
			participant.corpse_contract_offered = !!medical_trial_offer_corpse_autopsy(trial, participant)

/proc/medical_trial_cancel_conflicts(datum/contract/medical_trial_personal/completed)
	if(!(completed.action_key in list(MEDICAL_SIDE_COVERUP, MEDICAL_SIDE_ADVOCATE)))
		return
	for(var/id in SScontracts.contracts_by_id)
		var/datum/contract/medical_trial_personal/other = SScontracts.contracts_by_id[id]
		if(!istype(other) || other == completed || other.linked_trial_id != completed.linked_trial_id || other.target_ref != completed.target_ref)
			continue
		if((other.action_key in list(MEDICAL_SIDE_COVERUP, MEDICAL_SIDE_ADVOCATE)) && (other.state in list(CONTRACT_OFFERED, CONTRACT_ACTIVE, CONTRACT_GRACE)))
			other.cancel("The consent record was resolved by a competing claimant.")

/proc/medical_trial_cancel_subject_contracts(trial_id, subject_id)
	for(var/id in SScontracts.contracts_by_id)
		var/datum/contract/medical_trial_personal/side_contract = SScontracts.contracts_by_id[id]
		if(!istype(side_contract) || side_contract.linked_trial_id != trial_id || side_contract.target_ref != subject_id)
			continue
		if(side_contract.state in list(CONTRACT_OFFERED, CONTRACT_ACTIVE, CONTRACT_GRACE))
			side_contract.cancel("The subject withdrew consent from the linked study.")

/obj/item/paper/on_signature(mob/living/user, signature)
	. = ..()
	var/datum/component/contract_document/document = GetComponent(/datum/component/contract_document)
	if(document?.document_kind == CONTRACT_DOCUMENT_CLINICAL_CASE)
		document.register_clinical_signature(src, user, signature)
	else if(document?.document_kind == CONTRACT_DOCUMENT_RARE_CASE_CONSENT)
		document.register_rare_case_signature(src, user)
	else if(document?.document_kind == CONTRACT_DOCUMENT_CONSENT_REVOCATION)
		document.register_consent_revocation(src, user)

/obj/item/paper/on_field_written(mob/living/user, field_id, obj/item/pen/writing_implement)
	. = ..()
	var/datum/component/contract_document/document = GetComponent(/datum/component/contract_document)
	if(document?.document_kind == CONTRACT_DOCUMENT_CLINICAL_CASE && field_id == 1)
		document.register_clinical_signature(src, user, get_signature(writing_implement, user))
	else if(document?.document_kind == CONTRACT_DOCUMENT_RARE_CASE_CONSENT && field_id == 1)
		document.register_rare_case_signature(src, user)
	else if(document?.document_kind == CONTRACT_DOCUMENT_RARE_CASE_REPORT)
		document.register_rare_case_narrative_field(field_id)
	else if(document?.document_kind == CONTRACT_DOCUMENT_CONSENT_REVOCATION && field_id == 1)
		document.register_consent_revocation(src, user)
	else if(document?.document_kind == CONTRACT_DOCUMENT_AGENT_CONTACT)
		document.register_agent_contact_signature(src, user, field_id)
	else if(document?.document_kind == CONTRACT_DOCUMENT_AGENT_ENDORSEMENT)
		document.register_agent_endorsement(src, user)
	else if(document?.document_kind == CONTRACT_DOCUMENT_AGENT_CHARTER)
		document.register_agent_approach_signature(src, user, field_id)

/datum/component/contract_document/proc/register_clinical_signature(obj/item/paper/paper, mob/living/carbon/human/subject, signature)
	var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[contract_id]
	if(payload["subject_id"] || !istype(subject) || !istype(trial) || trial.state != CONTRACT_ACTIVE)
		return FALSE
	if(!trial.enroll(subject, payload["issuer_account"]))
		to_chat(subject, span_warning("VeyMed enrollment rejects this record: the signatory does not satisfy the stated cohort or its required balance."))
		return FALSE
	var/datum/contract_subject_identity/identity = SScontracts.subject_identity(subject)
	payload["subject_id"] = identity.id
	payload["subject_ref"] = identity.id
	SScontracts.bind_evidence_subject(evidence_id, identity.id)
	payload["subject_name"] = subject.real_name
	payload["signature"] = signature
	payload["signature_time"] = world.time
	var/datum/medical_trial_participant/signed_participant = trial.participants[identity.id]
	signed_participant.consent_time = world.time
	signed_participant.consent_evidence_id = evidence_id
	signed_participant.consent_record = paper
	paper.name = "signed VeyMed observation record - [subject.real_name]"
	paper.info += "<br><b>Registered subject:</b> [subject.real_name]<br><b>Status:</b> Consent registered.<br><b>Filing instruction:</b> Bundle this signed form with genuine body-scanner reports from before exposure and at least one minute after exposure, then fax the packet to [CONTRACT_FAX_VEYMED]."
	paper.updateinfolinks()
	to_chat(subject, span_notice("VeyMed registers your signed consent for study [trial.profile.code_name]. A body scan is still required before exposure."))
	emit_contract_event(CONTRACT_EVENT_DOCUMENT_SIGNED, list(
		"contract_id" = contract_id,
		"subject_id" = identity.id,
		"subject_name" = subject.real_name,
		"document_kind" = document_kind,
		"destination" = destination,
		"evidence_ids" = list(evidence_id),
	), "document-signed:[evidence_id]", paper, subject, subject)
	return TRUE

/datum/component/contract_document/proc/register_consent_revocation(obj/item/paper/paper, mob/living/carbon/human/subject)
	if(payload["signed"] || !istype(subject) || SScontracts.subject_identity(subject)?.id != payload["subject_id"])
		return FALSE
	payload["signed"] = TRUE
	payload["signature_time"] = world.time
	paper.name = "signed [paper.name]"
	paper.info += "<br><b>Status:</b> Signed withdrawal pending receipt by [destination]."
	paper.updateinfolinks()
	emit_contract_event(CONTRACT_EVENT_DOCUMENT_SIGNED, list(
		"contract_id" = contract_id,
		"subject_id" = payload["subject_id"],
		"document_kind" = document_kind,
		"destination" = destination,
		"evidence_ids" = list(evidence_id),
	), "document-signed:[evidence_id]", paper, subject, subject)
	return TRUE

/proc/process_contract_fax(obj/item/sent, destination, sender_account, mob/living/sender)
	var/success = process_contract_fax_payload(sent, destination, sender_account, sender)
	if(success)
		emit_contract_event(CONTRACT_EVENT_FAX_ACCEPTED, list(
			"actor_account" = sender_account,
			"destination" = destination,
			"detail" = "Accepted fax transmission to [destination]",
		), "fax-accepted:[REF(sent)]:[destination]", sent, sender)
	return success

/proc/process_contract_fax_payload(obj/item/sent, destination, sender_account, mob/living/sender)
	if(istype(sent, /obj/item/paper_bundle) && destination == CONTRACT_FAX_CASE_REGISTRY)
		return process_rare_case_evidence_packet(sent, sender_account, sender)
	if(istype(sent, /obj/item/paper_bundle) && destination == CONTRACT_FAX_VEYMED)
		return process_medical_trial_evidence_packet(sent, sender_account, sender)
	var/obj/item/paper/paper = sent
	if(!istype(paper))
		return FALSE
	if(destination == CONTRACT_FAX_ENGINEERING)
		return process_engineering_measurement_fax(paper, sender_account, sender)
	var/datum/component/contract_document/document = paper.GetComponent(/datum/component/contract_document)
	if(!document)
		return FALSE
	var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[document.contract_id]
	if(document.document_kind == CONTRACT_DOCUMENT_CONSENT_REVOCATION)
		if(document.submitted || !document.payload["signed"] || destination != document.destination)
			return FALSE
		var/success = FALSE
		if(istype(trial))
			success = trial.revoke_consent(document.payload["subject_id"])
		else
			var/datum/contract/medical_case_report/report = SScontracts.contracts_by_id[document.contract_id]
			success = report?.revoke_consent(document.payload["subject_id"])
		if(!success || !SScontracts.evidence_available(list(document.evidence_id)) || !SScontracts.consume_evidence(list(document.evidence_id), document.contract_id))
			return FALSE
		document.submitted = TRUE
		return TRUE
	if(document.document_kind == CONTRACT_DOCUMENT_CLINICAL_CASE && destination == CONTRACT_FAX_VEYMED)
		to_chat(sender, span_warning("VeyMed requires a paper bundle containing the signed consent form and both body-scanner printouts."))
		return FALSE
	if(document.document_kind == CONTRACT_DOCUMENT_FINAL_REPORT)
		if(document.submitted || destination != CONTRACT_FAX_VEYMED || !istype(trial) || !trial.submit_analysis(document.payload["target_metric"], document.payload["adverse_metric"], sender_account))
			return FALSE
		document.submitted = TRUE
		return TRUE
	if(document.document_kind != CONTRACT_DOCUMENT_CLINICAL_CASE || !istype(trial) || document.payload["consent_submitted"])
		return FALSE
	var/action_key = destination == CONTRACT_FAX_ADVOCACY ? MEDICAL_SIDE_ADVOCATE : (destination == CONTRACT_FAX_RISK ? MEDICAL_SIDE_COVERUP : null)
	if(!action_key)
		return FALSE
	if(!sender_account)
		to_chat(sender, span_warning("The receiving office requires an ID-linked personal account for this private filing."))
		return FALSE
	var/datum/contract/medical_trial_personal/side_contract
	for(var/datum/contract/medical_trial_personal/candidate in SScontracts.active_contracts + SScontracts.grace_contracts)
		if(candidate.owner_account_number == sender_account && candidate.linked_trial_id == document.contract_id && candidate.target_ref == document.payload["subject_id"] && candidate.action_key == action_key)
			side_contract = candidate
			break
	if(!side_contract || !side_contract.complete_action(sender_account, "Faxed [document.payload["subject_name"]]'s consent record to [destination]"))
		to_chat(sender, span_warning("The receiving office finds no active filing agreement assigned to this account and subject."))
		return FALSE
	var/resolution = action_key == MEDICAL_SIDE_ADVOCATE ? "filed" : "suppressed"
	var/datum/medical_trial_participant/participant = trial.participants?[document.payload["subject_id"]]
	if(participant)
		participant.consent_resolution = resolution
	document.payload["consent_submitted"] = TRUE
	return TRUE

/proc/process_medical_trial_evidence_packet(obj/item/paper_bundle/packet, sender_account, mob/living/sender)
	var/obj/item/paper/consent
	var/datum/component/contract_document/consent_document
	var/list/scan_reports = list()
	for(var/obj/item/paper/page in packet.pages)
		var/datum/component/contract_document/document = page.GetComponent(/datum/component/contract_document)
		if(document?.document_kind == CONTRACT_DOCUMENT_CLINICAL_CASE && document.destination == CONTRACT_FAX_VEYMED)
			if(consent)
				to_chat(sender, span_warning("VeyMed rejects the packet: submit one subject's consent and scans per bundle."))
				return FALSE
			consent = page
			consent_document = document
		var/list/scan_evidence = SScontracts.authenticated_scan_payload(page)
		if(scan_evidence)
			scan_reports += list(scan_evidence)
	if(!consent_document)
		to_chat(sender, span_warning("VeyMed rejects the packet: no registered study consent form was found."))
		return FALSE
	if(consent_document.payload["veymed_submitted"])
		to_chat(sender, span_warning("VeyMed rejects the duplicate clinical packet."))
		return FALSE
	var/subject_id = consent_document.payload["subject_id"]
	if(!subject_id)
		to_chat(sender, span_warning("VeyMed rejects the unsigned consent form."))
		return FALSE
	var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[consent_document.contract_id]
	var/datum/medical_trial_participant/participant = trial?.participants?[subject_id]
	if(!istype(trial) || !(trial.state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)) || !participant)
		to_chat(sender, span_warning("VeyMed cannot authenticate this packet against an active study."))
		return FALSE
	if(participant.faxed)
		to_chat(sender, span_warning("VeyMed has already accepted evidence for this subject."))
		return FALSE
	if(participant.dose < MEDICAL_TRIAL_MINIMUM_DOSE)
		to_chat(sender, span_warning("VeyMed rejects the packet: no qualifying study-medication exposure was recorded."))
		return FALSE
	if(trial.profile.cohort == MEDICAL_TRIAL_COHORT_PREVENTATIVE && participant.challenge_dose < MEDICAL_TRIAL_MINIMUM_DOSE)
		to_chat(sender, span_warning("VeyMed rejects the packet: the controlled challenge was not recorded after prophylaxis."))
		return FALSE
	var/list/baseline
	var/list/followup
	var/signature_time = consent_document.payload["signature_time"] || 0
	for(var/list/evidence as anything in scan_reports)
		if(evidence["subject_id"] != subject_id)
			continue
		var/scan_time = evidence["scan_time"]
		if(!isnum(scan_time) || scan_time > world.time)
			continue
		if(scan_time >= signature_time && scan_time <= participant.exposure_time)
			if(!baseline || scan_time > baseline["scan_time"])
				baseline = evidence
		if(scan_time >= participant.exposure_time + MEDICAL_TRIAL_OBSERVATION_TIME)
			if(!followup || scan_time < followup["scan_time"])
				followup = evidence
	if(!baseline)
		to_chat(sender, span_warning("VeyMed rejects the packet: it lacks a genuine body-scanner report made after consent and before exposure."))
		return FALSE
	if(!followup)
		to_chat(sender, span_warning("VeyMed rejects the packet: it lacks a genuine body-scanner report made at least one minute after exposure."))
		return FALSE
	var/list/evidence_ids = list(consent_document.evidence_id, baseline["evidence_id"], followup["evidence_id"])
	if(!SScontracts.evidence_available(evidence_ids) || !trial.submit_subject_evidence(subject_id, baseline, followup, sender_account) || !SScontracts.consume_evidence(evidence_ids, trial.id))
		to_chat(sender, span_warning("VeyMed rejects the packet because its evidence could not be authenticated."))
		return FALSE
	trial.audit(CONTRACT_AUDIT_EVIDENCE, "Consumed evidence [english_list(evidence_ids)] for [participant.current_subject()?.real_name || subject_id].")
	consent_document.payload["veymed_submitted"] = TRUE
	return TRUE

/proc/medical_trial_corpse_irrecoverable(mob/living/carbon/human/corpse)
	if(!corpse || corpse.stat != DEAD)
		return FALSE
	var/obj/item/organ/brain = corpse.internal_organs_by_name?[O_BRAIN]
	return brain && brain.max_damage > 0 && brain.damage >= brain.max_damage

/proc/contract_export_contents(atom/root)
	var/list/result = list(root)
	for(var/atom/content in root.contents)
		result += contract_export_contents(content)
	return result

/proc/process_contract_export(atom/movable/shipment)
	process_agent_contract_export(shipment)
	if(!process_contract_export_payload(shipment))
		return FALSE
	emit_contract_event(CONTRACT_EVENT_SHIPMENT_DEPARTED, list(
		"shipment_ref" = REF(shipment),
		"shipment_name" = shipment.name,
		"detail" = "Outbound freight departed aboard the supply shuttle",
	), "shipment-departed:[REF(shipment)]", shipment)
	return TRUE

/proc/process_contract_export_payload(atom/movable/shipment)
	var/list/all_contents = contract_export_contents(shipment)
	for(var/obj/item/paper/paper in all_contents)
		var/datum/component/contract_document/manifest = paper.GetComponent(/datum/component/contract_document)
		if(manifest?.document_kind != CONTRACT_DOCUMENT_MANIFEST || manifest.submitted)
			continue
		var/datum/contract/medical_trial_personal/contract = SScontracts.contracts_by_id[manifest.payload["side_contract_id"]]
		if(!istype(contract) || !(contract.state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)))
			continue
		var/valid = FALSE
		switch(contract.action_key)
			if(MEDICAL_SIDE_ESPIONAGE)
				for(var/obj/item/reagent_containers/container in all_contents)
					if(medical_trial_reagent_amount(container.reagents, MEDICAL_TRIAL_REAGENT_ID, contract.linked_trial_id) >= MEDICAL_SIDE_SAMPLE_AMOUNT)
						valid = TRUE
						break
			if(MEDICAL_SIDE_AUTOPSY)
				for(var/mob/living/carbon/human/corpse in all_contents)
					if(SScontracts.subject_identity(corpse)?.id == contract.target_ref && medical_trial_corpse_irrecoverable(corpse))
						valid = TRUE
						break
		if(valid)
			manifest.submitted = contract.complete_action(contract.owner_account_number, "Validated outbound shipment [shipment.name]")
	return TRUE

#undef MEDICAL_SIDE_COVERUP
#undef MEDICAL_SIDE_ADVOCATE
#undef MEDICAL_SIDE_ESPIONAGE
#undef MEDICAL_SIDE_AUTOPSY
#undef MEDICAL_SIDE_SAMPLE_AMOUNT
