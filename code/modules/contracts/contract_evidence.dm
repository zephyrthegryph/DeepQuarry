/// A round-stable identity follows a mind through cloning and resleeving.
/datum/contract_subject_identity
	var/id
	/// The subject's mind (a relation view: follows cloning and resleeving, null once it is deleted).
	var/datum/mind/subject_mind
	var/account_number
	var/display_name
	/// The body last seen (a relation view).
	var/mob/living/body

CAPABILITIES(/datum/contract_subject_identity)
	ref_one(nameof(subject_mind), /datum/mind)
	ref_one(nameof(body), /mob/living)

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

/obj/item/paper/proc/attach_contract_evidence(evidence_id)
	if(!evidence_id)
		return FALSE
	if(carried_evidence_id != evidence_id)
		release_carried_evidence()
		if(SScontracts.retain_evidence(evidence_id))
			carried_evidence_id = evidence_id
	medical_scan_evidence = list("evidence_id" = evidence_id)
	return TRUE
