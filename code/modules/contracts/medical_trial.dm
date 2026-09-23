/datum/contract_definition/experimental_medication
	id = "experimental_medication_study"
	title = "Experimental Medication Study"
	description = "VeyMed Clinical Development offers remuneration for a controlled study of a coded medication, comprising three signed subject records, one-minute post-exposure observations, and a final interpretation of therapeutic and adverse effects."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_MEDICAL
	issuer_name = "VeyMed Clinical Development"
	issuer_faction = REPUTATION_FACTION_VEYMED
	reward = 1800
	expected_duration = 90 MINUTES
	initial_offers = 1
	offer_duration = MEDICAL_TRIAL_OFFER_DURATION
	offer_kind = CONTRACT_OFFER_STANDING
	auto_replace = TRUE
	max_simultaneous = 3
	contract_type = /datum/contract/medical_trial

/datum/contract_definition/experimental_medication/is_available(list/context)
	return !context?["conditional_offer"] || !!context["eligibility_confirmed"]

/datum/contract_definition/experimental_medication/offer_remains_available(datum/contract/contract)
	var/datum/contract/medical_trial/trial = contract
	if(!istype(trial) || !trial.conditional_offer)
		return TRUE
	return medical_trial_protocol_is_viable(trial.profile.cohort, trial.profile.target_metric, medical_trial_station_availability())

/datum/contract_definition/experimental_medication/active_remains_possible(datum/contract/contract)
	var/datum/contract/medical_trial/trial = contract
	if(!istype(trial) || !trial.conditional_offer || length(trial.participants))
		return TRUE
	return offer_remains_available(trial)

/datum/contract_definition/experimental_medication/configure_contract(datum/contract/contract, list/context)
	contract.department = DEPARTMENT_MEDICAL
	contract.station_share = 0.2
	contract.department_share = 0.65
	contract.contributor_share = 0.15
	contract.station_reputation_reward = 15
	contract.department_reputation_reward = 40
	contract.personal_reputation_reward = 10
	var/datum/contract/medical_trial/trial = contract
	trial.conditional_offer = !!context?["conditional_offer"]
	trial.initialize_trial(context?["cohort"], context?["target_metric"])
	apply_contract_standing_terms(contract)
	configure_medical_trial_negotiations(contract)

/proc/configure_medical_trial_negotiations(datum/contract/contract)
	var/protocol_shift = max(100, round(contract.reward * 0.1))
	var/datum/contract_negotiation_clause/protocol = new("patient_protocol", "Patient records", "Choose what VeyMed receives and who controls review.")
	protocol.add_option(make_contract_clause_option("patient", "Patient-led · anonymous", "Require filed consent and withhold patient identities.", -round(protocol_shift * 0.25), -round(protocol_shift * 0.5), round(protocol_shift * 0.75), 4, 4, 4, 10 MINUTES, list("oversight" = "independent", "identity" = "anonymous")))
	protocol.add_option(make_contract_clause_option("coded", "Medical review · coded", "Medical reviews the study; VeyMed receives coded records.", 0, 0, 0, 1, 1, 1, 0, list("oversight" = "internal", "identity" = "coded")), TRUE)
	protocol.add_option(make_contract_clause_option("sponsor", "Sponsor review · identified", "VeyMed directs review and receives identified records.", round(protocol_shift * 0.25), round(protocol_shift * 0.75), 0, -4, -4, -2, -10 MINUTES, list("oversight" = "sponsor", "identity" = "identified")))
	contract.add_negotiation_clause(protocol)
	add_contract_payout_negotiation(contract)

/datum/contract/medical_trial
	var/datum/medical_trial_profile/profile
	var/list/participants
	var/datum/contract_requirement/event_count/observation_requirement
	var/datum/contract_requirement/event_count/analysis_requirement
	var/analysis_attempted = FALSE
	var/analysis_corrections = 0
	var/conditional_offer = FALSE
	var/resupplies_used = 0

/datum/contract/medical_trial/Destroy()
	QDEL_NULL(profile)
	for(var/key in participants)
		var/datum/medical_trial_participant/participant = participants[key]
		var/mob/living/subject = participant.current_subject()
		if(subject)
			UnregisterSignal(subject, COMSIG_MOB_DEATH)
		qdel(participant)
	participants = null
	observation_requirement = null
	analysis_requirement = null
	return ..()

/datum/contract/medical_trial/proc/initialize_trial(cohort, target_metric)
	profile = new(cohort, target_metric)
	participants = list()
	deadline_duration = 90 MINUTES
	title = "Experimental Medication Study: [profile.code_name]"
	description = "VeyMed requests a [profile.cohort] study of [profile.code_name], provisionally indicated for [profile.target_metric] conditions. [profile.protocol_instructions()] For each of three subjects, fax one packet containing the signed consent form, a pre-exposure body-scanner printout, and a body-scanner printout taken at least one minute after exposure."
	observation_requirement = new(CONTRACT_EVENT_MEDICAL_OBSERVATION_ACCEPTED, 3, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_CONTRACT)
	observation_requirement.name = "Valid clinical observations"
	observation_requirement.description = "VeyMed requires three evidence packets. Each must contain the subject's signed consent form plus genuine pre-exposure and one-minute post-exposure body-scanner printouts."
	observation_requirement.unique_field = "subject_id"
	add_requirement(observation_requirement)
	analysis_requirement = new(CONTRACT_EVENT_MEDICAL_ANALYSIS_ACCEPTED, 1, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_CONTRACT)
	analysis_requirement.name = "Clinical interpretation"
	analysis_requirement.description = "Payment is contingent upon correct identification of the medication's therapeutic target and primary adverse effect."
	add_requirement(analysis_requirement)

/datum/contract/medical_trial/proc/mixed_cohort_complete()
	var/healthy = 0
	var/affected = 0
	for(var/key in participants)
		var/datum/medical_trial_participant/participant = participants[key]
		if(!participant.completed)
			continue
		if(participant.healthy_volunteer)
			healthy++
		else
			affected++
	return healthy >= 1 && affected >= 1

