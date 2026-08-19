/// An immutable snapshot of one gameplay fact that contracts may use as
/// evidence. Atom references are diagnostic only; matching uses copied stable
/// identities and scalar metadata so deletion, cloning, or resleeving cannot
/// silently change what was reported.
/datum/contract_event
	var/id
	var/event_type
	var/occurred_at
	var/occurrence_id
	/// Stable identity and monotonic revision for gameplay facts that can be
	/// corrected (for example, a paid invoice becoming refunded).
	var/fact_id
	var/fact_revision = 0
	var/fact_active = TRUE
	var/actor_account
	var/actor_name
	var/actor_department
	var/subject_id
	var/subject_name
	var/contract_id
	var/department
	var/source_ref
	var/source_type
	var/location_ref
	var/area_name
	var/x = 0
	var/y = 0
	var/z = 0
	var/list/tags
	var/list/metrics
	var/list/evidence_ids
	var/list/data

/proc/contract_account_for_mob(mob/living/actor) as /datum/money_account
	var/obj/item/card/id/id_card = actor?.GetIdCard()
	return id_card ? get_account(id_card.associated_account_number) : actor?.mind?.initial_account

/datum/contract_event/New(_event_type, atom/source, mob/living/actor, mob/living/subject, list/context, _occurrence_id)
	. = ..()
	event_type = _event_type
	occurred_at = world.time
	occurrence_id = _occurrence_id
	data = context ? deepCopyList(context) : list()
	fact_id = data["fact_id"] || occurrence_id
	fact_revision = data["fact_revision"] || 0
	if(!isnull(data["fact_active"]))
		fact_active = !!data["fact_active"]
	var/list/context_tags = data["tags"]
	var/list/context_metrics = data["metrics"]
	var/list/context_evidence_ids = data["evidence_ids"]
	tags = context_tags ? deepCopyList(context_tags) : list()
	metrics = context_metrics ? deepCopyList(context_metrics) : list()
	evidence_ids = context_evidence_ids ? deepCopyList(context_evidence_ids) : list()
	actor_account = data["actor_account"] || data["contributor_account"]
	actor_name = data["actor_name"]
	actor_department = data["actor_department"]
	subject_id = data["subject_id"] || data["subject_ref"]
	subject_name = data["subject_name"]
	contract_id = data["contract_id"]
	department = data["department"]
	if(actor)
		var/datum/money_account/account = contract_account_for_mob(actor)
		actor_account ||= account?.account_number
		actor_name ||= actor.real_name
		actor_department ||= department_for_mob(actor)
	if(subject)
		var/datum/contract_subject_identity/identity = SScontracts?.subject_identity(subject)
		subject_id ||= identity?.id
		subject_name ||= subject.real_name
	if(source)
		source_ref = REF(source)
		source_type = source.type
		var/turf/source_turf = get_turf(source)
		if(source_turf)
			location_ref = REF(source_turf)
			x = source_turf.x
			y = source_turf.y
			z = source_turf.z
			var/area/source_area = get_area(source_turf)
			area_name = source_area?.name

/datum/contract_event/Destroy()
	tags = null
	metrics = null
	evidence_ids = null
	data = null
	return ..()

