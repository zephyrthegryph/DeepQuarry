// Freight-audit operations belong to the supply system.

/datum/system/supply/proc/audit_next_market_transaction(mob/living/user)
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