/datum/contract/medical_trial/on_accepted(mob/living/user, atom/source)
	var/turf/drop_location = get_turf(source ? source : user)
	if(!drop_location)
		return
	issue_trial_supplies(drop_location, 3, 30)
	medical_trial_offer_industrial_espionage(src)
	to_chat(user, span_notice("VeyMed transmits three coded medication bottles. Print clinical packets from the contract dashboard and fax completed paperwork to VeyMed."))

/datum/contract/medical_trial/proc/issue_trial_supplies(turf/location, count = 1, medication_volume = 10)
	if(!location || count <= 0 || medication_volume <= 0)
		return FALSE
	for(var/index in 1 to count)
		// Contract supplies deliberately use the ordinary chemistry container.
		// Provenance belongs to the reagent data, so decanting, mixing, sampling,
		// and Cargo export all continue through the same generic systems.
		var/obj/item/reagent_containers/glass/beaker/stopperedbottle/bottle = new(location)
		bottle.name = "[profile.code_name] trial bottle"
		bottle.desc = "A standard stoppered bottle bearing a VeyMed study label."
		bottle.reagents.add_reagent(MEDICAL_TRIAL_REAGENT_ID, medication_volume, medical_trial_contract_data(id))
		if(profile.cohort == MEDICAL_TRIAL_COHORT_PREVENTATIVE)
			var/obj/item/reagent_containers/glass/beaker/stopperedbottle/challenge = new(location)
			challenge.name = "[profile.code_name] controlled challenge"
			challenge.desc = "A standard stoppered bottle bearing a controlled-challenge label."
			challenge.reagents.add_reagent(MEDICAL_TRIAL_CHALLENGE_REAGENT_ID, 10, medical_trial_contract_data(id))
	return TRUE

/datum/contract/medical_trial/proc/request_resupply(turf/location)
	if(state != CONTRACT_ACTIVE || !location || resupplies_used >= MEDICAL_TRIAL_MAX_RESUPPLIES)
		return FALSE
	var/datum/money_account/medical_account = GLOB.department_accounts[DEPARTMENT_MEDICAL]
	if(!medical_account?.debit(MEDICAL_TRIAL_RESUPPLY_COST, "VeyMed Clinical Development", "Replacement dose for [id]", "Contracts"))
		return FALSE
	resupplies_used++
	issue_trial_supplies(location)
	audit(CONTRACT_AUDIT_PROGRESS, "Medical purchased replacement supply [resupplies_used]/[MEDICAL_TRIAL_MAX_RESUPPLIES].")
	return TRUE

/datum/contract/medical_trial/proc/enroll(mob/living/carbon/human/subject, clinician_account)
	var/datum/contract_subject_identity/identity = SScontracts.subject_identity(subject)
	if(!identity || state != CONTRACT_ACTIVE || participants[identity.id])
		return FALSE
	var/list/baseline = medical_trial_snapshot(subject)
	var/burden = medical_trial_condition_burden(subject)
	var/is_healthy = burden < MEDICAL_TRIAL_MINIMUM_BASELINE
	var/target_burden = medical_trial_condition_burden(subject, medical_trial_target_types(profile.target_metric))
	var/has_qualifying_target = target_burden >= MEDICAL_TRIAL_MINIMUM_BASELINE
	if(!profile.accepts_subject(is_healthy, has_qualifying_target))
		return FALSE
	if(profile.cohort == MEDICAL_TRIAL_COHORT_MIXED)
		var/matching_class = 0
		for(var/key in participants)
			var/datum/medical_trial_participant/existing = participants[key]
			if(existing.healthy_volunteer == is_healthy)
				matching_class++
		if(matching_class >= 2)
			return FALSE
	var/datum/medical_trial_participant/participant = new(identity.id, baseline, is_healthy, clinician_account)
	participants[identity.id] = participant
	RegisterSignal(subject, COMSIG_MOB_DEATH, PROC_REF(on_participant_death))
	medical_trial_offer_patient_advocate(src, participant)
	audit(CONTRACT_AUDIT_PROGRESS, "[subject.real_name] consented and baseline telemetry was recorded.")
	return TRUE

/datum/contract/medical_trial/proc/on_participant_death(mob/living/carbon/human/subject, gibbed)
	SIGNAL_HANDLER
	var/datum/contract_subject_identity/identity = SScontracts.subject_identity(subject)
	var/datum/medical_trial_participant/participant = participants?[identity?.id]
	if(!participant || participant.corpse_contract_offered || gibbed)
		return
	participant.corpse_contract_offered = !!medical_trial_offer_corpse_autopsy(src, participant)

/datum/contract/medical_trial/proc/record_exposure(mob/living/carbon/human/subject, amount)
	var/datum/contract_subject_identity/identity = SScontracts.subject_identity(subject)
	var/datum/medical_trial_participant/participant = participants?[identity?.id]
	if(!participant || participant.completed || !isnum(amount) || amount <= 0)
		return
	participant.dose += amount
	subject.record_clinical_exposure(id, profile.code_name, "coded trial medication", amount)
	if(!participant.exposure_time)
		participant.exposure_time = world.time

/datum/contract/medical_trial/proc/record_challenge(mob/living/carbon/human/subject, amount)
	var/datum/contract_subject_identity/identity = SScontracts.subject_identity(subject)
	var/datum/medical_trial_participant/participant = participants?[identity?.id]
	if(!participant || participant.completed || participant.dose < MEDICAL_TRIAL_MINIMUM_DOSE || amount <= 0)
		return FALSE
	participant.challenge_dose += amount
	subject.record_clinical_exposure(id, profile.code_name, "coded controlled challenge", amount)
	return TRUE