/proc/contract_event_schema(event_type)
	var/static/list/schemas = list(
		CONTRACT_EVENT_EVIDENCE_REGISTERED = list(
			"required" = list("evidence_kind", "evidence_ids"),
			"lists" = list("evidence_ids"),
		),
		CONTRACT_EVENT_EVIDENCE_CONSUMED = list(
			"required" = list("contract_id", "evidence_ids", "evidence_count"),
			"numeric" = list("evidence_count"),
			"lists" = list("evidence_ids"),
		),
		CONTRACT_EVENT_DOCUMENT_CREATED = list(
			"required" = list("contract_id", "document_kind", "destination", "evidence_ids"),
			"lists" = list("evidence_ids"),
		),
		CONTRACT_EVENT_DOCUMENT_SIGNED = list(
			"required" = list("contract_id", "subject_id", "document_kind", "destination", "evidence_ids"),
			"lists" = list("evidence_ids"),
		),
		CONTRACT_EVENT_FAX_ACCEPTED = list(
			"required" = list("destination"),
		),
		CONTRACT_EVENT_MEDICAL_SCAN_CREATED = list(
			"required" = list("subject_id", "evidence_ids", "scan_time"),
			"numeric" = list("scan_time"),
			"lists" = list("evidence_ids"),
		),
		CONTRACT_EVENT_MEDICAL_OBSERVATION_ACCEPTED = list(
			"required" = list("contract_id", "subject_id", "department"),
		),
		CONTRACT_EVENT_MEDICAL_ANALYSIS_ACCEPTED = list(
			"required" = list("contract_id", "department", "target_metric", "adverse_metric"),
		),
		CONTRACT_EVENT_RARE_CASE_ACCEPTED = list(
			"required" = list("contract_id", "subject_id", "department"),
		),
		CONTRACT_EVENT_CONTRACT_ACTION_ACCEPTED = list(
			"required" = list("contract_id", "action_key"),
		),
		CONTRACT_EVENT_SHIPMENT_DEPARTED = list(
			"required" = list("shipment_ref", "shipment_name"),
		),
		CONTRACT_EVENT_ITEM_EXPORTED = list(
			"required" = list("fact_id", "fact_revision", "item_type", "handling_department", "value"),
			"numeric" = list("fact_revision", "quantity", "value"),
		),
		CONTRACT_EVENT_SERVICE_INVOICE_CHANGED = list(
			"required" = list("department", "provider_account", "invoice_id", "fact_id", "fact_revision", "amount"),
			"numeric" = list("provider_account", "invoice_id", "fact_revision", "amount", "tip"),
		),
		CONTRACT_EVENT_SERVICE_PERIOD_SETTLED = list(
			"required" = list("department", "rollup", "accounting_period", "fact_id", "fact_revision", "amount", "customer_count"),
			"numeric" = list("accounting_period", "fact_revision", "amount", "customer_count", "verified_amount", "verified_item_count", "verified_type_count"),
		),
		CONTRACT_EVENT_MONEY_TRANSFERRED = list(
			"required" = list("source_account", "target_account", "amount"),
			"numeric" = list("source_account", "target_account", "amount"),
		),
		CONTRACT_EVENT_BUDGET_ALLOCATION_CHANGED = list(
			"required" = list("department", "target_department", "target_account", "target_is_department", "amount"),
			"numeric" = list("target_account", "amount"),
		),
		CONTRACT_EVENT_BUDGET_CYCLE_SETTLED = list(
			"required" = list("rollup", "accounting_period", "fact_id", "fact_revision", "funded_allocation_total", "funded_department_count", "payroll_coverage"),
			"numeric" = list("accounting_period", "fact_revision", "funded_allocation_total", "funded_department_count", "payroll_coverage"),
		),
		CONTRACT_EVENT_MACHINE_RESULT = list(
			"required" = list("machine_kind", "machine_id", "station_machine", "eer", "integrity"),
			"numeric" = list("eer", "integrity"),
		),
		CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED = list(
			"required" = list("subject_id", "physical_subject_id", "record_id", "disposition", "physical_custody_verified", "fact_id", "fact_revision", "custody_duration"),
			"numeric" = list("fact_revision", "custody_duration"),
		),
		CONTRACT_EVENT_CUSTODY_CHANGED = list(
			"required" = list("subject_id", "fact_id", "fact_revision", "custody_duration"),
			"numeric" = list("fact_revision", "custody_duration"),
		),
		CONTRACT_EVENT_ITEM_PRODUCED = list(
			"required" = list("fact_id", "fact_revision", "item_type", "department", "value"),
			"numeric" = list("fact_revision", "value"),
		),
		CONTRACT_EVENT_MATERIAL_PROCESSED = list(
			"required" = list("department", "process", "fingerprint", "amount"),
			"numeric" = list("amount", "purity", "hardness", "toughness", "brittleness", "conductivity", "heat_resistance", "corrosion_resistance", "composition_count", "yield", "energy_cost", "production_cost", "defect_fraction", "oxidation"),
		),
		CONTRACT_EVENT_MATERIAL_CERTIFIED = list(
			"required" = list("department", "fingerprint", "purity", "hardness", "toughness"),
			"numeric" = list("amount", "purity", "hardness", "toughness", "brittleness", "conductivity", "heat_resistance", "corrosion_resistance", "composition_count", "yield", "energy_cost", "production_cost", "defect_fraction", "oxidation"),
		),
		CONTRACT_EVENT_SUPPLY_ORDER_FULFILLED = list(
			"required" = list("fact_id", "fact_revision", "order_id", "pack_type", "funding_department", "value"),
			"numeric" = list("fact_revision", "order_id", "value"),
		),
		CONTRACT_EVENT_INFRASTRUCTURE_DAMAGED = list(
			"required" = list("fact_id", "fact_revision", "atom_id", "damage_amount", "integrity", "maximum_integrity"),
			"numeric" = list("fact_revision", "damage_amount", "integrity", "maximum_integrity"),
		),
		CONTRACT_EVENT_INFRASTRUCTURE_REPAIRED = list(
			"required" = list("atom_id", "repair_amount", "integrity", "maximum_integrity"),
			"numeric" = list("repair_amount", "integrity", "maximum_integrity"),
		),
		CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME = list(
			"required" = list("subject_id", "condition_type", "improvement"),
			"numeric" = list("improvement", "initial_severity", "final_severity"),
		),
		CONTRACT_EVENT_SUPPLY_SHORTAGE_DECLARED = list(
			"required" = list("shortage_id", "quantity_target", "variety_target"),
			"numeric" = list("quantity_target", "variety_target"),
		),
		CONTRACT_EVENT_SUPPLY_SHORTAGE_DELIVERY = list(
			"required" = list("shortage_id", "item_type", "item_name", "quantity"),
			"numeric" = list("quantity"),
		),
		CONTRACT_EVENT_STAKEHOLDER_APPROVED = list(
			"required" = list("contract_id", "actor_account", "role_id", "requested_weight"),
			"numeric" = list("actor_account", "requested_weight"),
		),
		CONTRACT_EVENT_POWER_SERVICE_CHANGED = list(
			"required" = list("fact_id", "fact_revision", "service_id", "powered_channels", "operational"),
			"numeric" = list("fact_revision", "powered_channels", "cell_percent", "load", "operational"),
		),
		CONTRACT_EVENT_ATMOS_SERVICE_CHANGED = list(
			"required" = list("fact_id", "fact_revision", "service_id", "danger_level", "pressure", "temperature"),
			"numeric" = list("fact_revision", "danger_level", "pressure", "temperature"),
		),
		CONTRACT_EVENT_BLOOD_DONATED = list(
			"required" = list("subject_id", "container_id", "blood_type", "amount"),
			"numeric" = list("amount"),
		),
		CONTRACT_EVENT_RESEARCH_MILESTONE = list(
			"required" = list("node_id", "node_name", "point_cost", "design_count"),
			"numeric" = list("point_cost", "design_count"),
		),
		CONTRACT_EVENT_CHEMISTRY_RESULT = list(
			"required" = list("reaction_id", "product_id", "amount", "reactant_count"),
			"numeric" = list("amount", "reactant_count"),
		),
		CONTRACT_EVENT_FOOD_CONSUMED = list(
			"required" = list("subject_id", "item_type", "food_kind", "portion"),
			"numeric" = list("portion", "finished"),
		),
		CONTRACT_EVENT_CROP_HARVESTED = list(
			"required" = list("crop_id", "crop_name", "yield", "potency"),
			"numeric" = list("yield", "potency"),
		),
		CONTRACT_EVENT_SANITATION_COMPLETED = list(
			"required" = list("target_id", "method", "cleaned_units"),
			"numeric" = list("cleaned_units"),
		),
		CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED = list(
			"required" = list("bot_id", "task_kind", "target_id", "successful"),
			"numeric" = list("successful", "work_units"),
		),
		CONTRACT_EVENT_CARGO_MARKET_PURCHASE = list(
			"required" = list("fact_id", "fact_revision", "counterparty_id", "faction_id", "listing_id", "order_id", "pack_type", "value"),
			"numeric" = list("fact_revision", "order_id", "value", "quantity"),
		),
		CONTRACT_EVENT_CARGO_MARKET_EXPORT = list(
			"required" = list("fact_id", "fact_revision", "counterparty_id", "faction_id", "bid_id", "profile_id", "item_type", "value", "quantity"),
			"numeric" = list("fact_revision", "value", "premium", "quantity"),
		),
		CONTRACT_EVENT_COVERT_MARKET_ACTIVITY = list(
			"required" = list("fact_id", "fact_revision", "principal_account", "faction_id", "transaction_id", "exposure", "increase"),
			"numeric" = list("fact_revision", "principal_account", "exposure", "increase"),
		),
		CONTRACT_EVENT_COVERT_MARKET_AUDIT = list(
			"required" = list("suspect_account", "transaction_id", "detected"),
			"numeric" = list("suspect_account"),
		),
	)
	return schemas[event_type]

