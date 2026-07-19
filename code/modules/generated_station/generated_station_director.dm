/datum/generated_station_knowledge_report
	var/id
	var/subject_id
	var/category
	var/details
	var/source_department_id
	var/confidence = 0
	var/created_at = 0
	var/expires_at = 0
	var/datum/weakref/target_ref

/datum/generated_station_knowledge_report/proc/is_expired(at_time = world.time)
	return expires_at > 0 && at_time >= expires_at

/datum/generated_station_squad
	var/id
	var/department_id
	var/list/member_ids
	var/active_order_id

/datum/generated_station_squad/New()
	..()
	member_ids = list()

/datum/generated_station_squad/Destroy()
	member_ids = null
	return ..()

/datum/generated_station_squad/proc/add_member(member_id)
	if(!member_id || (member_id in member_ids) || length(member_ids) >= GENERATED_STATION_MAX_SQUAD_MEMBERS)
		return FALSE
	member_ids += member_id
	return TRUE

/datum/generated_station_order
	var/id
	var/squad_id
	var/report_id
	var/kind
	var/global_coordination = FALSE
	var/state = GENERATED_STATION_ORDER_PENDING
	var/created_at = 0

/// Event-driven strategic state for one station. Producers submit observations
/// and capability changes directly; this layer never discovers state by polling mobs.
/datum/generated_station_director
	var/datum/generated_station_simulation/simulation
	var/alert_level = GENERATED_STATION_ALERT_GREEN
	var/list/local_alert_levels
	var/list/department_connected
	var/list/reports
	var/list/global_knowledge
	var/list/local_knowledge
	var/list/squads
	var/list/orders
	var/list/dirty_departments
	var/strategic_dirty = TRUE
	var/strategic_online = FALSE
	var/next_report_id = 1
	var/next_squad_id = 1
	var/next_order_id = 1
	var/datum/generated_station_defense_runtime/defense_runtime

/datum/generated_station_director/New(datum/generated_station_simulation/new_simulation)
	..()
	simulation = new_simulation
	local_alert_levels = list()
	department_connected = list()
	reports = list()
	global_knowledge = list()
	local_knowledge = list()
	squads = list()
	orders = list()
	dirty_departments = list()
	for(var/department_id in simulation?.departments)
		department_connected[department_id] = TRUE
		local_alert_levels[department_id] = GENERATED_STATION_ALERT_GREEN
		local_knowledge[department_id] = list()
	process_dirty()

/// Narrow integration hook for whichever station runtime owns the dependency
/// simulation. The caller retains ownership of the simulation.
/proc/generated_station_create_director(datum/generated_station_simulation/simulation)
	if(!istype(simulation))
		return null
	return new /datum/generated_station_director(simulation)

/datum/generated_station_director/Destroy()
	defense_runtime = null
	simulation = null
	for(var/id in reports)
		qdel(reports[id])
	for(var/id in squads)
		qdel(squads[id])
	for(var/id in orders)
		qdel(orders[id])
	reports = null
	squads = null
	orders = null
	global_knowledge = null
	local_knowledge = null
	local_alert_levels = null
	department_connected = null
	dirty_departments = null
	return ..()

/datum/generated_station_director/proc/mark_dirty(department_id)
	strategic_dirty = TRUE
	if(department_id)
		dirty_departments[department_id] = TRUE

/datum/generated_station_director/proc/on_capabilities_changed()
	mark_dirty()
	process_dirty()

/datum/generated_station_director/proc/set_department_connected(department_id, connected)
	if(!(department_id in department_connected))
		return FALSE
	connected = !!connected
	if(department_connected[department_id] == connected)
		return TRUE
	department_connected[department_id] = connected
	mark_dirty(department_id)
	process_dirty()
	return TRUE

/datum/generated_station_director/proc/compute_strategic_online()
	if(!simulation)
		return FALSE
	return simulation.department_state("ai-1") != GENERATED_DEPARTMENT_OFFLINE && simulation.capability_available("data") && simulation.capability_available("coordination")

/datum/generated_station_director/proc/process_dirty()
	if(!strategic_dirty)
		return
	strategic_online = compute_strategic_online()
	if(strategic_online)
		for(var/department_id in dirty_departments)
			if(!department_connected[department_id])
				continue
			var/list/knowledge = local_knowledge[department_id]
			for(var/report_id in knowledge)
				var/datum/generated_station_knowledge_report/report = reports[report_id]
				if(report && !report.is_expired())
					propagate_report(report)
	dirty_departments.Cut()
	strategic_dirty = FALSE

