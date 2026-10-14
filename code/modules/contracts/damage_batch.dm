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
	owns_many(nameof(contracts_by_id), /datum/contract)
	owns_many(nameof(evidence_by_id), /datum/contract_evidence)
	ref_many(nameof(offered_contracts), /datum/contract)
	ref_many(nameof(active_contracts), /datum/contract)
	ref_many(nameof(grace_contracts), /datum/contract)
	ref_many(nameof(closed_contracts), /datum/contract)
	ref_many(nameof(offer_candidates), /datum/contract_offer_candidate)
	ref_many(nameof(lifecycle_history), /datum/contract_lifecycle_entry)
	ref_many(nameof(recent_events), /datum/contract_event)
	ref_many(nameof(opportunity_history), /datum/contract_opportunity_history_entry)

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