/datum/contract_event/proc/is_valid()
	if(!istext(event_type) || !length(event_type))
		return FALSE
	var/list/schema = contract_event_schema(event_type)
	if(!schema)
		// Third-party and test contract definitions remain extensible. Known
		// authoritative event types receive strict producer-schema validation.
		return TRUE
	for(var/key in schema["required"])
		if(isnull(value(key)))
			return FALSE
	for(var/key in schema["numeric"])
		var/measurement = value(key)
		if(!isnull(measurement) && !isnum(measurement))
			return FALSE
	for(var/key in schema["lists"])
		if(!islist(value(key)))
			return FALSE
	if(("fact_revision" in schema["required"]) && fact_revision < 1)
		return FALSE
	return TRUE

/// Resolve a declarative requirement field. Stable first-class fields win over
/// caller data, and numeric measurements live in their own namespace.
/datum/contract_event/proc/value(key)
	switch(key)
		if("id")
			return id
		if("event_type")
			return event_type
		if("occurred_at")
			return occurred_at
		if("occurrence_id")
			return occurrence_id
		if("fact_id")
			return fact_id
		if("fact_revision")
			return fact_revision
		if("fact_active")
			return fact_active
		if("actor_account", "contributor_account")
			return actor_account
		if("actor_name")
			return actor_name
		if("actor_department")
			return actor_department
		if("subject_id", "subject_ref")
			return subject_id
		if("subject_name")
			return subject_name
		if("contract_id")
			return contract_id
		if("department")
			return department
		if("source_ref")
			return source_ref
		if("source_type")
			return source_type
		if("location_ref")
			return location_ref
		if("area_name")
			return area_name
		if("x")
			return x
		if("y")
			return y
		if("z")
			return z
	if(key in metrics)
		return metrics[key]
	return data[key]

/datum/contract_event/proc/summary()
	var/source_description = source_type ? "[source_type]" : "system"
	return "[id || "unpublished"] [event_type] from [actor_name || actor_account || source_description]"

/// Preferred producer API. occurrence_id should identify the underlying fact,
/// not the callback invocation, when a signal can be delivered more than once.
/proc/emit_contract_event(event_type, list/context, occurrence_id, atom/source, mob/living/actor, mob/living/subject)
	var/datum/contract_event/event = new(event_type, source, actor, subject, context, occurrence_id)
	return SScontracts?.publish_event(event)