/datum/contract/medical_trial/proc/submit_subject_evidence(subject_id, list/baseline_evidence, list/followup_evidence, contributor_account)
	var/datum/medical_trial_participant/participant = participants?[subject_id]
	if(!participant || participant.faxed || participant.dose < MEDICAL_TRIAL_MINIMUM_DOSE || !participant.exposure_time)
		return FALSE
	if(profile.cohort == MEDICAL_TRIAL_COHORT_PREVENTATIVE && participant.challenge_dose < MEDICAL_TRIAL_MINIMUM_DOSE)
		return FALSE
	if(negotiated_effect("oversight", "internal") == "independent" && participant.consent_resolution != "filed")
		return FALSE
	if(!islist(baseline_evidence) || !islist(followup_evidence))
		return FALSE
	if(baseline_evidence["subject_id"] != subject_id || followup_evidence["subject_id"] != subject_id)
		return FALSE
	if(baseline_evidence["scan_time"] > participant.exposure_time)
		return FALSE
	if(followup_evidence["scan_time"] < participant.exposure_time + MEDICAL_TRIAL_OBSERVATION_TIME)
		return FALSE
	var/list/markers = followup_evidence["trial_markers"]
	if(!islist(markers) || (markers[id] || 0) <= 0)
		return FALSE
	participant.baseline_metrics = baseline_evidence["snapshot"]
	participant.final_metrics = followup_evidence["snapshot"]
	participant.completed = TRUE
	participant.faxed = TRUE
	var/mob/living/current_subject = participant.current_subject()
	var/identity_term = negotiated_effect("identity", "coded")
	var/sponsor_subject = identity_term == "identified" ? (current_subject?.real_name || subject_id) : (identity_term == "anonymous" ? "anonymous participant" : "coded participant [copytext(md5("[id]:[subject_id]"), 1, 7)]")
	var/detail = "Authenticated clinical packet for [sponsor_subject]"
	record_contribution(participant.subject_account, 1, "Consented study participation", current_subject?.real_name)
	record_contribution(participant.clinician_account, 2, "Issued and registered the participant's enrollment record")
	record_contribution(baseline_evidence["operator_account"], 1, "Produced the authenticated baseline scan")
	record_contribution(followup_evidence["operator_account"], 1, "Produced the authenticated follow-up scan")
	record_contribution(contributor_account, 1, "Filed the completed clinical packet")
	return !!emit_contract_event(CONTRACT_EVENT_MEDICAL_OBSERVATION_ACCEPTED, list(
		"contract_id" = id,
		"subject_id" = subject_id,
		"subject_name" = sponsor_subject,
		"identity_term" = identity_term,
		"contributor_account" = contributor_account,
		"department" = DEPARTMENT_MEDICAL,
		"detail" = detail,
	), "medical-observation:[id]:[subject_id]", null, null, current_subject)

/datum/contract/medical_trial/ui_details(mob/living/user)
	var/list/subjects = list()
	for(var/key in participants)
		var/datum/medical_trial_participant/participant = participants[key]
		var/mob/living/carbon/human/current_subject = participant.current_subject()
		var/wait_remaining = participant.exposure_time ? max(0, participant.exposure_time + MEDICAL_TRIAL_OBSERVATION_TIME - world.time) : 0
		var/next_step = "Fax the accepted evidence packet."
		if(participant.faxed)
			next_step = "Evidence accepted."
		else if(!participant.exposure_time)
			next_step = "Print a baseline scan, then administer the coded medication."
		else if(wait_remaining > 0)
			next_step = "Wait [DisplayTimeText(wait_remaining, 1)] before printing the follow-up scan."
		else
			next_step = "Print the follow-up scan and fax it with this subject's consent and baseline scan."
		subjects.Add(list(list(
			"name" = current_subject?.real_name || "Unavailable subject",
			"subject_ref" = key,
			"cohort_class" = participant.healthy_volunteer ? "healthy control" : "affected patient",
			"status" = participant.consent_withdrawn ? "withdrawn; previously received evidence retained" : (participant.faxed ? "evidence packet accepted" : (participant.exposure_time ? "awaiting evidence packet" : "consent registered")),
			"next_step" = next_step,
			"marker_detected" = (current_subject?.medical_trial_marker_snapshot()?[id] || 0) > 0,
			"can_reissue" = !participant.faxed,
			"can_revoke" = !participant.consent_withdrawn,
		)))
	return list(
		"kind" = "medical_trial",
		"code_name" = profile.code_name,
		"cohort" = profile.cohort,
		"protocol" = profile.protocol_instructions(),
		"indication" = profile.target_metric,
		"adverse_choices" = medical_trial_adverse_choices(),
		"subjects" = subjects,
		"analysis_ready" = observation_requirement.state == CONTRACT_REQUIREMENT_COMPLETE && !analysis_attempted,
		"resupplies_remaining" = MEDICAL_TRIAL_MAX_RESUPPLIES - resupplies_used,
		"resupply_cost" = MEDICAL_TRIAL_RESUPPLY_COST,
	)

/datum/contract/medical_trial/proc/print_clinical_packet(turf/location, issuer_account)
	if(state != CONTRACT_ACTIVE || !location)
		return FALSE
	var/document_info = "<h2>VeyMed Clinical Consent Record</h2><b>Study:</b> [profile.code_name]<br><b>Cohort:</b> [profile.cohort]<br><b>Eligibility:</b> [profile.protocol_instructions()]<br><b>Filing office:</b> VeyMed Clinical Development<br><br>By signing below, the signatory voluntarily authorizes recording and transmission of relevant conditions, symptoms, organ state, medication exposure, and follow-up vital signs for this study. Bundle this signed consent with a body-scanner printout made before medication exposure and another made at least one minute afterward, then fax the complete packet to the filing office.<br><br><b>Subject signature:</b> <span class=\"paper_field\"></span>"
	create_contract_document(location, "VeyMed clinical consent and observation record", document_info, id, CONTRACT_DOCUMENT_CLINICAL_CASE, CONTRACT_FAX_VEYMED, list("issuer_account" = issuer_account))
	return TRUE

