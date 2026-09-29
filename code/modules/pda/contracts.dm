/datum/data/pda/app/contracts
	name = "Contracts"
	icon = "file-signature"
	template = "pda_contracts"

/datum/data/pda/app/contracts/start()
	. = ..()
	unnotify()

/datum/data/pda/app/contracts/update_ui(mob/living/user, list/data)
	var/list/contracts = list()
	var/datum/money_account/account = pda().id ? get_account(pda().id.associated_account_number) : null
	if(account)
		for(var/id in SScontracts.contracts_by_id)
			var/datum/contract/contract = SScontracts.contracts_by_id[id]
			var/personal_contract = contract.scope == CONTRACT_SCOPE_PERSONAL && contract.owner_account_number == account.account_number
			var/datum/contract/social/social = contract
			var/social_opportunity = istype(social) && social.account_can_participate(account)
			if(!personal_contract && !social_opportunity)
				continue
			var/list/row = SScontracts.contract_row(user, contract, personal_contract && contract.state == CONTRACT_OFFERED)
			contracts.Add(list(row))
	data["contracts"] = contracts
	data["contract_account"] = account?.account_number
	data["agents"] = faction_agent_ui_rows(account)

/// The account of the PDA's ID, while `user` holds the PDA; null otherwise.
/datum/data/pda/app/contracts/proc/holder_account(mob/user)
	if(pda().loc != user || !pda().id)
		return null
	return get_account(pda().id.associated_account_number)

UI_ACT(/datum/data/pda/app/contracts, "contract_agent_apply", ui_act_contract_agent_apply, UI_ARG_TEXT("faction", 128))
UI_ACT_PROC(/datum/data/pda/app/contracts, ui_act_contract_agent_apply)
	var/datum/money_account/account = holder_account(user)
	if(!account)
		return FALSE
	var/datum/reputation_faction/faction = GLOB.reputation_factions[params["faction"]]
	if(!faction || !GLOB.station_faction_relations.account_agent_eligibility(account.account_number, faction.id))
		return FALSE
	var/_answer_k39 = act_ask(user, action, params, ui, "k39", /datum/om/prompt/choice/alert, message = "Open exclusive vetting with [faction.name] for the remainder of this round? You must complete an authenticated trade before accreditation. The relationship grants no legal immunity or special permission.", title = "Faction vetting", choices = list("Cancel", "Begin vetting"))
	if(isnull(_answer_k39))
		return
	if(_answer_k39 != "Begin vetting")
		return FALSE
	if(pda().loc != user || !pda().id || pda().id.associated_account_number != account.account_number)
		return FALSE
	return GLOB.station_faction_relations.begin_agent_vetting(user, faction.id)

UI_ACT(/datum/data/pda/app/contracts, "contract_stakeholder_propose", ui_act_contract_stakeholder_propose, UI_ARG_TEXT("id", 128), UI_ARG_TEXT("role", 128), UI_ARG_NUM("weight"))
UI_ACT_PROC(/datum/data/pda/app/contracts, ui_act_contract_stakeholder_propose)
	var/datum/money_account/account = holder_account(user)
	var/datum/contract/social/social = SScontracts.contracts_by_id[params["id"]]
	return account && istype(social) && social.propose_stakeholder(account, params["role"], params["weight"])

UI_ACT(/datum/data/pda/app/contracts, "contract_stakeholder_withdraw", ui_act_contract_stakeholder_withdraw, UI_ARG_TEXT("id", 128), UI_ARG_TEXT("role", 128))
UI_ACT_PROC(/datum/data/pda/app/contracts, ui_act_contract_stakeholder_withdraw)
	var/datum/money_account/account = holder_account(user)
	var/datum/contract/social/social = SScontracts.contracts_by_id[params["id"]]
	return account && istype(social) && social.withdraw_stakeholder(account, params["role"])

UI_ACT(/datum/data/pda/app/contracts, "contract_decline", ui_act_contract_decline, UI_ARG_TEXT("id", 128))
UI_ACT_PROC(/datum/data/pda/app/contracts, ui_act_contract_decline)
	var/datum/money_account/account = holder_account(user)
	var/datum/contract/contract = SScontracts.contracts_by_id[params["id"]]
	if(!account || !contract)
		return FALSE
	if(contract.scope != CONTRACT_SCOPE_PERSONAL || contract.owner_account_number != account.account_number)
		return FALSE
	return contract.decline(user)

UI_ACT(/datum/data/pda/app/contracts, "contract_accept", ui_act_contract_accept, UI_ARG_TEXT("id", 128))
UI_ACT_PROC(/datum/data/pda/app/contracts, ui_act_contract_accept)
	var/datum/money_account/account = holder_account(user)
	var/datum/contract/contract = SScontracts.contracts_by_id[params["id"]]
	if(!account || !contract)
		return FALSE
	if(contract.scope != CONTRACT_SCOPE_PERSONAL || contract.owner_account_number != account.account_number)
		return FALSE
	var/datum/contract/faction_agent/agent_contract = contract
	if(istype(agent_contract) && agent_contract.red_contract)
		var/_answer_k57 = act_ask(user, action, params, ui, "k57", /datum/om/prompt/choice/alert, message = "This is a RED CONTRACT. Acceptance explicitly registers you as a contract antagonist for the written objective until it closes. This is not unrestricted permission to antagonize or grief. Accept?", title = "Explicit antagonist opt-in", choices = list("Cancel", "Accept red contract"))
		if(isnull(_answer_k57))
			return
		if(_answer_k57 != "Accept red contract")
			return FALSE
		if(pda().loc != user || !pda().id || pda().id.associated_account_number != account.account_number || contract.state != CONTRACT_OFFERED)
			return FALSE
	return contract.accept(account, user, pda())
