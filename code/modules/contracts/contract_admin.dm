ADMIN_VERB(dq_inspect_contract, R_ADMIN, "Inspect Contract", "Inspect contract state, evidence, contributions, and audit history.", ADMIN_CATEGORY_DEBUG)
	return contract_inspect_stage(user, list())

/datum/admin_verb/dq_inspect_contract/proc/contract_inspect_stage(client/user, list/inspect_answers)
	var/list/options = list()
	for(var/id in contracts_contracts_by_id())
		var/datum/contract/contract = contracts_contracts_by_id()[id]
		options["[contract.id] — [contract.title] ([contract.state])"] = contract
	if(!("k6" in inspect_answers))
		if(!user || !user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/choice/contract_inspector_review, PROC_REF(contract_inspect_answered), answerer = user.mob, choices = options)
		return
	var/selection = inspect_answers["k6"]
	if(isnull(selection))
		return
	var/datum/contract/contract = options[selection]
	if(!contract)
		return
	var/list/evidence = SScontracts.evidence_summary(contract.id)
	var/list/event_stats = SScontracts.event_observability()
	var/html = "<h2>[html_encode(contract.id)] — [html_encode(contract.title)]</h2>"
	html += "<b>State:</b> [html_encode(contract.state)]<br><b>Issuer:</b> [html_encode(contract.issuer_name)]<br><b>Scope:</b> [html_encode(contract.scope)] / [html_encode(contract.department || "none")]<br>"
	html += "<b>Offer lifecycle:</b> [html_encode(contract.offer_kind)] / [html_encode(contract.offer_key || "direct")] on [html_encode(contract.board_key || "unmanaged")]<br><b>Closure:</b> [html_encode(contract.closure_code || "open")]<br>"
	html += "<b>Reward:</b> [contract.reward] Thalers<br><b>Evidence:</b> [evidence["consumed"]] consumed for this contract; [evidence["registered"]] registered globally.<br>"
	html += "<b>Sponsor standing:</b> [html_encode(contract.standing_tier)] ([contract.standing_score]).<br>"
	html += "<b>Evidence bus:</b> [event_stats["published"]] published, [event_stats["dispatched"]] routed, [event_stats["matched"]] matched, [event_stats["deduplicated"]] duplicates suppressed, [event_stats["rejected"]] invalid rejected.<br>"
	html += "<h3>Contributions</h3><ul>"
	for(var/account in contract.contributions)
		html += "<li>[html_encode(contract.contributor_names[account] || "Account [account]")]: [contract.contributions[account]] weight</li>"
	html += "</ul><h3>Audit history</h3><table border='1' cellspacing='0' cellpadding='4'><tr><th>Time</th><th>Category</th><th>Detail</th></tr>"
	for(var/datum/contract_audit_entry/entry in contract.audit_log)
		html += "<tr><td>[worldtime2stationtime(entry.time)]</td><td>[html_encode(entry.category)]</td><td>[html_encode(entry.detail)]</td></tr>"
	html += "</table><h3>Recent routed evidence</h3><table border='1' cellspacing='0' cellpadding='4'><tr><th>Time</th><th>ID</th><th>Type</th><th>Fact / revision</th><th>Active</th><th>Actor/source</th><th>Detail</th></tr>"
	for(var/index = length(contracts_recent_events()), index >= 1, index--)
		var/datum/contract_event/event = contracts_recent_events()[index]
		if(event.contract_id && event.contract_id != contract.id)
			continue
		html += "<tr><td>[worldtime2stationtime(event.occurred_at)]</td><td>[html_encode(event.id)]</td><td>[html_encode(event.event_type)]</td><td>[html_encode(event.fact_id || "final event")] / [event.fact_revision]</td><td>[event.fact_active ? "yes" : "no"]</td><td>[html_encode(event.actor_name || event.actor_account || event.source_type || "system")]</td><td>[html_encode(event.value("detail") || "")]</td></tr>"
	html += "</table>"
	user.mob << browse(html, "window=dq_contract_inspector;size=760x620")

