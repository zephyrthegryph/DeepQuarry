/datum/unit_test/dq_generated_station_objectives_follow_department_state

/datum/unit_test/dq_generated_station_objectives_follow_department_state/Run()
	var/datum/generated_station_planner/planner = new
	var/datum/generated_station_spec/spec = planner.plan(5150)
	var/datum/expedition_site/site = new(world.maxz, EXP_DIFF_MED)
	site.station_spec = spec
	site.station_simulation = new(spec)
	site.station_controls = list()
	for(var/datum/generated_station_department_instance/department in spec.departments)
		var/obj/machinery/generated_station_department_control/control = new(null)
		control.station_id = spec.id
		control.department_id = department.id
		site.station_controls += control
	var/datum/expedition_mission/station_assault/mission = new(EXP_DIFF_MED)
	site.mission = mission
	mission.populate(site)
	TEST_ASSERT(mission.has_viable_objectives(), "Station assault did not bind required objectives to department controls")

	site.station_simulation.set_integrity("command-1", 0)
	site.station_simulation.set_integrity("security-1", 0)
	for(var/obj/machinery/generated_station_department_control/control in site.station_controls)
		if(control.department_id == "ai-1")
			control.captured = TRUE
	for(var/datum/expedition_objective/objective in mission.objectives)
		objective.check()
	for(var/datum/expedition_objective/objective in mission.objectives)
		objective.check()

	var/list/rows = mission.objective_rows()
	TEST_ASSERT_EQUAL(length(rows), 8, "Station assault did not expose its strategic and physical objective rows")
	var/datum/expedition_objective/command_objective = mission.objectives[1]
	var/datum/expedition_objective/security_objective = mission.objectives[2]
	TEST_ASSERT_EQUAL(command_objective.state, EXP_OBJ_COMPLETE, "Command objective ignored authoritative offline state")
	TEST_ASSERT_EQUAL(security_objective.state, EXP_OBJ_COMPLETE, "Security objective ignored authoritative offline state")
	var/capture_complete = FALSE
	var/preserve_complete = FALSE
	for(var/datum/expedition_objective/objective in mission.objectives)
		if(istype(objective, /datum/expedition_objective/generated_department/capture_ai))
			capture_complete = objective.state == EXP_OBJ_COMPLETE
		else if(istype(objective, /datum/expedition_objective/generated_department/preserve_engineering))
			preserve_complete = objective.state == EXP_OBJ_COMPLETE
	TEST_ASSERT(capture_complete, "Captured operational AI did not complete capture objective")
	TEST_ASSERT(preserve_complete, "Operational Engineering did not complete preserve objective")

	for(var/obj/machinery/generated_station_department_control/control in site.station_controls)
		qdel(control)
	qdel(site)
	qdel(planner)

/datum/unit_test/dq_generated_station_preserve_fails_when_disabled

/datum/unit_test/dq_generated_station_preserve_fails_when_disabled/Run()
	var/datum/generated_station_planner/planner = new
	var/datum/generated_station_spec/spec = planner.plan(6160)
	var/datum/expedition_site/site = new(world.maxz, EXP_DIFF_MED)
	site.station_spec = spec
	site.station_simulation = new(spec)
	var/obj/machinery/generated_station_department_control/control = new(null)
	control.station_id = spec.id
	control.department_id = "engineering-1"
	site.station_controls = list(control)
	var/datum/expedition_objective/generated_department/preserve_engineering/objective = new(FALSE)
	objective.populate(site)
	site.station_simulation.set_integrity("engineering-1", 0)
	TEST_ASSERT_EQUAL(objective.check(), EXP_OBJ_FAILED, "Preserve objective did not fail when its department went offline")
	qdel(objective)
	qdel(control)
	qdel(site)
	qdel(planner)
