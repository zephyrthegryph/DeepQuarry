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
		for(var/id in contracts_contracts_by_id())
			var/datum/contract/contract = contracts_contracts_by_id()[id]
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

CAPABILITIES(/datum/data/pda/app/contracts)
	op("contract_agent_apply", ui_act("contract_agent_apply", arg("faction", schema_text(128))), asks(/datum/prompt/choice, fields = list("question" = computed(PROC_REF(ui_act_contract_agent_apply_k39_question)), "title" = "Faction vetting", "choices" = list("Cancel", "Begin vetting"), "buttons" = TRUE, "timeout" = 0), step = "k39", when = PROC_REF(agent_vetting_asks)), then(PROC_REF(ui_act_contract_agent_apply)))
	op("contract_stakeholder_propose", ui_act("contract_stakeholder_propose", arg("id", schema_text(128)), arg("role", schema_text(128)), arg("weight", num())), then(PROC_REF(ui_act_contract_stakeholder_propose)))
	op("contract_stakeholder_withdraw", ui_act("contract_stakeholder_withdraw", arg("id", schema_text(128)), arg("role", schema_text(128))), then(PROC_REF(ui_act_contract_stakeholder_withdraw)))
	op("contract_decline", ui_act("contract_decline", arg("id", schema_text(128))), then(PROC_REF(ui_act_contract_decline)))
	op("contract_accept", ui_act("contract_accept", arg("id", schema_text(128))), asks(/datum/prompt/choice, fields = list("question" = "This is a RED CONTRACT. Acceptance explicitly registers you as a contract antagonist for the written objective until it closes. This is not unrestricted permission to antagonize or grief. Accept?", "title" = "Explicit antagonist opt-in", "choices" = list("Cancel", "Accept red contract"), "buttons" = TRUE, "timeout" = 0), step = "k57", when = PROC_REF(red_contract_asks)), then(PROC_REF(ui_act_contract_accept)))
/datum/data/pda/app/contracts/proc/ui_act_contract_agent_apply(datum/act/op/A, faction_arg)
	var/mob/user = A.actor
	var/datum/money_account/account = holder_account(user)
	if(!account)
		return FALSE
	var/datum/reputation_faction/faction = GLOB.reputation_factions[faction_arg]
	if(!faction || !GLOB.station_faction_relations.account_agent_eligibility(account.account_number, faction.id))
		return FALSE
	var/_answer_k39 = A.step_value("k39")
	if(isnull(_answer_k39))
		return
	if(_answer_k39 != "Begin vetting")
		return FALSE
	if(pda().loc != user || !pda().id || pda().id.associated_account_number != account.account_number)
		return FALSE
	return GLOB.station_faction_relations.begin_agent_vetting(user, faction.id)

/datum/data/pda/app/contracts/proc/ui_act_contract_stakeholder_propose(datum/act/op/A, id, role, weight)
	var/mob/user = A.actor
	var/datum/money_account/account = holder_account(user)
	var/datum/contract/social/social = contracts_contracts_by_id()[id]
	return account && istype(social) && social.propose_stakeholder(account, role, weight)

/datum/data/pda/app/contracts/proc/ui_act_contract_stakeholder_withdraw(datum/act/op/A, id, role)
	var/mob/user = A.actor
	var/datum/money_account/account = holder_account(user)
	var/datum/contract/social/social = contracts_contracts_by_id()[id]
	return account && istype(social) && social.withdraw_stakeholder(account, role)

/datum/data/pda/app/contracts/proc/ui_act_contract_decline(datum/act/op/A, id)
	var/mob/user = A.actor
	var/datum/money_account/account = holder_account(user)
	var/datum/contract/contract = contracts_contracts_by_id()[id]
	if(!account || !contract)
		return FALSE
	if(contract.scope != CONTRACT_SCOPE_PERSONAL || contract.owner_account_number != account.account_number)
		return FALSE
	return contract.decline(user)

/datum/data/pda/app/contracts/proc/ui_act_contract_accept(datum/act/op/A, id)
	var/mob/user = A.actor
	var/datum/money_account/account = holder_account(user)
	var/datum/contract/contract = contracts_contracts_by_id()[id]
	if(!account || !contract)
		return FALSE
	if(contract.scope != CONTRACT_SCOPE_PERSONAL || contract.owner_account_number != account.account_number)
		return FALSE
	var/datum/contract/faction_agent/agent_contract = contract
	if(istype(agent_contract) && agent_contract.red_contract)
		var/_answer_k57 = A.step_value("k57")
		if(isnull(_answer_k57))
			return
		if(_answer_k57 != "Accept red contract")
			return FALSE
		if(pda().loc != user || !pda().id || pda().id.associated_account_number != account.account_number || contract.state != CONTRACT_OFFERED)
			return FALSE
	return contract.accept(account, user, pda())

// The questions' computed fields (asks()).
/datum/data/pda/app/contracts/proc/ui_act_contract_agent_apply_k39_question(datum/act/op/A)
	var/datum/reputation_faction/faction = GLOB.reputation_factions[A.args["faction"]]
	return "Open exclusive vetting with [faction.name] for the remainder of this round? You must complete an authenticated trade before accreditation. The relationship grants no legal immunity or special permission."

/// The vetting question opens for a known faction (the handler refuses an account that may not apply).
/datum/data/pda/app/contracts/proc/agent_vetting_asks(datum/act/op/A)
	return !isnull(GLOB.reputation_factions[A.args["faction"]])

/// The antagonist opt-in opens only for a red contract.
/datum/data/pda/app/contracts/proc/red_contract_asks(datum/act/op/A)
	var/datum/system/contracts/service = SScontracts
	var/datum/contract/faction_agent/agent_contract = service.contracts_by_id[A.args["id"]]
	return istype(agent_contract) && agent_contract.red_contract