ADMIN_VERB(dq_inspect_contract_board, R_ADMIN, "Inspect Contract Board", "Inspect offer queues, limits, cooldowns, and lifecycle outcomes.", ADMIN_CATEGORY_DEBUG)
	var/list/summary = SScontracts.lifecycle_summary()
	var/list/opportunity_summary = SScontracts.opportunity_observability()
	var/html = "<h2>Contract Offer Lifecycle</h2>"
	html += "<b>Current:</b> [summary["candidates"]] queued, [summary["offered"]] offered, [summary["active"]] active, [summary["grace"]] in grace, [summary["closed"]] closed.<br>"
	html += "<b>Outcomes:</b> [summary["materialized"]] materialized, [summary["declined"]] declined, [summary["expired"]] expired, [summary["withdrawn"]] ineligible withdrawals.<br>"
	html += "<b>Opportunity broker:</b> [opportunity_summary["rules"]] rules, [opportunity_summary["windows"]] rolling windows, [opportunity_summary["events"]] relevant events, [opportunity_summary["triggered"]] offers triggered, [opportunity_summary["suppressed"]] duplicate/cooldown triggers suppressed.<br>"
	html += "<h3>Candidate queue</h3><table border='1' cellspacing='0' cellpadding='4'><tr><th>ID</th><th>Definition</th><th>Board</th><th>Priority</th><th>Expires</th><th>Reason</th></tr>"
	for(var/datum/contract_offer_candidate/candidate in contracts_offer_candidates())
		var/expires = candidate.expires_at ? worldtime2stationtime(candidate.expires_at) : "standing"
		html += "<tr><td>[html_encode(candidate.id)]</td><td>[html_encode(candidate.definition_id)]</td><td>[html_encode(candidate.board_key)]</td><td>[candidate.priority]</td><td>[html_encode(expires)]</td><td>[html_encode(candidate.reason)]</td></tr>"
	html += "</table><h3>Offer cooldowns</h3><table border='1' cellspacing='0' cellpadding='4'><tr><th>Offer key</th><th>Available</th></tr>"
	for(var/offer_key in contracts_offer_cooldowns())
		var/available_at = contracts_offer_cooldowns()[offer_key]
		html += "<tr><td>[html_encode(offer_key)]</td><td>[html_encode(BEFORE(src, available_at, CLOCK_WORLD) ? worldtime2stationtime(available_at) : "now")]</td></tr>"
	html += "</table><h3>Opportunity windows / near misses</h3><table border='1' cellspacing='0' cellpadding='4'><tr><th>Rule</th><th>Bucket</th><th>Overall</th><th>Lane progress</th><th>Last activity</th></tr>"
	for(var/list/near_miss as anything in SScontracts.opportunity_near_misses())
		html += "<tr><td>[html_encode(near_miss["rule"])]</td><td>[html_encode(near_miss["bucket"])]</td><td>[near_miss["progress"]]%</td><td>[html_encode(near_miss["lanes"])]</td><td>[worldtime2stationtime(near_miss["last_event_at"])]</td></tr>"
	html += "</table><h3>Recent opportunity triggers</h3><table border='1' cellspacing='0' cellpadding='4'><tr><th>Time</th><th>Rule</th><th>Bucket</th><th>Offer</th><th>Trigger event</th><th>Signal snapshot</th></tr>"
	for(var/index = length(contracts_opportunity_history()), index >= 1, index--)
		var/datum/contract_opportunity_history_entry/opportunity = contracts_opportunity_history()[index]
		var/list/signal_parts = list()
		for(var/signal_id in opportunity.snapshots)
			var/list/snapshot = opportunity.snapshots[signal_id]
			signal_parts += "[signal_id]: [round(snapshot["value"], 0.1)] value / [snapshot["facts"]] facts / [snapshot["actors"]] actors"
		html += "<tr><td>[worldtime2stationtime(opportunity.time)]</td><td>[html_encode(opportunity.rule_id)]</td><td>[html_encode(opportunity.bucket)]</td><td>[html_encode(opportunity.offer_key)]</td><td>[html_encode(opportunity.event_id)]</td><td>[html_encode(jointext(signal_parts, "; "))]</td></tr>"
	html += "</table><h3>Recent lifecycle history</h3><table border='1' cellspacing='0' cellpadding='4'><tr><th>Time</th><th>Action</th><th>Definition / contract</th><th>Board</th><th>Reason</th></tr>"
	for(var/index = length(contracts_lifecycle_history()), index >= 1, index--)
		var/datum/contract_lifecycle_entry/entry = contracts_lifecycle_history()[index]
		html += "<tr><td>[worldtime2stationtime(entry.time)]</td><td>[html_encode(entry.action)]</td><td>[html_encode(entry.definition_id)] / [html_encode(entry.contract_id || "candidate")]</td><td>[html_encode(entry.board_key || "none")]</td><td>[html_encode(entry.reason || "") ]</td></tr>"
	html += "</table>"
	user.mob << browse(html, "window=dq_contract_board;size=900x680")

/datum/prompt/choice/contract_inspector_review
	recheck_on_open = TRUE
	timeout = 0
	rights = R_ADMIN
	question = "Select a contract to inspect."
	title = "Contract Inspector"

/datum/prompt/choice/contract_inspector_review/recheck_extra()
	if(!admin_can(answerer?.client, 0))
		return "no admin rights"

/proc/contract_inspector_advanced_call(mob/actor)
#ifdef TESTING
	return FALSE
#else
	return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
#endif

/datum/admin_verb/dq_inspect_contract/proc/contract_inspect_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	if(contract_inspector_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	return contract_inspect_stage(user, list("k6" = context.answer.value))
