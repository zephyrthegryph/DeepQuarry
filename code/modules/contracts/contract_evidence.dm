/// A round-stable identity follows a mind through cloning and resleeving.
/datum/contract_subject_identity
	var/id
	/// The subject's mind (a relation view: follows cloning and resleeving, null once it is deleted).
	var/datum/mind/subject_mind
	var/account_number
	var/display_name
	/// The body last seen (a relation view).
	var/mob/living/body

/datum/contract_subject_identity/New(_id, mob/living/subject)
	. = ..()
	id = _id
	update(subject)

/datum/contract_subject_identity/proc/update(mob/living/subject)
	if(!subject)
		return
	if(subject.mind)
		rel_set(src, nameof(subject_mind), subject.mind)
		account_number = subject.mind.initial_account()?.account_number
	display_name = subject.real_name
	rel_set(src, nameof(body), subject)

/datum/contract_subject_identity/proc/current_mob() as /mob/living
	if(subject_mind)
		if(istype(subject_mind.current))
			return subject_mind.current
	if(account_number)
		return SScontracts?.find_mob_by_account(account_number)
	if(istype(body))
		return body

/// Immutable evidence provenance. Payloads are copied on registration.
/datum/contract_evidence
	var/id
	var/kind
	var/subject_id
	EXPIRY_DECLARE(created_at)
	var/creator_account
	var/source_ref
	var/consumed_by
	EXPIRY_DECLARE(consumed_at)
	var/reference_count = 0
	var/void_reason
	var/list/payload

/datum/contract_evidence/New(_id, _kind, _subject_id, _creator_account, atom/source, list/_payload)
	. = ..()
	id = _id
	kind = _kind
	subject_id = _subject_id
	creator_account = _creator_account
	source_ref = source ? REF(source) : null
	EXPIRY_STAMP(src, created_at, CLOCK_WORLD)
	payload = _payload ? deepCopyList(_payload) : list()

/datum/system/contracts/proc/subject_identity(mob/living/subject) as /datum/contract_subject_identity
	if(!subject)
		return null
	var/body_key = "body:[REF(subject)]"
	var/key = subject.mind ? "mind:[REF(subject.mind)]" : body_key
	var/datum/contract_subject_identity/identity = subject_identities[key]
	// A patient may be scanned before a player takes the body. Preserve every
	// existing document/evidence reference by migrating that body's identity to
	// the newly assigned mind instead of minting a second subject ID.
	if(!identity && subject.mind)
		identity = subject_identities[body_key]
		if(identity)
			subject_identities -= body_key
			subject_identities[key] = identity // ALLOW(ownership): the contracts system's own ledger table, written only by its own procs
	if(!identity)
		identity = new("DQ-SUB-[next_subject_id++]", subject)
		subject_identities[key] = identity // ALLOW(ownership): the contracts system's own ledger table, written only by its own procs
		subject_identities[identity.id] = identity // ALLOW(ownership): the contracts system's own ledger table, written only by its own procs
	else
		identity.update(subject)
	return identity

/datum/system/contracts/proc/resolve_subject(subject_id) as /mob/living
	var/datum/contract_subject_identity/identity = subject_identities[subject_id]
	return identity?.current_mob()