/datum/contract/medical_trial/proc/reissue_clinical_packet(turf/location, subject_id, issuer_account)
	var/datum/medical_trial_participant/participant = participants?[subject_id]
	if(state != CONTRACT_ACTIVE || !location || !participant || participant.faxed)
		return FALSE
	var/mob/living/carbon/human/subject = participant.current_subject()
	var/document_info = "<h2>VeyMed Replacement Clinical Record</h2><b>Study:</b> [profile.code_name]<br><b>Registered subject:</b> [subject?.real_name || subject_id]<br><b>Status:</b> Consent previously registered with VeyMed.<br><br>This certified replacement may be bundled with the subject's genuine baseline and follow-up body-scanner printouts and faxed to [CONTRACT_FAX_VEYMED]."
	var/obj/item/paper/document = create_contract_document(location, "replacement VeyMed observation record - [subject?.real_name || subject_id]", document_info, id, CONTRACT_DOCUMENT_CLINICAL_CASE, CONTRACT_FAX_VEYMED, list(
		"issuer_account" = issuer_account,
		"subject_id" = subject_id,
		"subject_ref" = subject_id,
		"subject_name" = subject?.real_name,
		"signature_time" = participant.consent_time,
		"replacement" = TRUE,
	))
	participant.consent_record = document
	audit(CONTRACT_AUDIT_RECOVERY, "Issued a certified replacement consent record for [subject?.real_name || subject_id].")
	return TRUE

/datum/contract/medical_trial/proc/print_consent_revocation(turf/location, subject_id, issuer_account)
	var/datum/medical_trial_participant/participant = participants?[subject_id]
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)) || !location || !participant || participant.consent_withdrawn)
		return FALSE
	var/mob/living/carbon/human/subject = participant.current_subject()
	var/document_info = "<h2>Withdrawal of Clinical Consent</h2><b>Study:</b> [profile.code_name]<br><b>Registered subject:</b> [subject?.real_name || subject_id]<br><br>The signatory withdraws authorization for further medication, observation, and transmission of unsubmitted clinical evidence. Records already received by VeyMed cannot be recalled.<br><br><b>Subject signature:</b> <span class=\"paper_field\"></span>"
	create_contract_document(location, "clinical consent withdrawal - [subject?.real_name || subject_id]", document_info, id, CONTRACT_DOCUMENT_CONSENT_REVOCATION, CONTRACT_FAX_VEYMED, list(
		"issuer_account" = issuer_account,
		"subject_id" = subject_id,
		"subject_name" = subject?.real_name,
	))
	return TRUE

/datum/contract/medical_trial/proc/revoke_consent(subject_id)
	var/datum/medical_trial_participant/participant = participants?[subject_id]
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)) || !participant || participant.consent_withdrawn)
		return FALSE
	participant.consent_withdrawn = TRUE
	if(participant.faxed)
		audit(CONTRACT_AUDIT_PROGRESS, "[participant.current_subject()?.real_name || subject_id] withdrew from further participation after evidence had already been received.")
		return TRUE
	var/mob/living/carbon/human/subject = participant.current_subject()
	if(subject)
		UnregisterSignal(subject, COMSIG_MOB_DEATH)
	SScontracts.void_evidence(participant.consent_evidence_id, "The subject withdrew consent before submission.")
	medical_trial_cancel_subject_contracts(id, subject_id)
	participants -= subject_id
	qdel(participant)
	audit(CONTRACT_AUDIT_PROGRESS, "[subject?.real_name || subject_id] withdrew consent; unsubmitted observations were discarded and the cohort slot reopened.")
	return TRUE

/datum/contract/medical_trial/proc/print_final_report(turf/location, adverse_metric)
	if(state != CONTRACT_ACTIVE || observation_requirement.state != CONTRACT_REQUIREMENT_COMPLETE || analysis_attempted || !location)
		return FALSE
	if(!(adverse_metric in medical_trial_adverse_choices()))
		return FALSE
	var/document_info = "<h2>Final Clinical Interpretation</h2><b>Study:</b> [profile.code_name]<br><b>Declared indication:</b> [profile.target_metric]<br><b>Primary adverse syndrome:</b> [adverse_metric]<br><b>Identity handling:</b> [negotiated_effect("identity", "coded")]<br><b>Review:</b> [negotiated_effect("oversight", "internal")]<br><br>VeyMed Clinical Development will adjudicate efficacy from the submitted scanner evidence and reported adverse syndrome."
	create_contract_document(location, "final clinical interpretation — [profile.code_name]", document_info, id, CONTRACT_DOCUMENT_FINAL_REPORT, CONTRACT_FAX_VEYMED, list("target_metric" = profile.target_metric, "adverse_metric" = adverse_metric))
	return TRUE

/datum/contract/medical_trial/proc/submit_analysis(target_metric, adverse_metric, contributor_account)
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)) || analysis_attempted || observation_requirement.state != CONTRACT_REQUIREMENT_COMPLETE)
		return FALSE
	if(profile.cohort == MEDICAL_TRIAL_COHORT_MIXED && !mixed_cohort_complete())
		return FALSE
	if(!(target_metric in medical_trial_target_choices()) || !(adverse_metric in medical_trial_adverse_choices()))
		return FALSE
	if(target_metric != profile.target_metric || adverse_metric != profile.adverse_metric)
		analysis_corrections++
		reward = max(0, round(reward * 0.9))
		audit(CONTRACT_AUDIT_PROGRESS, "VeyMed returned clinical interpretation [analysis_corrections] for correction; the final award was reduced by 10%.")
		return TRUE
	analysis_attempted = TRUE
	record_contribution(contributor_account, 2, "Submitted the correct final clinical interpretation")
	return !!emit_contract_event(CONTRACT_EVENT_MEDICAL_ANALYSIS_ACCEPTED, list(
		"contract_id" = id,
		"contributor_account" = contributor_account,
		"department" = DEPARTMENT_MEDICAL,
		"target_metric" = target_metric,
		"adverse_metric" = adverse_metric,
		"detail" = "Correct clinical interpretation submitted",
	), "medical-analysis:[id]")

