// Contract-system operations moved from code/modules/contracts/damage_batch.dm.

/datum/system/contracts/proc/begin_contract_batch()
	contract_batch_depth++

/datum/system/contracts/proc/end_contract_batch()
	if(contract_batch_depth <= 0)
		return
	if(--contract_batch_depth > 0)
		return
	flush_damage_reports()
	flush_opportunity_windows()

/datum/system/contracts/proc/is_contract_batching()
	return contract_batch_depth > 0

/// Adds one hit to `source`'s pending report for this batch.
/datum/system/contracts/proc/queue_damage_report(atom/source, amount)
	var/key = REF(source)
	var/datum/contract_damage_report/report = LAZYACCESS(pending_damage_reports, key)
	if(!report)
		report = new(source)
		rel_add(src, nameof(pending_damage_reports), report, key)
	report.total_amount += amount
	report.integrity = source.get_integrity()

/datum/system/contracts/proc/flush_damage_reports()
	// rel_take_all() empties the owned list in place and hands back its values (the reports),
	// so iterate what it returns, not the var.
	var/list/reports = rel_take_all(src, nameof(pending_damage_reports))
	// Publishing here must not re-queue: the batch is closed by now, but keep
	// the broker batched so every window is evaluated once for all reports.
	contract_batch_depth++
	for(var/datum/contract_damage_report/report as anything in reports)
		publish_damage_report(report)
		spent(report)
	contract_batch_depth--

/datum/system/contracts/proc/publish_damage_report(datum/contract_damage_report/report)
	if(report.total_amount < CONTRACT_INFRASTRUCTURE_DAMAGE_MINIMUM)
		return
	var/key = report.source_ref
	var/revision = (infrastructure_fact_revisions[key] || 0) + 1
	infrastructure_fact_revisions[key] = revision
	var/current_damage = max(0, report.max_integrity - report.integrity)
	var/asset_label = "[report.name] in [report.area_name]"
	if(report.location_ref)
		asset_label += " ([report.x], [report.y], [report.z])"
	var/datum/contract_event/event = new(CONTRACT_EVENT_INFRASTRUCTURE_DAMAGED, null, null, null, list(
		"department" = DEPARTMENT_ENGINEERING,
		"atom_id" = key,
		"asset_name" = report.name,
		"asset_label" = asset_label,
		"atom_type" = report.source_type,
		"fact_id" = "infrastructure-damage:[key]",
		"fact_revision" = revision,
		"fact_active" = current_damage > 0,
		"metrics" = list(
			"damage_amount" = current_damage,
			"integrity" = report.integrity,
			"maximum_integrity" = report.max_integrity,
		),
		"detail" = "[report.name] sustained [round(report.total_amount, 0.1)] integrity damage in [report.area_name].",
	), "infrastructure-damage:[key]:[revision]")
	event.source_ref = key
	event.source_type = report.source_type
	event.location_ref = report.location_ref
	event.x = report.x
	event.y = report.y
	event.z = report.z
	event.area_name = report.area_name
	publish_event(event)

/// Evaluates every opportunity window the batch revised, once each.
/datum/system/contracts/proc/flush_opportunity_windows()
	var/list/windows = pending_opportunity_windows
	pending_opportunity_windows = null
	pruned_opportunity_windows = null
	for(var/window_key in windows)
		var/datum/contract_opportunity_window/window = opportunity_windows?[window_key]
		if(!window)
			continue
		var/datum/contract_event/event = window.batch_event
		rel_clear(window, nameof(window.batch_event))
		if(QDELETED(event))
			continue
		var/rule_id = splittext(window_key, "|")[1]
		var/datum/contract_opportunity_rule/rule = opportunity_rules?[rule_id]
		if(rule)
			evaluate_opportunity_window(rule, window, window_key, event)
