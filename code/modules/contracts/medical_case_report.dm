/datum/contract_definition/medical_rare_case
	id = "medical_rare_case_report"
	title = "Rare Clinical Case Report"
	description = "VeyMed's clinical registry requests a consented longitudinal record of an uncommon condition, its treatment, and the observed outcome."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_MEDICAL
	issuer_name = CONTRACT_FAX_CASE_REGISTRY
	issuer_faction = REPUTATION_FACTION_VEYMED
	reward = 1100
	offer_duration = MEDICAL_TRIAL_OFFER_DURATION
	max_simultaneous = 32
	contract_type = /datum/contract/medical_case_report

/datum/contract_definition/medical_rare_case/is_available(list/context)
	var/mob/living/carbon/human/subject = SScontracts.resolve_subject(context?["target_ref"])
	if(!istype(subject) || subject.stat == DEAD || !subject.mind?.assigned_role)
		return FALSE
	for(var/datum/affliction/condition as anything in subject.get_afflictions())
		if(condition.type == context["condition_type"] && medical_rare_case_condition(condition))
			return TRUE
	return FALSE

/datum/contract_definition/medical_rare_case/offer_remains_available(datum/contract/contract)
	return is_available(contract.offer_context)

/datum/contract_definition/medical_rare_case/active_remains_possible(datum/contract/contract)
	var/datum/contract/medical_case_report/report = contract
	return istype(report) && (report.consent_time || is_available(report.offer_context))

/datum/contract_definition/medical_rare_case/configure_contract(datum/contract/contract, list/context)
	var/datum/contract/medical_case_report/report = contract
	report.department = DEPARTMENT_MEDICAL
	report.station_share = 0.2
	report.department_share = 0.65
	report.contributor_share = 0.15
	report.station_reputation_reward = 8
	report.department_reputation_reward = 20
	report.personal_reputation_reward = 8
	report.initialize_case(context)

/datum/contract/medical_case_report
	var/target_ref
	var/target_name
	var/target_condition_type
	var/target_condition_name
	var/consent_time = 0
	var/obj/item/paper/consent_record
	var/consent_evidence_id
	var/datum/contract_requirement/event_count/evidence_requirement

/datum/contract/medical_case_report/Destroy()
	consent_record = null
	evidence_requirement = null
	return ..()

/datum/contract/medical_case_report/proc/initialize_case(list/context)
	target_ref = context?["target_ref"]
	target_name = context?["target_name"]
	target_condition_type = context?["condition_type"]
	target_condition_name = context?["condition_name"]
	deadline_duration = 35 MINUTES
	title = "Rare Case: [target_condition_name]"
	description = "The registry has identified a clinically uncommon presentation of [target_condition_name]. With [target_name]'s consent, submit a baseline body scan, treat the condition, wait at least one minute, submit a follow-up scan demonstrating at least 50% improvement, and include the completed case narrative."
	evidence_requirement = new(CONTRACT_EVENT_RARE_CASE_ACCEPTED, 1, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_CONTRACT)
	evidence_requirement.name = "Authenticated longitudinal case packet"
	evidence_requirement.description = "Fax the signed consent, completed case narrative, and genuine baseline/follow-up body-scanner reports to [CONTRACT_FAX_CASE_REGISTRY]."
	add_requirement(evidence_requirement)

/datum/contract/medical_case_report/proc/target_subject() as /mob/living/carbon/human
	var/mob/living/carbon/human/subject = SScontracts.resolve_subject(target_ref)
	return istype(subject) ? subject : null

/datum/contract/medical_case_report/proc/target_condition() as /datum/affliction
	var/mob/living/carbon/human/subject = target_subject()
	for(var/datum/affliction/condition as anything in subject?.get_afflictions())
		if(condition.type == target_condition_type)
			return condition