/datum/medical_trial_profile
	var/code_name
	var/cohort
	var/target_metric
	var/adverse_metric
	var/therapeutic_strength
	var/adverse_strength

/datum/medical_trial_profile/New(requested_cohort, requested_target)
	. = ..()
	code_name = "VM-[rand(100, 999)]-[pick(GLOB.alphabet_upper)]"
	cohort = requested_cohort || pick(MEDICAL_TRIAL_COHORT_HEALTHY, MEDICAL_TRIAL_COHORT_PREVENTATIVE)
	target_metric = requested_target || pick(medical_trial_target_choices())
	var/list/adverse_choices = medical_trial_adverse_choices()
	adverse_choices -= target_metric
	adverse_metric = pick(adverse_choices)
	therapeutic_strength = rand(8, 16) / 10
	adverse_strength = adverse_metric == "none" ? 0 : rand(3, 10) / 10

/datum/medical_trial_profile/proc/accepts_subject(is_healthy, has_qualifying_target)
	switch(cohort)
		if(MEDICAL_TRIAL_COHORT_THERAPEUTIC)
			return has_qualifying_target
		if(MEDICAL_TRIAL_COHORT_HEALTHY, MEDICAL_TRIAL_COHORT_PREVENTATIVE)
			return is_healthy
		if(MEDICAL_TRIAL_COHORT_MIXED)
			return is_healthy || has_qualifying_target
	return FALSE

/datum/medical_trial_profile/proc/protocol_instructions()
	switch(cohort)
		if(MEDICAL_TRIAL_COHORT_THERAPEUTIC)
			return "Eligible cohort: patients bearing a registered [target_metric] condition of severity [MEDICAL_TRIAL_MINIMUM_BASELINE] or greater."
		if(MEDICAL_TRIAL_COHORT_HEALTHY)
			return "Safety cohort: volunteers bearing no registered condition of severity [MEDICAL_TRIAL_MINIMUM_BASELINE] or greater; therapeutic efficacy is outside this cohort's remit."
		if(MEDICAL_TRIAL_COHORT_MIXED)
			return "Eligible cohort: patients bearing a registered [target_metric] condition of severity [MEDICAL_TRIAL_MINIMUM_BASELINE] or greater and healthy controls, with at least one completed observation from each class."
		if(MEDICAL_TRIAL_COHORT_PREVENTATIVE)
			return "Eligible cohort: healthy volunteers. Study medication exposure must precede the separately coded controlled challenge."
	return "Follow the transmitted inclusion protocol."

/datum/medical_trial_participant
	var/subject_id
	var/list/baseline_metrics
	var/list/final_metrics
	var/healthy_volunteer = FALSE
	var/obj/item/paper/consent_record
	var/consent_resolution
	var/consent_evidence_id
	var/consent_withdrawn = FALSE
	var/clinician_account
	var/subject_account
	var/coverup_contract_offered = FALSE
	var/corpse_contract_offered = FALSE
	var/dose = 0
	var/challenge_dose = 0
	var/exposure_time = 0
	var/consent_time = 0
	var/completed = FALSE
	var/faxed = FALSE

/datum/medical_trial_participant/New(_subject_id, list/_baseline, _healthy_volunteer, _clinician_account)
	. = ..()
	subject_id = _subject_id
	baseline_metrics = _baseline.Copy()
	healthy_volunteer = _healthy_volunteer
	clinician_account = _clinician_account
	var/datum/contract_subject_identity/identity = SScontracts.subject_identities[subject_id]
	subject_account = identity?.account_number

/datum/medical_trial_participant/proc/current_subject() as /mob/living/carbon/human
	var/mob/living/carbon/human/subject = SScontracts.resolve_subject(subject_id)
	return istype(subject) ? subject : null

/datum/medical_trial_participant/Destroy()
	subject_id = null
	consent_record = null
	baseline_metrics = null
	final_metrics = null
	return ..()

/proc/medical_trial_target_choices()
	return list("trauma", "infection", "respiratory", "neurological", "organ failure")

/proc/medical_trial_qualifying_indications(list/candidates = GLOB.player_list, require_station_crew = TRUE)
	var/list/available = list()
	for(var/mob/living/carbon/human/subject in candidates)
		if(subject.stat == DEAD)
			continue
		if(require_station_crew && !subject.mind?.assigned_role)
			continue
		for(var/family in medical_trial_target_choices())
			if(medical_trial_condition_burden(subject, medical_trial_target_types(family)) >= MEDICAL_TRIAL_MINIMUM_BASELINE)
				available |= family
	return available

/proc/medical_trial_condition_family(datum/affliction/condition)
	for(var/family in medical_trial_target_choices())
		for(var/condition_type in medical_trial_target_types(family))
			if(istype(condition, condition_type))
				return family

/datum/affliction
	var/contract_eligibility_initialized = FALSE
	var/contract_eligibility_qualifying = FALSE
	var/contract_rare_eligibility_qualifying = FALSE

/// Does this affliction's severity describe a clinical outcome? Wounds,
/// lesions and injury load mirror physical integrity (autoheal, bandaging,
/// fighting), so they feed neither trial eligibility nor outcome telemetry.
/proc/affliction_reports_clinical_outcomes(datum/affliction/A)
	return !istype(A, /datum/affliction/wound) && !istype(A, /datum/affliction/lesion) && !istype(A, /datum/affliction/load)