/datum/system/contracts/proc/find_mob_by_account(account_number) as /mob/living
	for(var/mob/living/subject in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(subject.mind?.initial_account()?.account_number == account_number)
			return subject

/datum/system/contracts/proc/register_evidence(kind, subject_id, creator_account, atom/source, list/payload)
	if(!kind)
		return null
	var/id = "DQ-EV-[next_evidence_id++]"
	var/datum/contract_evidence/evidence = new(id, kind, subject_id, creator_account, source, payload)
	evidence_by_id[id] = evidence // ALLOW(ownership): the contracts system's own ledger table, written only by its own procs
	emit_contract_event(CONTRACT_EVENT_EVIDENCE_REGISTERED, list(
		"subject_id" = subject_id,
		"actor_account" = creator_account,
		"contract_id" = payload?["contract_id"],
		"evidence_kind" = kind,
		"evidence_ids" = list(id),
	), "evidence-registered:[id]", source)
	return id

/datum/system/contracts/proc/retain_evidence(evidence_id)
	var/datum/contract_evidence/evidence = evidence_by_id[evidence_id]
	if(!evidence)
		return FALSE
	evidence.reference_count++
	return TRUE

/datum/system/contracts/proc/release_evidence(evidence_id)
	var/datum/contract_evidence/evidence = evidence_by_id[evidence_id]
	if(!evidence)
		return
	evidence.reference_count = max(0, evidence.reference_count - 1)
	if(!evidence.reference_count && !evidence.consumed_by)
		unregister_evidence(evidence)

/datum/system/contracts/proc/unregister_evidence(datum/contract_evidence/evidence)
	if(!evidence || evidence_by_id[evidence.id] != evidence)
		return
	evidence_by_id -= evidence.id
	spent(evidence)

/datum/system/contracts/proc/void_evidence(evidence_id, reason)
	var/datum/contract_evidence/evidence = evidence_by_id[evidence_id]
	if(!evidence || evidence.consumed_by)
		return FALSE
	evidence.void_reason = reason || "Voided by the issuing office."
	if(!evidence.reference_count)
		unregister_evidence(evidence)
	return TRUE

/datum/system/contracts/proc/bind_evidence_subject(evidence_id, subject_id)
	var/datum/contract_evidence/evidence = evidence_by_id[evidence_id]
	if(!evidence || evidence.consumed_by || (evidence.subject_id && evidence.subject_id != subject_id))
		return FALSE
	evidence.subject_id = subject_id
	return TRUE

/// Atomic consume: either every supplied record is available and bound, or none are consumed.
/datum/system/contracts/proc/consume_evidence(list/evidence_ids, contract_id)
	if(!evidence_available(evidence_ids) || !contract_id)
		return FALSE
	var/list/unique_ids = list()
	for(var/evidence_id in evidence_ids)
		unique_ids += evidence_id
	for(var/evidence_id in unique_ids)
		var/datum/contract_evidence/evidence = evidence_by_id[evidence_id]
		evidence.consumed_by = contract_id
		EXPIRY_STAMP(evidence, consumed_at, CLOCK_WORLD)
	emit_contract_event(CONTRACT_EVENT_EVIDENCE_CONSUMED, list(
		"contract_id" = contract_id,
		"evidence_ids" = unique_ids.Copy(),
		"metrics" = list("evidence_count" = length(unique_ids)),
		"detail" = "Authenticated evidence consumed by [contract_id]",
	), "evidence-consumed:[contract_id]:[jointext(unique_ids, ",")]" )
	return TRUE

/datum/system/contracts/proc/evidence_available(list/evidence_ids)
	if(!length(evidence_ids))
		return FALSE
	var/list/unique_ids = list()
	for(var/evidence_id in evidence_ids)
		if(!evidence_id || (evidence_id in unique_ids))
			return FALSE
		var/datum/contract_evidence/evidence = evidence_by_id[evidence_id]
		if(!evidence || evidence.consumed_by || evidence.void_reason)
			return FALSE
		unique_ids += evidence_id
	return TRUE

/datum/system/contracts/proc/evidence_summary(contract_id)
	var/registered = 0
	var/consumed = 0
	for(var/id in evidence_by_id)
		var/datum/contract_evidence/evidence = evidence_by_id[id]
		registered++
		if(evidence.consumed_by == contract_id)
			consumed++
	return list("registered" = registered, "consumed" = consumed)

/datum/system/contracts/proc/authenticated_scan_payload(obj/item/paper/paper)
	var/evidence_id = paper?.medical_scan_evidence?["evidence_id"]
	var/datum/contract_evidence/evidence = evidence_by_id[evidence_id]
	if(!evidence || evidence.kind != CONTRACT_EVIDENCE_MEDICAL_SCAN || evidence.consumed_by || evidence.void_reason)
		return null
	var/list/result = deepCopyList(evidence.payload)
	result["evidence_id"] = evidence.id
	return result

/datum/system/contracts/proc/schedule_contract_evidence_prune(contract_id)
	after(src, CONTRACT_EVIDENCE_RETENTION, PROC_REF(prune_contract_evidence), with = list(contract_id))

/datum/system/contracts/proc/prune_contract_evidence(contract_id)
	for(var/evidence_id in evidence_by_id.Copy())
		var/datum/contract_evidence/evidence = evidence_by_id[evidence_id]
		if(evidence.consumed_by == contract_id || evidence.payload?["contract_id"] == contract_id)
			unregister_evidence(evidence)

/obj/item/paper/proc/attach_contract_evidence(evidence_id)
	if(!evidence_id)
		return FALSE
	if(carried_evidence_id != evidence_id)
		release_carried_evidence()
		if(SScontracts.retain_evidence(evidence_id))
			carried_evidence_id = evidence_id
	medical_scan_evidence = list("evidence_id" = evidence_id)
	return TRUE