/datum/contract/medical_case_report/proc/print_case_forms(turf/location, issuer_account)
	if(state != CONTRACT_ACTIVE || !location)
		return FALSE
	var/consent_info = consent_time ? "<h2>VeyMed Certified Replacement Consent</h2><b>Patient:</b> [target_name]<br><b>Observed condition:</b> [target_condition_name]<br><b>Status:</b> Consent previously registered with the case registry." : "<h2>VeyMed Clinical Case Registry Consent</h2><b>Patient:</b> [target_name]<br><b>Observed condition:</b> [target_condition_name]<br><br>The signatory authorizes transmission of relevant conditions, treatment history, body-scanner findings, and outcome observations for this case report.<br><br><b>Patient signature:</b> <span class=\"paper_field\"></span>"
	var/obj/item/paper/consent = create_contract_document(location, "case registry consent - [target_name]", consent_info, id, CONTRACT_DOCUMENT_RARE_CASE_CONSENT, CONTRACT_FAX_CASE_REGISTRY, list("issuer_account" = issuer_account, "subject_ref" = target_ref, "subject_id" = target_ref, "signed" = !!consent_time, "signature_time" = consent_time))
	if(consent_time)
		var/datum/component/contract_document/consent_document = consent.GetComponent(/datum/component/contract_document)
		SScontracts.bind_evidence_subject(consent_document.evidence_id, target_ref)
		audit(CONTRACT_AUDIT_RECOVERY, "Issued certified replacement case forms for [target_name].")
	var/report_info = "<h2>Rare Clinical Case Narrative</h2><b>Patient:</b> [target_name]<br><b>Condition:</b> [target_condition_name]<br><br><b>Treatment performed:</b> <span class=\"paper_field\"></span><br><br><b>Clinical outcome and complications:</b> <span class=\"paper_field\"></span>"
	create_contract_document(location, "case narrative - [target_condition_name]", report_info, id, CONTRACT_DOCUMENT_RARE_CASE_REPORT, CONTRACT_FAX_CASE_REGISTRY, list("initial_info" = report_info, "subject_id" = target_ref))
	return TRUE

/datum/contract/medical_case_report/proc/register_consent(obj/item/paper/paper, mob/living/carbon/human/subject)
	if(state != CONTRACT_ACTIVE || consent_time || SScontracts.subject_identity(subject)?.id != target_ref || !target_condition())
		return FALSE
	consent_time = world.time
	consent_record = paper
	return TRUE

/datum/contract/medical_case_report/proc/print_consent_revocation(turf/location, issuer_account)
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)) || !location || !consent_time)
		return FALSE
	var/document_info = "<h2>Withdrawal from Clinical Case Registry</h2><b>Patient:</b> [target_name]<br><b>Case:</b> [target_condition_name]<br><br>The signatory withdraws authorization for further collection and transmission of this case. Information already received by the registry cannot be recalled.<br><br><b>Patient signature:</b> <span class=\"paper_field\"></span>"
	create_contract_document(location, "case registry consent withdrawal - [target_name]", document_info, id, CONTRACT_DOCUMENT_CONSENT_REVOCATION, CONTRACT_FAX_CASE_REGISTRY, list(
		"issuer_account" = issuer_account,
		"subject_id" = target_ref,
		"subject_name" = target_name,
	))
	return TRUE

/datum/contract/medical_case_report/proc/revoke_consent(subject_id)
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)) || subject_id != target_ref || !consent_time)
		return FALSE
	SScontracts.void_evidence(consent_evidence_id, "The patient withdrew from the case registry before submission.")
	audit(CONTRACT_AUDIT_PROGRESS, "[target_name] withdrew consent; the unsubmitted case report was cancelled without penalty.")
	return cancel("The patient withdrew consent before the clinical record was submitted.")

/datum/component/contract_document/proc/register_rare_case_signature(obj/item/paper/paper, mob/living/carbon/human/subject)
	var/datum/contract/medical_case_report/report = SScontracts.contracts_by_id[contract_id]
	if(payload["signed"] || !istype(subject) || !istype(report) || !report.register_consent(paper, subject))
		return FALSE
	payload["signed"] = TRUE
	report.consent_evidence_id = evidence_id
	SScontracts.bind_evidence_subject(evidence_id, report.target_ref)
	payload["signature_time"] = world.time
	paper.name = "signed case registry consent - [subject.real_name]"
	paper.info += "<br><b>Status:</b> Consent registered.<br><b>Filing instruction:</b> Bundle this form with the completed case narrative and longitudinal body scans, then fax it to [CONTRACT_FAX_CASE_REGISTRY]."
	paper.updateinfolinks()
	to_chat(subject, span_notice("Your consent to the VeyMed clinical case report is registered."))
	emit_contract_event(CONTRACT_EVENT_DOCUMENT_SIGNED, list(
		"contract_id" = contract_id,
		"subject_id" = report.target_ref,
		"subject_name" = subject.real_name,
		"document_kind" = document_kind,
		"destination" = destination,
		"evidence_ids" = list(evidence_id),
	), "document-signed:[evidence_id]", paper, subject, subject)
	return TRUE

/datum/component/contract_document/proc/register_rare_case_narrative_field(field_id)
	if(!isnum(field_id) || field_id < 1)
		return FALSE
	LAZYINITLIST(payload["completed_fields"])
	payload["completed_fields"] |= "[field_id]"
	return TRUE

