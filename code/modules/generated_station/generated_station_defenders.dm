/// Event-driven binding between one physical defender and its strategic squad.
/datum/generated_station_defender_agent
	var/tmp/mob/living/simple_mob/defender
	var/tmp/datum/generated_station_defense_runtime/runtime
	var/department_id
	var/squad_id
	var/tmp/turf/home
	/// Relation view: the last hostile that hurt this defender.
	var/atom/last_contact

/datum/generated_station_defender_agent/New(mob/living/simple_mob/new_defender, datum/generated_station_defense_runtime/new_runtime, new_department_id, new_squad_id, turf/new_home)
	..()
	rel_set(src, nameof(defender), new_defender)
	rel_set(src, nameof(runtime), new_runtime)
	department_id = new_department_id
	squad_id = new_squad_id
	rel_set(src, nameof(home), new_home)
	observe(defender(), /datum/notice/dqai_damage_taken, src, then(PROC_REF(on_damage)))
	observe(defender(), /datum/notice/mob_death, src, then(PROC_REF(on_death)))

// its director unregisters the defender.
/datum/generated_station_defender_agent/on_destroy(force)
	if(defender())
		runtime()?.director()?.unregister_defender(defender())
	..()

/// A null or deleted defender must never read as "alive"; `defender?.stat < DEAD`
/// evaluates `null < DEAD` and is TRUE for a missing mob.
/datum/generated_station_defender_agent/proc/is_active()
	return defender() && !QDELETED(defender()) && defender().stat < DEAD