/// COMSIG_AFFLICTION_SEVERITY_CHANGED: republish trial eligibility and emit
/// the measured treatment outcome when a condition improves.
/datum/controller/subsystem/contracts/proc/on_affliction_severity_changed(mob/living/carbon/human/patient, datum/affliction/A, old_severity)
	SIGNAL_HANDLER
	if(!istype(patient) || !affliction_reports_clinical_outcomes(A))
		return
	A.update_contract_eligibility()
	var/improvement = old_severity - A.severity
	if(improvement < 1 || old_severity < MEDICAL_TRIAL_MINIMUM_BASELINE)
		return
	var/datum/contract_subject_identity/identity = subject_identity(patient)
	if(!identity)
		return
	emit_contract_event(CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, list(
		"department" = DEPARTMENT_MEDICAL,
		"subject_id" = identity.id,
		"subject_name" = patient.real_name,
		"condition_type" = A.type,
		"condition_name" = A.name,
		"metrics" = list(
			"improvement" = improvement,
			"initial_severity" = old_severity,
			"final_severity" = A.severity,
		),
		"detail" = "[patient.real_name]'s [A.name] improved by [round(improvement, 0.1)] severity.",
	), "medical-treatment:[REF(A)]:[world.time]:[A.severity]", patient, null, patient)

/// COMSIG_BODY_AFFLICTIONS_CHANGED: an affliction can join or leave a body
/// without a severity change (an organ carrying afflictions is reattached, an
/// affliction is cured or cleared outright). Keep eligibility in step.
/datum/controller/subsystem/contracts/proc/on_body_afflictions_changed(mob/living/carbon/human/patient, datum/affliction/A, added)
	SIGNAL_HANDLER
	if(!affliction_reports_clinical_outcomes(A))
		return
	if(added)
		A.update_contract_eligibility()
		return
	if(A.contract_eligibility_qualifying || A.contract_rare_eligibility_qualifying)
		A.contract_eligibility_qualifying = FALSE
		A.contract_rare_eligibility_qualifying = FALSE
		SEND_SIGNAL(patient, COMSIG_MOB_MEDICAL_ISSUES_CHANGED)

/datum/affliction/proc/update_contract_eligibility()
	var/family = medical_trial_condition_family(src)
	var/qualifying = !!family && severity >= MEDICAL_TRIAL_MINIMUM_BASELINE
	var/rare_qualifying = medical_rare_case_condition(src)
	if(contract_eligibility_initialized && qualifying == contract_eligibility_qualifying && rare_qualifying == contract_rare_eligibility_qualifying)
		return
	contract_eligibility_initialized = TRUE
	contract_eligibility_qualifying = qualifying
	contract_rare_eligibility_qualifying = rare_qualifying
	if(owner)
		SEND_SIGNAL(owner, COMSIG_MOB_MEDICAL_ISSUES_CHANGED)

/mob/living/carbon/human
	var/list/contract_medical_indications

/mob/living/carbon/human/proc/refresh_contract_medical_eligibility()
	var/list/current = medical_trial_qualifying_indications(list(src), FALSE)
	var/changed = length(current) != length(contract_medical_indications)
	if(!changed)
		for(var/family in current)
			if(!(family in contract_medical_indications))
				changed = TRUE
				break
	if(!changed)
		return FALSE
	contract_medical_indications = current
	SScontracts?.reconcile_medical_trial_offers()
	return TRUE

/proc/medical_trial_station_availability()
	var/list/indication_counts = list()
	var/healthy_count = 0
	for(var/mob/living/carbon/human/subject in GLOB.player_list)
		if(subject.stat == DEAD || !subject.mind?.assigned_role)
			continue
		for(var/family in subject.contract_medical_indications)
			indication_counts[family] = (indication_counts[family] || 0) + 1
		if(medical_trial_condition_burden(subject) < MEDICAL_TRIAL_MINIMUM_BASELINE)
			healthy_count++
	return list(
		"indication_counts" = indication_counts,
		"healthy_count" = healthy_count,
	)

/proc/medical_trial_protocol_is_viable(cohort, target_metric, list/availability)
	var/list/counts = availability?["indication_counts"]
	var/affected = counts?[target_metric] || 0
	var/healthy = availability?["healthy_count"] || 0
	if(cohort == MEDICAL_TRIAL_COHORT_THERAPEUTIC)
		return affected >= 3
	if(cohort == MEDICAL_TRIAL_COHORT_MIXED)
		return affected >= 1 && healthy >= 1 && affected + healthy >= 3
	return TRUE

/proc/medical_trial_viable_conditional_protocols(list/availability)
	var/list/result = list()
	var/list/counts = availability?["indication_counts"]
	for(var/family in counts)
		if(medical_trial_protocol_is_viable(MEDICAL_TRIAL_COHORT_MIXED, family, availability))
			result += list(list("cohort" = MEDICAL_TRIAL_COHORT_MIXED, "target_metric" = family))
		if(medical_trial_protocol_is_viable(MEDICAL_TRIAL_COHORT_THERAPEUTIC, family, availability))
			result += list(list("cohort" = MEDICAL_TRIAL_COHORT_THERAPEUTIC, "target_metric" = family))
	return result

/proc/medical_trial_adverse_choices()
	return list("none", "respiratory failure", "heart damage", "concussion", "hepatic failure")

/proc/medical_trial_target_types(family)
	switch(family)
		if("trauma")
			return list(/datum/affliction/deep_bruising, /datum/affliction/internal_hemorrhage, /datum/affliction/untreated_fracture, /datum/affliction/burn_shock)
		if("infection")
			return list(/datum/affliction/wound_infection, /datum/affliction/cellulitis, /datum/affliction/sepsis, /datum/affliction/septic_shock)
		if("respiratory")
			return list(/datum/affliction/pulmonary_contusion, /datum/affliction/pneumothorax, /datum/affliction/airway_burn, /datum/affliction/respiratory_failure)
		if("neurological")
			return list(/datum/affliction/concussion, /datum/affliction/subdural_hematoma, /datum/affliction/brain_damage)
		if("organ failure")
			return list(/datum/affliction/hepatic_failure, /datum/affliction/renal_failure, /datum/affliction/heart_damage)
	return list()

/proc/medical_trial_condition_burden(mob/living/carbon/human/subject, list/allowed_types)
	. = 0
	for(var/datum/affliction/condition as anything in subject.get_afflictions())
		if(allowed_types)
			var/type_allowed = FALSE
			for(var/condition_type in allowed_types)
				if(istype(condition, condition_type))
					type_allowed = TRUE
					break
			if(!type_allowed)
				continue
		. = max(., condition.severity)