/datum/contract/medical_case_report/proc/submit_case(list/baseline, list/followup, contributor_account)
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)) || evidence_requirement.state != CONTRACT_REQUIREMENT_PENDING || !consent_time)
		return FALSE
	var/baseline_severity = medical_snapshot_condition_severity(baseline?["snapshot"], target_condition_type)
	var/followup_severity = medical_snapshot_condition_severity(followup?["snapshot"], target_condition_type)
	if(!isnum(baseline_severity) || baseline_severity < MEDICAL_RARE_CASE_MINIMUM_SEVERITY)
		return FALSE
	if(followup["scan_time"] < baseline["scan_time"] + MEDICAL_TRIAL_OBSERVATION_TIME)
		return FALSE
	if(isnum(followup_severity) && followup_severity > baseline_severity * MEDICAL_RARE_CASE_IMPROVEMENT)
		return FALSE
	var/mob/living/carbon/human/subject = target_subject()
	record_contribution(medical_trial_account_for_mob(subject)?.account_number, 1, "Consented to the longitudinal case report", target_name)
	record_contribution(baseline["operator_account"], 1, "Produced the authenticated baseline scan")
	record_contribution(followup["operator_account"], 1, "Produced the authenticated follow-up scan")
	record_contribution(contributor_account, 2, "Completed and filed the rare-case packet")
	return !!emit_contract_event(CONTRACT_EVENT_RARE_CASE_ACCEPTED, list(
		"contract_id" = id,
		"subject_id" = target_ref,
		"subject_name" = target_name,
		"contributor_account" = contributor_account,
		"department" = DEPARTMENT_MEDICAL,
		"detail" = "The registry authenticated the longitudinal record and treatment narrative.",
	), "rare-case:[id]")

/datum/contract/medical_case_report/ui_details(mob/living/user)
	return list(
		"kind" = "medical_case_report",
		"patient" = target_name,
		"condition" = target_condition_name,
		"consented" = !!consent_time,
	)

/proc/medical_rare_case_types()
	var/static/list/types = list(
		/datum/affliction/subdural_hematoma,
		/datum/affliction/pneumothorax,
		/datum/affliction/compartment_syndrome,
		/datum/affliction/tissue_necrosis,
		/datum/affliction/septic_shock,
		/datum/affliction/chronic_radiation,
		/datum/affliction/ischemic_vision_loss,
		/datum/affliction/genetic_damage,
	)
	return types

/proc/medical_rare_case_condition(datum/affliction/condition)
	return condition && (condition.type in medical_rare_case_types()) && condition.severity >= MEDICAL_RARE_CASE_MINIMUM_SEVERITY

/proc/medical_snapshot_condition_severity(list/snapshot, condition_type)
	for(var/list/entry as anything in snapshot?["conditions"])
		if(entry["type"] == condition_type)
			return entry["severity"]
	return null

/proc/process_rare_case_evidence_packet(obj/item/paper_bundle/packet, sender_account, mob/living/sender)
	var/datum/component/contract_document/consent_document
	var/obj/item/paper/narrative
	var/datum/component/contract_document/narrative_document
	var/list/scans = list()
	for(var/obj/item/paper/page in packet.pages)
		var/datum/component/contract_document/document = page.GetComponent(/datum/component/contract_document)
		if(document?.document_kind == CONTRACT_DOCUMENT_RARE_CASE_CONSENT)
			if(consent_document)
				to_chat(sender, span_warning("The case registry rejects the packet: submit exactly one consent form."))
				return FALSE
			consent_document = document
		else if(document?.document_kind == CONTRACT_DOCUMENT_RARE_CASE_REPORT)
			if(narrative_document)
				to_chat(sender, span_warning("The case registry rejects the packet: submit exactly one case narrative."))
				return FALSE
			narrative = page
			narrative_document = document
		var/list/scan_evidence = SScontracts.authenticated_scan_payload(page)
		if(scan_evidence)
			scans += list(scan_evidence)
	if(!consent_document?.payload["signed"] || !narrative_document || consent_document.submitted || narrative_document.submitted)
		to_chat(sender, span_warning("The case registry rejects the packet: signed consent and one unsubmitted case narrative are required."))
		return FALSE
	if(consent_document.contract_id != narrative_document.contract_id || narrative.info == narrative_document.payload["initial_info"] || length(narrative_document.payload["completed_fields"]) < 2)
		to_chat(sender, span_warning("The case registry rejects the packet: the treatment and outcome narrative is incomplete."))
		return FALSE
	var/datum/contract/medical_case_report/report = SScontracts.contracts_by_id[consent_document.contract_id]
	if(!istype(report) || !(report.state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)) || report.target_ref != consent_document.payload["subject_id"])
		to_chat(sender, span_warning("The case registry cannot authenticate this packet against an active report."))
		return FALSE
	var/list/baseline
	var/list/followup
	for(var/list/evidence as anything in scans)
		if(evidence["subject_id"] != report.target_ref || evidence["scan_time"] < report.consent_time || evidence["scan_time"] > world.time)
			continue
		var/severity = medical_snapshot_condition_severity(evidence["snapshot"], report.target_condition_type)
		if(isnum(severity) && severity >= MEDICAL_RARE_CASE_MINIMUM_SEVERITY)
			if(!baseline || evidence["scan_time"] < baseline["scan_time"])
				baseline = evidence
	if(baseline)
		var/baseline_severity = medical_snapshot_condition_severity(baseline["snapshot"], report.target_condition_type)
		for(var/list/evidence as anything in scans)
			if(evidence["subject_id"] != report.target_ref || evidence["scan_time"] < baseline["scan_time"] + MEDICAL_TRIAL_OBSERVATION_TIME)
				continue
			var/severity = medical_snapshot_condition_severity(evidence["snapshot"], report.target_condition_type)
			if(isnum(severity) && severity > baseline_severity * MEDICAL_RARE_CASE_IMPROVEMENT)
				continue
			if(!followup || evidence["scan_time"] < followup["scan_time"])
				followup = evidence
	var/list/evidence_ids = list(consent_document.evidence_id, narrative_document.evidence_id, baseline?["evidence_id"], followup?["evidence_id"])
	if(!baseline || !followup || !SScontracts.evidence_available(evidence_ids) || !report.submit_case(baseline, followup, sender_account) || !SScontracts.consume_evidence(evidence_ids, report.id))
		to_chat(sender, span_warning("The case registry rejects the packet: it requires a qualifying baseline and a follow-up at least one minute later showing at least 50% improvement."))
		return FALSE
	consent_document.submitted = TRUE
	narrative_document.submitted = TRUE
	report.audit(CONTRACT_AUDIT_EVIDENCE, "Consumed longitudinal case evidence [english_list(evidence_ids)].")
	return TRUE