/datum/generated_station_defender_agent/proc/on_damage(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/dqai_damage_taken/event = A
	var/atom/attacker = event.attacker
	if(attacker)
		rel_set(src, nameof(last_contact), attacker)
		runtime()?.report_contact(src, attacker)
	if(defender() && defender().vitality() <= GENERATED_STATION_DEFENDER_RETREAT_HEALTH)
		runtime()?.retreat_agent(src)

/datum/generated_station_defender_agent/proc/on_death(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	runtime()?.on_casualty(src)

/datum/generated_station_defender_agent/proc/apply_order(datum/generated_station_order/order, datum/generated_station_knowledge_report/report)
	if(!is_active())
		return
	var/atom/target = report?.target
	switch(order.kind)
		if(GENERATED_STATION_ORDER_INTERCEPT)
			if(isliving(target))
				var/mob/living/living_target = target
				defender().ai_brain?.give_target(living_target, TRUE)
		if(GENERATED_STATION_ORDER_DEFEND)
			defender().ai_brain?.give_destination(home())
		if(GENERATED_STATION_ORDER_SEARCH, GENERATED_STATION_ORDER_PATROL)
			defender().ai_brain?.give_destination(get_turf(target) || home())
		if(GENERATED_STATION_ORDER_RETREAT)
			runtime().retreat_agent(src)
	defender().ai_brain?.go_wake()

/// Owns the finite generated-station roster. It performs no periodic scans.
/datum/generated_station_defense_runtime
	var/tmp/datum/expedition_site/site
	var/tmp/datum/generated_station_director/director
	var/list/agents
	var/list/squads_by_department
	/// department id -> list(x, y, z) of its control console (coordinates, not turf refs: see department_turf()).
	var/list/department_coords
	var/list/active_patrols
	var/casualties = 0
	var/suppress_sensor_events = FALSE

CAPABILITIES(/datum/generated_station_defense_runtime)
	links(/datum/generated_station_defense_runtime::director, /datum/generated_station_director::defense_runtime)
	owns_many(nameof(agents))

/// Area entry is only an event trigger. A report requires a real powered camera
/// relay in this department to confirm line of sight.
/area/generated_station/Entered(atom/movable/arrived, atom/old_loc)
	. = ..()
	if(!isliving(arrived) || !department_id)
		return
	var/mob/living/entrant = arrived
	if(entrant.faction == GENERATED_STATION_DEFENDER_FACTION)
		return
	for(var/obj/machinery/generated_station_data_relay/relay in contents_of(src))
		if(relay.department_id == department_id && relay.report_hostile(entrant, 85))
			return

/datum/generated_station_defense_runtime/New(datum/expedition_site/new_site, datum/generated_station_director/new_director)
	..()
	rel_set(src, nameof(site), new_site)
	rel_set(src, nameof(director), new_director)
	own_take_all(src, nameof(agents))
	squads_by_department = list()
	department_coords = list()
	active_patrols = list()
	rel_set(director(), nameof(/datum/generated_station_director::defense_runtime), src)

// its director forgets it.


/// The turf of a department's control console, or null when unknown.
/datum/generated_station_defense_runtime/proc/department_turf(department_id)
	var/list/coords = department_coords?[department_id]
	if(length(coords) != 3)
		return null
	return locate(coords[1], coords[2], coords[3])

/datum/generated_station_defense_runtime/proc/create_roster()
	for(var/obj/machinery/generated_station_department_control/control in site().station_controls)
		var/turf/control_turf = get_turf(control)
		if(control_turf)
			department_coords[control.department_id] = list(control_turf.x, control_turf.y, control_turf.z)
	// Relays are tracked by the materialization; never materialise a full-z
	// block() list (and a typed for-loop over turfs would skip every relay anyway).
	for(var/obj/machinery/generated_station_data_relay/relay in site().station_materialization?.infrastructure)
		if(QDELETED(relay))
			continue
		if(relay.station_id == site().station_spec?.id)
			rel_set(relay, nameof(relay.defense_runtime), src)
	spawn_department("security-1", 2)
	spawn_department("medical-1", 1)
	spawn_department("engineering-1", 1)
	spawn_department("logistics-1", 1)

/datum/generated_station_defense_runtime/proc/spawn_department(department_id, count)
	var/turf/spawn_turf = generated_station_defender_spawn_turf(department_turf(department_id))
	if(!spawn_turf)
		return
	var/datum/generated_station_squad/squad = director().create_squad(department_id)
	if(!squad)
		return
	squads_by_department[department_id] = squad.id
	for(var/index in 1 to count)
		spawn_defender(department_id, squad, spawn_turf)

/// Creates one physical defender bound to a squad. Shared by the initial roster
/// and reinforcement so the two paths cannot drift.
/datum/generated_station_defense_runtime/proc/spawn_defender(department_id, datum/generated_station_squad/squad, turf/spawn_turf)
	suppress_sensor_events = TRUE
	var/mob/living/simple_mob/humanoid/merc/ranged/poi/defender = new(spawn_turf)
	suppress_sensor_events = FALSE
	defender.faction = GENERATED_STATION_DEFENDER_FACTION
	defender.ai_attack_on_sight = FALSE
	defender.ai_brain?.set_hostile(FALSE)
	defender.ai_brain?.go_sleep()
	var/datum/generated_station_defender_agent/agent = new(defender, src, department_id, squad.id, spawn_turf)
	rel_add(src, nameof(agents), agent)
	squad.add_member(REF(defender))
	director().register_defender(defender)
	return agent

/// Finds a walkable tile adjacent to the department core. The core itself is dense.
/proc/generated_station_defender_spawn_turf(turf/core_turf)
	if(!core_turf)
		return null
	for(var/turf/candidate in orange(1, core_turf))
		if(candidate.z == core_turf.z && !is_blocked_turf(candidate))
			return candidate
	if(!is_blocked_turf(core_turf))
		return core_turf
	return null

/datum/generated_station_defense_runtime/proc/report_contact(datum/generated_station_defender_agent/observer, atom/contact)
	if(!observer || !contact)
		return
	notify_sensor_contact(observer.department_id, contact, "defender", 100)

/// Cameras, relays, doors, and other event producers call this directly. Detection
/// remains local if data or AI coordination is unavailable.
/datum/generated_station_defense_runtime/proc/notify_sensor_contact(department_id, atom/contact, source_kind = "sensor", confidence = 80, issue_response = TRUE)
	if(!contact || !director() || !(department_id in director().local_knowledge))
		return null
	var/datum/generated_station_knowledge_report/report = director().submit_report(department_id, REF(contact), "hostile-contact", "[source_kind] detected a hostile.", confidence, GENERATED_STATION_CONTACT_LIFETIME)
	if(!report)
		return null
	rel_set(report, nameof(report.target), contact)
	director().set_alert(GENERATED_STATION_ALERT_RED, department_id)
	if(issue_response)
		var/coordinated = director().ai_can_coordinate()
		var/squad_id = coordinated ? squads_by_department["security-1"] : squads_by_department[department_id]
		if(squad_id)
			director().issue_order(squad_id, report.id, GENERATED_STATION_ORDER_INTERCEPT, coordinated)
	after(src, GENERATED_STATION_CONTACT_LIFETIME, PROC_REF(contact_expired), with = list(report.id, department_id))
	return report

/datum/generated_station_defense_runtime/proc/contact_expired(report_id, department_id)
	if(!director() || QDELETED(src))
		return
	if(director().reports?[report_id])
		return
	director().set_alert(GENERATED_STATION_ALERT_BLUE, department_id)
	after(src, GENERATED_STATION_SEARCH_DURATION, PROC_REF(return_to_green), with = list(department_id))

/datum/generated_station_defense_runtime/proc/return_to_green(department_id)
	if(director()?.local_alert_levels?[department_id] == GENERATED_STATION_ALERT_BLUE)
		director().set_alert(GENERATED_STATION_ALERT_GREEN, department_id)

/// Door controllers call this only after a denied or forced transition, avoiding
/// any scan of idle doors.
/datum/generated_station_defense_runtime/proc/notify_department_breach(department_id, atom/breach)
	var/datum/generated_station_knowledge_report/report = notify_sensor_contact(department_id, breach, "access controller", 90, FALSE)
	if(!report)
		return FALSE
	var/squad_id = squads_by_department[department_id] || squads_by_department["security-1"]
	if(squad_id)
		director().issue_order(squad_id, report.id, GENERATED_STATION_ORDER_DEFEND, FALSE)
	return TRUE

/datum/generated_station_defense_runtime/proc/apply_order(datum/generated_station_order/order)
	var/datum/generated_station_squad/squad = director().squads?[order.squad_id]
	var/datum/generated_station_knowledge_report/report = director().reports?[order.report_id]
	for(var/datum/generated_station_defender_agent/agent in agents)
		if(agent.squad_id == squad?.id)
			agent.apply_order(order, report)
	after(src, order.kind == GENERATED_STATION_ORDER_PATROL ? GENERATED_STATION_PATROL_DURATION : GENERATED_STATION_SEARCH_DURATION, PROC_REF(finish_order), with = list(order.id))

/datum/generated_station_defense_runtime/proc/finish_order(order_id)
	var/datum/generated_station_order/order = director()?.orders?[order_id]
	if(!order)
		return
	var/datum/generated_station_squad/squad = director().squads?[order.squad_id]
	director().complete_order(order.id)
	sleep_squad(squad?.id)

/// Puts every living member of a squad back to sleep after a bounded job.
/datum/generated_station_defense_runtime/proc/sleep_squad(squad_id)
	if(!squad_id)
		return
	for(var/datum/generated_station_defender_agent/agent in agents)
		if(agent.squad_id == squad_id && agent.is_active())
			agent.defender().ai_brain?.go_sleep()

/// Patrols are explicitly requested and self-terminate; stable stations schedule none.
/datum/generated_station_defense_runtime/proc/request_patrol(department_id, turf/destination)
	var/squad_id = squads_by_department[department_id]
	if(!squad_id || active_patrols[squad_id])
		return FALSE
	var/datum/generated_station_knowledge_report/report = director().submit_report(department_id, "patrol-[world.time]", "patrol", "Finite patrol route.", 100, GENERATED_STATION_PATROL_DURATION)
	if(!report)
		return FALSE
	rel_set(report, nameof(report.target), destination || department_turf(department_id))
	var/datum/generated_station_order/order = director().issue_order(squad_id, report.id, GENERATED_STATION_ORDER_PATROL, FALSE)
	if(!order)
		return FALSE
	active_patrols[squad_id] = order.id
	after(src, GENERATED_STATION_PATROL_DURATION, PROC_REF(clear_patrol), with = list(squad_id, order.id))
	return TRUE

/datum/generated_station_defense_runtime/proc/clear_patrol(squad_id, order_id)
	if(active_patrols?[squad_id] == order_id)
		active_patrols -= squad_id

/// A dead defender leaves the roster entirely: its agent is dropped from `agents`
/// and its squad membership released, so reinforcement is not locked out by
/// corpses still counting against GENERATED_STATION_MAX_SQUAD_MEMBERS.
/datum/generated_station_defense_runtime/proc/on_casualty(datum/generated_station_defender_agent/agent)
	if(!agent || QDELETED(agent))
		return
	casualties++
	var/department_id = agent.department_id
	var/datum/generated_station_squad/squad = director()?.squads?[agent.squad_id]
	if(squad && agent.defender())
		squad.member_ids -= REF(agent.defender())
	director()?.unregister_defender(agent.defender())
	own_take_member(src, nameof(agents), agent)
	spent(agent)
	if(department_id == "security-1" && director()?.request_security_reserve())
		after(src, 10 SECONDS, PROC_REF(spawn_reinforcement), with = list("security-1"))

/datum/generated_station_defense_runtime/proc/spawn_reinforcement(department_id)
	if(!director() || QDELETED(src))
		return FALSE
	var/turf/spawn_turf = generated_station_defender_spawn_turf(department_turf(department_id))
	var/squad_id = squads_by_department[department_id]
	var/datum/generated_station_squad/squad = director().squads?[squad_id]
	if(!spawn_turf || !squad || length(squad.member_ids) >= GENERATED_STATION_MAX_SQUAD_MEMBERS)
		return FALSE
	spawn_defender(department_id, squad, spawn_turf)
	return TRUE

/// Damage producers call this with the affected department. Engineering consumes
/// finite stockpiles and performs one delayed repair without polling structures.
/datum/generated_station_defense_runtime/proc/request_engineering_repair(department_id, amount = 20)
	for(var/obj/machinery/generated_station_department_control/control in site().station_controls)
		if(control.department_id == department_id)
			return request_physical_repair(control, amount)
	return FALSE

/datum/generated_station_defense_runtime/proc/retreat_agent(datum/generated_station_defender_agent/agent)
	if(!agent?.is_active())
		return
	var/turf/medical = department_turf("medical-1") || agent.home()
	agent.defender().ai_brain?.give_destination(medical)
	agent.defender().ai_brain?.go_wake()
	after(src, 5 SECONDS, PROC_REF(heal_and_redeploy), key = "redeploy:[REF(agent)]", with = list(agent))

/// after() holds `agent` as a handle: the call is dropped if the agent is gone.
/datum/generated_station_defense_runtime/proc/heal_and_redeploy(datum/generated_station_defender_agent/agent)
	if(!agent?.is_active())
		return
	var/obj/item/stack/medical/medicine
	var/area/medical_area = get_area(department_turf("medical-1"))
	for(var/obj/item/stack/medical/candidate in area_contents_of_type(medical_area, /obj/item/stack/medical))
		if(candidate.amount > 0)
			medicine = candidate
			break
	if(!medicine || !medicine.use(1))
		agent.defender().ai_brain?.go_sleep()
		return
	agent.defender().mend(TREAT_TISSUE_REPAIR, 30)
	agent.defender().mend(TREAT_BURN_CARE, 30)
	agent.defender().mend(TREAT_PLATING_REPAIR, 30)
	agent.defender().mend(TREAT_WIRING_REPAIR, 30)
	var/atom/contact = agent.last_contact
	if(isliving(contact))
		var/mob/living/living_contact = contact
		agent.defender().ai_brain?.give_target(living_contact, TRUE)
	else
		agent.defender().ai_brain?.give_destination(agent.home())
	agent.defender().ai_brain?.go_wake()

/// Dispatches Engineering to a damaged physical object and consumes tangible
/// repair material after revalidating the target at arrival.
/datum/generated_station_defense_runtime/proc/request_physical_repair(atom/target, amount = 20)
	if(!target || !target.max_integrity || target.get_integrity() >= target.max_integrity)
		return FALSE
	var/squad_id = squads_by_department["engineering-1"]
	if(!squad_id)
		return FALSE
	for(var/datum/generated_station_defender_agent/agent in agents)
		if(agent.squad_id == squad_id && agent.is_active())
			agent.defender().ai_brain?.give_destination(get_turf(target))
			agent.defender().ai_brain?.go_wake()
	after(src, 5 SECONDS, PROC_REF(complete_physical_repair), with = list(target, amount, squad_id))
	return TRUE

/datum/generated_station_defense_runtime/proc/complete_physical_repair(atom/target, amount, squad_id)
	if(!target || QDELETED(target) || target.get_integrity() >= target.max_integrity)
		return
	var/obj/item/stack/material/materials
	var/area/engineering_area = get_area(department_turf("engineering-1"))
	for(var/obj/item/stack/material/candidate in area_contents_of_type(engineering_area, /obj/item/stack/material))
		if(candidate.amount > 0)
			materials = candidate
			break
	if(!materials || !materials.use(1))
		return
	target.repair_damage(amount)
	sleep_squad(squad_id)

/// Moves an actual crate through a bounded delivery job.
/datum/generated_station_defense_runtime/proc/request_logistics_delivery(obj/structure/closet/crate/crate, turf/destination)
	if(!crate || !destination)
		return FALSE
	var/squad_id = squads_by_department["logistics-1"]
	if(!squad_id)
		return FALSE
	for(var/datum/generated_station_defender_agent/agent in agents)
		if(agent.squad_id == squad_id && agent.is_active())
			agent.defender().ai_brain?.give_destination(get_turf(crate))
			agent.defender().ai_brain?.go_wake()
	after(src, 5 SECONDS, PROC_REF(complete_logistics_delivery), with = list(crate, destination, squad_id))
	return TRUE

/// after() drops the call when the crate is gone (the squad then sleeps on its own order timer).
/datum/generated_station_defense_runtime/proc/complete_logistics_delivery(obj/structure/closet/crate/crate, turf/destination, squad_id)
	if(crate && destination && !QDELETED(crate) && !is_blocked_turf(destination))
		crate.forceMove(destination)
	sleep_squad(squad_id)

/datum/expedition_site
	var/datum/generated_station_defense_runtime/station_defense

/datum/expedition_site/proc/initialize_generated_station_defenders()
	if(!station_director || station_defense)
		return FALSE
	rel_set(src, nameof(station_defense), new /datum/generated_station_defense_runtime(src, station_director))
	station_defense.create_roster()
	return TRUE


/// Accessor for the defender var.
/datum/generated_station_defender_agent/proc/defender() as /mob/living/simple_mob
	return defender

/// Accessor for the runtime var.
/datum/generated_station_defender_agent/proc/runtime() as /datum/generated_station_defense_runtime
	return runtime

/// Accessor for the home var.
/datum/generated_station_defender_agent/proc/home() as /turf
	return home

/// Accessor for the site var.
/datum/generated_station_defense_runtime/proc/site() as /datum/expedition_site
	return site

/// Accessor for the director var.
/datum/generated_station_defense_runtime/proc/director() as /datum/generated_station_director
	return director




/// Its defenders go with it, before phase 4 deletes the agents that name them.
/datum/generated_station_defense_runtime/lifecycle_prerelease()
	for(var/datum/generated_station_defender_agent/agent in agents)
		var/mob/living/defender = agent.defender()
		if(defender && !QDELETED(defender))
			spent(defender)
	return ..()