/proc/medical_trial_snapshot(mob/living/carbon/human/subject)
	var/list/conditions = list()
	for(var/datum/affliction/condition as anything in subject.get_afflictions())
		var/list/symptoms = list()
		for(var/datum/affliction_symptom/symptom as anything in affliction_symptoms_of(condition))
			symptoms += symptom.name
		conditions.Add(list(list(
			"name" = condition.name,
			"type" = condition.type,
			"severity" = round(condition.severity, 0.1),
			"organ" = condition.location?.name || "systemic",
			"symptoms" = symptoms,
		)))
	var/list/bp = subject.get_bp_reading()
	return list(
		"conditions" = conditions,
		"vitals" = list(
			"pulse" = subject.get_pulse_reading_bpm(),
			"blood_pressure" = bp ? "[bp[1]]/[bp[2]]" : "undetectable",
			"oxygen_saturation" = subject.get_o2_sat_reading(),
			"respiration" = subject.get_respiratory_rate(),
			"temperature" = subject.get_temperature_reading_c(),
		),
		"damage" = list(
			"brute" = round(subject.injury_load(INJURY_CATEGORY_PHYSICAL), 0.1),
			"burn" = round(subject.injury_load(INJURY_CATEGORY_THERMAL), 0.1),
			"toxin" = round(subject.injury_load(INJURY_CATEGORY_TOXIC), 0.1),
			"oxygen" = round(subject.oxygen_debt(), 0.1),
		),
		"exposures" = subject.clinical_exposure_history?.Copy() || list(),
	)

/mob/living/carbon/human
	/// Machine-recorded medication exposure provenance. Conditions remain normal
	/// medical conditions; causal attribution lives here instead of in bespoke types.
	var/list/clinical_exposure_history

/mob/living/carbon/human/proc/record_clinical_exposure(contract_id, study_code, agent_name, amount)
	if(!contract_id || !isnum(amount) || amount <= 0)
		return
	var/list/existing
	for(var/list/entry as anything in clinical_exposure_history)
		if(entry["contract_id"] == contract_id && entry["agent"] == agent_name)
			existing = entry
			break
	if(!existing)
		existing = list(
			"contract_id" = contract_id,
			"study_code" = study_code,
			"agent" = agent_name,
			"first_exposure" = world.time,
			"dose" = 0,
		)
		LAZYINITLIST(clinical_exposure_history)
		clinical_exposure_history += list(existing)
	existing["dose"] += amount
	existing["last_exposure"] = world.time

/mob/living/carbon/human/proc/clinical_exposure_printout()
	if(!length(clinical_exposure_history))
		return ""
	var/result = "<br><b>Machine-recorded clinical exposures:</b><br>"
	for(var/list/entry as anything in clinical_exposure_history)
		result += "[entry["study_code"]]: [entry["agent"]], [round(entry["dose"], 0.1)] units<br>"
	return result

/mob/living/carbon/human/proc/medical_trial_marker_snapshot()
	var/list/markers = list()
	for(var/datum/reagent/reagent as anything in bloodstr?.reagent_list)
		if(reagent.id != MEDICAL_TRIAL_MARKER_REAGENT_ID || !islist(reagent.data))
			continue
		var/list/contracts = reagent.data["contracts"]
		for(var/contract_id in contracts)
			markers[contract_id] = round(reagent.volume, 0.01)
	return markers

/datum/contract/medical_trial/proc/apply_therapeutic_effect(mob/living/carbon/human/subject, amount)
	var/list/target_types = medical_trial_target_types(profile.target_metric)
	for(var/datum/affliction/condition as anything in subject.get_afflictions())
		if(condition.type in target_types)
			condition.adjust_severity(-amount * profile.therapeutic_strength)
			if(condition.severity <= 0)
				condition.cure()

/datum/contract/medical_trial/proc/apply_adverse_effect(mob/living/carbon/human/subject, amount)
	if(profile.adverse_metric == "none")
		return
	var/condition_type
	var/organ_tag
	switch(profile.adverse_metric)
		if("respiratory failure")
			condition_type = /datum/affliction/respiratory_failure
			organ_tag = O_LUNGS
		if("heart damage")
			condition_type = /datum/affliction/heart_damage
			organ_tag = O_HEART
		if("concussion")
			condition_type = /datum/affliction/concussion
			organ_tag = O_BRAIN
		if("hepatic failure")
			condition_type = /datum/affliction/hepatic_failure
			organ_tag = O_LIVER
	var/obj/item/organ/host = subject.internal_organs_by_name?[organ_tag]
	if(!host || !condition_type)
		return
	var/datum/affliction/adverse = subject.body.find_affliction(condition_type, host)
	if(!adverse)
		adverse = subject.body.afflict(condition_type, host)
		if(!adverse)
			return
		if(profile.adverse_metric == "heart damage")
			adverse._apply_stage("Moderate")
	adverse.adjust_severity(amount * profile.adverse_strength)
	adverse.roll_symptoms()
	var/datum/contract_subject_identity/identity = SScontracts.subject_identity(subject)
	var/datum/medical_trial_participant/participant = participants?[identity?.id]
	if(participant && !participant.coverup_contract_offered)
		participant.coverup_contract_offered = !!medical_trial_offer_coverup(src, participant)

/datum/contract/medical_trial/proc/apply_controlled_challenge(mob/living/carbon/human/subject, amount)
	var/condition_type
	var/obj/item/organ/host
	switch(profile.target_metric)
		if("trauma")
			condition_type = /datum/affliction/deep_bruising
			host = subject.get_organ(BP_TORSO)
		if("infection")
			condition_type = /datum/affliction/cellulitis
			host = subject.get_organ(BP_TORSO)
		if("respiratory")
			condition_type = /datum/affliction/pulmonary_contusion
			host = subject.internal_organs_by_name?[O_LUNGS]
		if("neurological")
			condition_type = /datum/affliction/concussion
			host = subject.internal_organs_by_name?[O_BRAIN]
		if("organ failure")
			condition_type = /datum/affliction/hepatic_failure
			host = subject.internal_organs_by_name?[O_LIVER]
	if(!host || !condition_type)
		return
	var/datum/affliction/challenge_condition = subject.body.afflict(condition_type, host)
	if(!challenge_condition)
		return
	challenge_condition.adjust_severity(amount * 4)
	challenge_condition.roll_symptoms()

