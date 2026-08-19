/datum/data/pda/app/contracts
	name = "Contracts"
	icon = "file-signature"
	template = "pda_contracts"

/datum/data/pda/app/contracts/start()
	. = ..()
	unnotify()

/datum/data/pda/app/contracts/update_ui(mob/living/user, list/data)
	var/list/contracts = list()
	var/datum/money_account/account = pda.id ? get_account(pda.id.associated_account_number) : null
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

/datum/data/pda/app/contracts/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE
	if(!(action in list("contract_accept", "contract_decline", "contract_stakeholder_propose", "contract_agent_apply")) || pda.loc != ui.user || !pda.id)
		return FALSE
	var/datum/money_account/account = get_account(pda.id.associated_account_number)
	var/datum/contract/contract = SScontracts.contracts_by_id[params["id"]]
	if(!account || !contract)
		if(action == "contract_agent_apply" && account)
			var/datum/reputation_faction/faction = GLOB.reputation_factions[params["faction"]]
			if(!faction || !GLOB.station_faction_relations.account_agent_eligibility(account.account_number, faction.id))
				return FALSE
			if(tgui_alert(ui.user, "Open exclusive vetting with [faction.name] for the remainder of this round? You must complete an authenticated trade before accreditation. The relationship grants no legal immunity or special permission.", "Faction vetting", list("Cancel", "Begin vetting")) != "Begin vetting")
				return FALSE
			if(pda.loc != ui.user || !pda.id || pda.id.associated_account_number != account.account_number)
				return FALSE
			return GLOB.station_faction_relations.begin_agent_vetting(ui.user, faction.id)
		return FALSE
	if(action == "contract_stakeholder_propose")
		var/datum/contract/social/social = contract
		return istype(social) && social.propose_stakeholder(account, params["role"], text2num(params["weight"]))
	if(contract.scope != CONTRACT_SCOPE_PERSONAL || contract.owner_account_number != account.account_number)
		return FALSE
	if(action == "contract_decline")
		return contract.decline(ui.user)
	var/datum/contract/faction_agent/agent_contract = contract
	if(istype(agent_contract) && agent_contract.red_contract)
		if(tgui_alert(ui.user, "This is a RED CONTRACT. Acceptance explicitly registers you as a contract antagonist for the written objective until it closes. This is not unrestricted permission to antagonize or grief. Accept?", "Explicit antagonist opt-in", list("Cancel", "Accept red contract")) != "Accept red contract")
			return FALSE
		if(pda.loc != ui.user || !pda.id || pda.id.associated_account_number != account.account_number || contract.state != CONTRACT_OFFERED)
			return FALSE
	return contract.accept(account, ui.user, pda)
