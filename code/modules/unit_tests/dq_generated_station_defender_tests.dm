/datum/unit_test/dq_generated_station_defender_spawn_is_walkable

/datum/unit_test/dq_generated_station_defender_spawn_is_walkable/Run()
	var/turf/core_turf
	for(var/turf/candidate in world)
		if(!is_blocked_turf(candidate))
			core_turf = candidate
			break
	TEST_ASSERT_NOTNULL(core_turf, "No walkable turf exists for the defender spawn test")
	var/obj/structure/core_blocker = new(core_turf)
	core_blocker.density = TRUE
	var/turf/spawn_turf = generated_station_defender_spawn_turf(core_turf)
	TEST_ASSERT_NOTNULL(spawn_turf, "A dense department core had no adjacent defender spawn")
	TEST_ASSERT(spawn_turf != core_turf, "Defender spawn selected the dense department core")
	TEST_ASSERT(!is_blocked_turf(spawn_turf), "Defender spawn selected a blocked adjacent turf")
	qdel(core_blocker)

/datum/unit_test/dq_generated_station_defense_has_no_idle_loop

/datum/unit_test/dq_generated_station_defense_has_no_idle_loop/Run()
	var/datum/generated_station_planner/planner = new
	var/datum/generated_station_spec/spec = planner.plan(424242)
	var/datum/generated_station_simulation/simulation = new(spec)
	var/datum/generated_station_director/director = new(simulation)
	var/datum/expedition_site/site = new
	site.station_spec = spec
	site.station_simulation = simulation
	site.station_director = director
	var/datum/generated_station_defense_runtime/runtime = new(site, director)
	TEST_ASSERT_EQUAL(length(runtime.active_patrols), 0, "Fresh defense runtime scheduled idle patrol work")
	TEST_ASSERT_EQUAL(length(runtime.agents), 0, "Defense runtime spawned agents before explicit roster creation")
	TEST_ASSERT(director.defense_runtime == runtime, "Director was not bound to its event-driven defense runtime")
	qdel(runtime)
	site.station_director = null
	site.station_simulation = null
	site.station_spec = null
	qdel(site)
	qdel(director)
	qdel(simulation)
	qdel(spec)
	qdel(planner)

/mob/living/simple_mob/generated_station_defender_test_subject
	name = "defender relation test subject"

/datum/unit_test/dq_generated_station_defender_relation_lifetime
	needs_test_block = FALSE

/datum/unit_test/dq_generated_station_defender_relation_lifetime/Run()
	var/turf/spawn_turf = locate(1, 1, 1)
	var/mob/living/simple_mob/generated_station_defender_test_subject/first = new(spawn_turf)
	var/mob/living/simple_mob/generated_station_defender_test_subject/second = new(spawn_turf)
	var/datum/generated_station_defender_agent/agent = new(first, null, "security-1", "squad-1", spawn_turf)
	var/obj/item/first_contact = new(spawn_turf)
	var/obj/item/second_contact = new(spawn_turf)
	TEST_ASSERT(om_has_link(agent, /datum/object_model/relation/generated_station_defender, first), "New agent did not relate to its defender")
	SEND_SIGNAL(first, GENERATED_STATION_DEFENDER_DAMAGE_SIGNAL, 1, INJURY_BLUNT, first_contact)
	TEST_ASSERT(agent.last_contact?.resolve() == first_contact, "Agent did not observe damage to its related defender")
	TEST_ASSERT(om_link(agent, /datum/object_model/relation/generated_station_defender, second), "Agent could not replace its defender")
	TEST_ASSERT(agent.defender == second, "Agent kept the old defender after replacement")
	TEST_ASSERT(!om_has_link(agent, /datum/object_model/relation/generated_station_defender, first), "Old defender relation survived replacement")
	SEND_SIGNAL(first, GENERATED_STATION_DEFENDER_DAMAGE_SIGNAL, 1, INJURY_BLUNT, second_contact)
	TEST_ASSERT(agent.last_contact?.resolve() == first_contact, "Old defender kept sending damage events to the agent")
	SEND_SIGNAL(second, GENERATED_STATION_DEFENDER_DAMAGE_SIGNAL, 1, INJURY_BLUNT, second_contact)
	TEST_ASSERT(agent.last_contact?.resolve() == second_contact, "Replacement defender did not send damage events")
	qdel(second)
	TEST_ASSERT(!agent.defender, "Deleted defender remained in the agent mirror")
	TEST_ASSERT(!length(om_linked(agent, /datum/object_model/relation/generated_station_defender)), "Deleted defender relation survived")
	qdel(agent)
	qdel(first)
	qdel(first_contact)
	qdel(second_contact)