/datum/reagent/medicine/experimental_contract
	name = "coded experimental medication"
	id = MEDICAL_TRIAL_REAGENT_ID
	description = "A VeyMed investigational compound with a contract-specific profile."
	taste_description = "clinical uncertainty"
	color = "#79b7c9"
	metabolism = REM * 0.5
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = 1
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/medicine/experimental_contract/affect_blood(mob/living/carbon/subject, alien, removed)
	var/mob/living/carbon/human/human_subject = subject
	if(!istype(human_subject))
		return
	var/list/contracts = medical_trial_contract_fractions(data)
	for(var/contract_id in contracts)
		var/effective_amount = removed * contracts[contract_id]
		var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[contract_id]
		if(!istype(trial) || trial.state != CONTRACT_ACTIVE || effective_amount <= 0)
			continue
		trial.record_exposure(human_subject, effective_amount)
		// The metabolite is intentionally transferable. Deception requires
		// physical chemistry rather than editable paper text.
		subject.bloodstr.add_reagent(MEDICAL_TRIAL_MARKER_REAGENT_ID, effective_amount, medical_trial_contract_data(contract_id))
		trial.apply_therapeutic_effect(human_subject, effective_amount)
		trial.apply_adverse_effect(human_subject, effective_amount)

/datum/reagent/medicine/experimental_contract/affect_ingest(mob/living/carbon/subject, alien, removed)
	// Preserve the signed study identifier when absorbed into the bloodstream;
	// the base reagent implementation intentionally drops arbitrary metadata.
	subject.bloodstr.add_reagent(id, removed, data)

/datum/reagent/medicine/experimental_contract/mix_data(list/newdata, newamount)
	medical_trial_merge_contract_data(src, newdata, newamount)

/datum/reagent/medical_trial_marker
	name = "coded trial metabolite"
	id = MEDICAL_TRIAL_MARKER_REAGENT_ID
	description = "An inert, contract-coded tracer used to authenticate clinical exposure."
	color = "#55d7c7"
	metabolism = REM * 0.05
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = 1
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/medical_trial_marker/mix_data(list/newdata, newamount)
	medical_trial_merge_contract_data(src, newdata, newamount)

/datum/reagent/medicine/experimental_challenge
	name = "coded controlled challenge"
	id = MEDICAL_TRIAL_CHALLENGE_REAGENT_ID
	description = "A tightly dosed VeyMed challenge agent for a preventative clinical protocol."
	taste_description = "sterile bitterness"
	color = "#d28d62"
	metabolism = REM * 0.5
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = 1
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/medicine/experimental_challenge/affect_blood(mob/living/carbon/subject, alien, removed)
	var/mob/living/carbon/human/human_subject = subject
	if(!istype(human_subject))
		return
	var/list/contracts = medical_trial_contract_fractions(data)
	for(var/contract_id in contracts)
		var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[contract_id]
		var/effective_amount = removed * contracts[contract_id]
		if(!istype(trial) || trial.state != CONTRACT_ACTIVE || trial.profile.cohort != MEDICAL_TRIAL_COHORT_PREVENTATIVE)
			continue
		if(trial.record_challenge(human_subject, effective_amount))
			trial.apply_controlled_challenge(human_subject, effective_amount)

/datum/reagent/medicine/experimental_challenge/affect_ingest(mob/living/carbon/subject, alien, removed)
	subject.bloodstr.add_reagent(id, removed, data)

/datum/reagent/medicine/experimental_challenge/mix_data(list/newdata, newamount)
	medical_trial_merge_contract_data(src, newdata, newamount)

/proc/medical_trial_contract_data(contract_id)
	var/list/contracts = list()
	contracts[contract_id] = 1
	return list("contracts" = contracts)

/proc/medical_trial_contract_fractions(list/provenance)
	var/list/result = list()
	if(islist(provenance?["contracts"]))
		for(var/contract_id in provenance["contracts"])
			if(provenance["contracts"][contract_id] > 0)
				result[contract_id] = provenance["contracts"][contract_id]
	else if(provenance?["contract_id"])
		result[provenance["contract_id"]] = 1
	var/total = 0
	for(var/contract_id in result)
		total += result[contract_id]
	if(total > 0)
		for(var/contract_id in result)
			result[contract_id] /= total
	return result

/proc/medical_trial_merge_contract_data(datum/reagent/reagent, list/newdata, newamount)
	if(!reagent || !isnum(newamount) || newamount <= 0)
		return
	var/old_amount = max(0, reagent.volume - newamount)
	var/list/old_contracts = medical_trial_contract_fractions(reagent.data)
	var/list/new_contracts = medical_trial_contract_fractions(newdata)
	var/list/weights = list()
	for(var/contract_id in old_contracts)
		weights[contract_id] = old_contracts[contract_id] * old_amount
	for(var/contract_id in new_contracts)
		weights[contract_id] = (weights[contract_id] || 0) + new_contracts[contract_id] * newamount
	var/total = old_amount + newamount
	if(total <= 0)
		return
	for(var/contract_id in weights)
		weights[contract_id] /= total
	reagent.data = list("contracts" = weights)

/proc/medical_trial_reagent_amount(datum/reagents/holder, reagent_id, contract_id)
	var/datum/reagent/reagent = holder?.get_reagent(reagent_id)
	if(!reagent)
		return 0
	var/list/contracts = medical_trial_contract_fractions(reagent.data)
	return reagent.volume * (contracts[contract_id] || 0)