/datum/generated_station_director/proc/submit_report(source_department_id, subject_id, category, details, confidence = 50, lifetime = 5 MINUTES)
	if(!(source_department_id in local_knowledge) || !subject_id || !category)
		return null
	var/list/source_knowledge = local_knowledge[source_department_id]
	for(var/existing_report_id in source_knowledge)
		var/datum/generated_station_knowledge_report/existing_report = reports[existing_report_id]
		if(existing_report && !existing_report.is_expired() && existing_report.subject_id == subject_id && existing_report.category == category)
			return existing_report
	var/datum/generated_station_knowledge_report/report = new
	report.id = "report-[next_report_id++]"
	report.subject_id = subject_id
	report.category = category
	report.details = details
	report.source_department_id = source_department_id
	report.confidence = clamp(confidence, 0, 100)
	report.created_at = world.time
	report.expires_at = lifetime > 0 ? world.time + lifetime : 0
	reports[report.id] = report
	source_knowledge[report.id] = report
	process_dirty()
	if(strategic_online && department_connected[source_department_id])
		propagate_report(report)
	if(report.expires_at)
		addtimer(CALLBACK(src, PROC_REF(expire_report), report.id, report.expires_at), lifetime)
	return report

/datum/generated_station_director/proc/propagate_report(datum/generated_station_knowledge_report/report)
	if(!strategic_online || !report || report.is_expired() || !department_connected[report.source_department_id])
		return FALSE
	global_knowledge[report.id] = report
	for(var/department_id in local_knowledge)
		if(department_connected[department_id])
			var/list/knowledge = local_knowledge[department_id]
			knowledge[report.id] = report
	return TRUE

/datum/generated_station_director/proc/expire_report(report_id, expected_expiry)
	var/datum/generated_station_knowledge_report/report = reports[report_id]
	if(!report || report.expires_at != expected_expiry || !report.is_expired())
		return
	global_knowledge -= report_id
	for(var/department_id in local_knowledge)
		var/list/knowledge = local_knowledge[department_id]
		knowledge -= report_id
	reports -= report_id
	qdel(report)

/datum/generated_station_director/proc/department_knows(department_id, report_id)
	var/list/knowledge = local_knowledge[department_id]
	var/datum/generated_station_knowledge_report/report = knowledge?[report_id]
	return report && !report.is_expired()

/datum/generated_station_director/proc/globally_knows(report_id)
	var/datum/generated_station_knowledge_report/report = global_knowledge[report_id]
	return report && !report.is_expired()

/datum/generated_station_director/proc/set_alert(new_level, source_department_id)
	new_level = clamp(new_level, GENERATED_STATION_ALERT_GREEN, GENERATED_STATION_ALERT_DELTA)
	if(source_department_id in local_alert_levels)
		local_alert_levels[source_department_id] = new_level
	process_dirty()
	if(strategic_online && department_connected[source_department_id])
		alert_level = new_level
		for(var/department_id in local_alert_levels)
			if(department_connected[department_id])
				local_alert_levels[department_id] = new_level
		return TRUE
	return FALSE

/datum/generated_station_director/proc/create_squad(department_id)
	if(!(department_id in local_knowledge) || length(squads) >= GENERATED_STATION_MAX_SQUADS)
		return null
	var/datum/generated_station_squad/squad = new
	squad.id = "squad-[next_squad_id++]"
	squad.department_id = department_id
	squads[squad.id] = squad
	return squad

/datum/generated_station_director/proc/issue_order(squad_id, report_id, kind, global_coordination = FALSE)
	var/datum/generated_station_squad/squad = squads[squad_id]
	if(!squad || !kind || squad.active_order_id || length(orders) >= GENERATED_STATION_MAX_ORDERS)
		return null
	if(global_coordination)
		process_dirty()
		if(!strategic_online || !department_connected[squad.department_id] || !globally_knows(report_id))
			return null
	else if(!department_knows(squad.department_id, report_id))
		return null
	var/datum/generated_station_order/order = new
	order.id = "order-[next_order_id++]"
	order.squad_id = squad.id
	order.report_id = report_id
	order.kind = kind
	order.global_coordination = global_coordination
	order.created_at = world.time
	order.state = GENERATED_STATION_ORDER_ACTIVE
	orders[order.id] = order
	squad.active_order_id = order.id
	defense_runtime?.apply_order(order)
	return order

/datum/generated_station_director/proc/complete_order(order_id)
	var/datum/generated_station_order/order = orders[order_id]
	if(!order || order.state != GENERATED_STATION_ORDER_ACTIVE)
		return FALSE
	order.state = GENERATED_STATION_ORDER_COMPLETE
	var/datum/generated_station_squad/squad = squads[order.squad_id]
	if(squad?.active_order_id == order.id)
		squad.active_order_id = null
	orders -= order.id
	qdel(order)
	return TRUE
