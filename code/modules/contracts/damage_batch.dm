/// Batched contract reporting for bulk damage (init_and_turfs.md §2.1, §4.4).
///
/// A big explosion damages thousands of objects, and reporting each hit
/// published one contract event and recomputed every opportunity window's
/// snapshot per hit (about 5 s for the brig blast). Between
/// `begin_contract_batch()` and `end_contract_batch()`:
///
/// - `contract_report_station_damage()` only accumulates, per damaged atom,
///   the total damage and a snapshot of where it was (the atom may be
///   destroyed before the batch ends);
/// - at the end each damaged atom is published once, as one fact carrying the
///   batch's total, and the opportunity broker evaluates each window it
///   touched once for the whole batch instead of once per event.
///
/// Batches nest; only the outermost end flushes.

/datum/system/contracts
	var/contract_batch_depth = 0
	/// REF(atom) -> /datum/contract_damage_report, in first-hit order.
	var/list/pending_damage_reports
	/// window key -> TRUE when the batch revised it (the event is the window's batch_event).
	var/list/pending_opportunity_windows
	/// window key -> TRUE once pruned in this batch.
	var/list/pruned_opportunity_windows

CAPABILITIES(/datum/system/contracts)
	owns_many(nameof(pending_damage_reports))

/// One damaged atom's accumulated damage in a batch, with the location facts
/// the event needs if the atom is gone by the time the batch flushes.
/datum/contract_damage_report
	var/source_ref
	var/source_type
	var/name
	var/area_name
	var/location_ref
	var/x
	var/y
	var/z
	var/total_amount = 0
	var/integrity = 0
	var/max_integrity = 0

/datum/contract_damage_report/New(atom/source)
	. = ..()
	source_ref = REF(source)
	source_type = source.type
	name = source.name
	max_integrity = source.max_integrity
	var/turf/source_turf = get_turf(source)
	if(source_turf)
		location_ref = REF(source_turf)
		x = source_turf.x
		y = source_turf.y
		z = source_turf.z
		var/area/source_area = source_turf.loc
		area_name = source_area?.name

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
	// own_take_all() empties the owned list in place and hands back its values (the reports),
	// so iterate what it returns, not the var.
	var/list/reports = own_take_all(src, nameof(pending_damage_reports))
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