/datum/controller/subsystem/contracts/proc/consider_rare_medical_case(mob/living/carbon/human/subject)
	if(!subject || subject.stat == DEAD || !subject.mind?.assigned_role)
		withdraw_rare_case_offers(subject)
		return
	var/list/qualifying_types = list()
	var/subject_id = subject_identity(subject)?.id
	for(var/datum/affliction/condition as anything in subject.get_afflictions())
		if(medical_rare_case_condition(condition))
			qualifying_types |= condition.type
	for(var/datum/contract/medical_case_report/report in offered_contracts.Copy())
		if(report.target_ref == subject_id && !(report.target_condition_type in qualifying_types))
			report.withdraw("The qualifying condition resolved before acceptance.")
	for(var/datum/contract/medical_case_report/report in active_contracts.Copy())
		if(report.target_ref == subject_id && !report.consent_time && !(report.target_condition_type in qualifying_types))
			report.withdraw("The qualifying presentation resolved before consent; no penalty was assessed.")
	for(var/datum/affliction/condition as anything in subject.get_afflictions())
		if(!medical_rare_case_condition(condition) || rare_case_contract_exists(subject_id, condition.type))
			continue
		queue_offer("medical_rare_case_report", list(
			"target_ref" = subject_id,
			"target_name" = subject.real_name,
			"condition_type" = condition.type,
			"condition_name" = condition.name,
		), "A qualifying rare clinical presentation was detected", "medical_rare_case_report:[subject_id]:[condition.type]", 90)

/datum/controller/subsystem/contracts/proc/rare_case_contract_exists(subject_ref, condition_type)
	for(var/datum/contract/medical_case_report/report in offered_contracts)
		if(report.target_ref == subject_ref && report.target_condition_type == condition_type)
			return TRUE
	for(var/datum/contract/medical_case_report/report in active_contracts)
		if(report.target_ref == subject_ref && report.target_condition_type == condition_type)
			return TRUE
	if(find_candidate("medical_rare_case_report:[subject_ref]:[condition_type]"))
		return TRUE
	return FALSE

/datum/controller/subsystem/contracts/proc/withdraw_rare_case_offers(mob/living/carbon/human/subject)
	if(!subject)
		return
	for(var/datum/contract/medical_case_report/report in offered_contracts.Copy())
		if(report.target_ref == subject_identity(subject)?.id)
			report.withdraw("The patient is no longer available for this report.")
	var/subject_ref = subject_identity(subject)?.id
	for(var/datum/contract_offer_candidate/candidate in offer_candidates.Copy())
		if(candidate.definition_id == "medical_rare_case_report" && candidate.context["target_ref"] == subject_ref)
			withdraw_candidate(candidate, "The patient is no longer available for this report.")
