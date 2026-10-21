/// One eligible offer waiting for capacity on its station, department, or
/// personal board. Candidates are deliberately cheaper than live contracts:
/// no timers, requirements, physical supplies, or event subscriptions exist
/// until the lifecycle engine admits them.
/datum/contract_offer_candidate
	var/id
	var/definition_id
	var/offer_key
	var/board_key
	var/offer_kind
	var/reason
	EXPIRY_DECLARE(created_at)
	var/expires_at
	var/priority = 50
	var/list/context

/datum/contract_offer_candidate/New(_id, _definition_id, _offer_key, _board_key, _offer_kind, _reason, list/_context, _expires_at, _priority)
	. = ..()
	id = _id
	definition_id = _definition_id
	offer_key = _offer_key
	board_key = _board_key
	offer_kind = _offer_kind
	reason = _reason
	EXPIRY_STAMP(src, created_at, CLOCK_WORLD)
	expires_at = _expires_at
	priority = _priority
	context = _context ? deepCopyList(_context) : list()

/datum/contract_lifecycle_entry
	EXPIRY_DECLARE(time)
	var/action
	var/contract_id
	var/definition_id
	var/offer_key
	var/board_key
	var/reason

/datum/contract_lifecycle_entry/New(_action, _contract_id, _definition_id, _offer_key, _board_key, _reason)
	. = ..()
	EXPIRY_STAMP(src, time, CLOCK_WORLD)
	action = _action
	contract_id = _contract_id
	definition_id = _definition_id
	offer_key = _offer_key
	board_key = _board_key
	reason = _reason
