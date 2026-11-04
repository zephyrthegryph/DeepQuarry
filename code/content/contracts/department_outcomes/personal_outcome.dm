/datum/contract_definition/personal_outcome
	abstract_type = /datum/contract_definition/personal_outcome
	scope = CONTRACT_SCOPE_PERSONAL
	offer_kind = CONTRACT_OFFER_OPPORTUNITY
	candidate_duration = 10 MINUTES
	max_simultaneous = 32
	contract_type = /datum/contract/personal_outcome
	var/minimum_personal_reputation = REPUTATION_UNFRIENDLY

/datum/contract_definition/personal_outcome/is_available(list/context)
	var/owner_account = context?["owner_account"]
	var/datum/contract/parent = contracts_contracts_by_id()[context?["parent_contract_id"]]
	if(!owner_account || !get_account(owner_account) || !istype(parent) || parent.state != CONTRACT_ACTIVE)
		return FALSE
	var/mob/living/owner = contract_mob_for_account(owner_account)
	return owner && (owner.client || contract_unit_test_mode()) && owner.stat != DEAD && owner.get_faction_reputation(issuer_faction) >= minimum_personal_reputation

/datum/contract_definition/personal_outcome/offer_remains_available(datum/contract/contract)
	return is_available(contract.offer_context)

/datum/contract_definition/personal_outcome/active_remains_possible(datum/contract/contract)
	var/datum/contract/personal_outcome/personal = contract
	var/datum/contract/parent = contracts_contracts_by_id()[personal.linked_parent_id]
	if(!istype(parent))
		return FALSE
	// An accepted private bargain survives successful settlement of its public
	// parent. Cancellation still closes work whose underlying project vanished.
	return parent.state in list(CONTRACT_ACTIVE, CONTRACT_GRACE, CONTRACT_COMPLETED)
