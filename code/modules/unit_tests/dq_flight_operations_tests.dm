/datum/unit_test/dq_flight_plan_owns_destination_lease

/datum/unit_test/dq_flight_plan_owns_destination_lease/Run()
	var/obj/effect/target = new(null)
	var/datum/flight_destination/destination = new
	destination.id = "unit-test-destination"
	destination.name = "Unit Test Destination"
	destination.target = target
	destination.required_capabilities = FLIGHT_CAP_STRATEGIC
	var/datum/flight_vessel/vessel = new
	vessel.name = "Unit Test Vessel"
	vessel.capabilities = FLIGHT_CAP_STRATEGIC
	var/datum/flight_plan/plan = new(vessel, null, destination)
	vessel.active_plan = plan
	TEST_ASSERT(plan in destination.active_plans, "A new flight plan did not lease its destination")
	TEST_ASSERT(plan.start(), "A compatible strategic flight plan refused to start")
	TEST_ASSERT_EQUAL(plan.state, FLIGHT_PLAN_PREPARING, "Starting a flight plan did not enter PREPARING")
	qdel(plan)
	TEST_ASSERT(!LAZYLEN(destination.active_plans), "Deleting a flight plan left a stale destination lease")
	qdel(vessel)
	qdel(destination)
	qdel(target)

/datum/unit_test/dq_expedition_is_metadata_until_departure

/datum/unit_test/dq_expedition_is_metadata_until_departure/Run()
	var/datum/expedition_mission/mission = new /datum/expedition_mission/survey(EXP_DIFF_LOW)
	var/datum/expedition_site/site = SSexpedition.create_site_descriptor(mission, EXP_DIFF_LOW)
	TEST_ASSERT_NOTNULL(site, "Expedition survey did not create a site descriptor")
	TEST_ASSERT_EQUAL(site.z_level, 0, "Surveying an expedition allocated a physical z-level before departure")
	TEST_ASSERT_NULL(site.landing, "Surveying an expedition created a landing turf before departure")
	TEST_ASSERT_NULL(site.overmap_sector, "Surveying an expedition created a legacy overmap sector before departure")
	TEST_ASSERT_NOTNULL(site.flight_destination_id, "Surveying an expedition did not register a stable flight destination")
	var/datum/flight_destination/destination = SSflight_operations.destinations[site.flight_destination_id]
	TEST_ASSERT(destination?.expedition == site, "The flight destination did not retain the surveyed site descriptor")
	SSflight_operations.unregister_destination(site.flight_destination_id)
	qdel(site)

/datum/unit_test/dq_incompatible_flight_plan_fails_closed

/datum/unit_test/dq_incompatible_flight_plan_fails_closed/Run()
	var/obj/effect/target = new(null)
	var/datum/flight_destination/destination = new
	destination.name = "Surface Site"
	destination.target = target
	destination.required_capabilities = FLIGHT_CAP_LAND
	var/datum/flight_vessel/vessel = new
	vessel.capabilities = FLIGHT_CAP_STRATEGIC
	var/datum/flight_plan/plan = new(vessel, null, destination)
	TEST_ASSERT(!plan.start(), "A vessel without landing capability started a surface flight plan")
	TEST_ASSERT_EQUAL(plan.state, FLIGHT_PLAN_FAILED, "An incompatible flight plan did not fail closed")
	qdel(plan)
	qdel(vessel)
	qdel(destination)
	qdel(target)

/datum/unit_test/dq_flight_ui_includes_nontravelable_system_root

/datum/unit_test/dq_flight_ui_includes_nontravelable_system_root/Run()
	var/datum/flight_vessel/vessel = new
	vessel.capabilities = FLIGHT_CAP_STRATEGIC
	var/datum/flight_operations_ui/flight_ui = new(src, vessel)
	var/list/data = flight_ui.tgui_data(null)
	var/found_system = FALSE
	for(var/list/destination in data["destinations"])
		if(destination["kind"] == FLIGHT_DEST_SYSTEM)
			found_system = TRUE
			break
	TEST_ASSERT(found_system, "Flight Operations omitted its non-travelable system root from render data")
	qdel(flight_ui)
	qdel(vessel)

/datum/unit_test/dq_flight_registry_has_single_authored_planet

/datum/unit_test/dq_flight_registry_has_single_authored_planet/Run()
	TEST_ASSERT_NOTNULL(SSflight_operations.planet_id_named("Sif"), "Flight registry omitted Sif")
	TEST_ASSERT_NULL(SSflight_operations.planet_id_named("Kara"), "Removed Kara remains in the flight registry")

/datum/unit_test/dq_live_carrier_independently_orbits_sif

/datum/unit_test/dq_live_carrier_independently_orbits_sif/Run()
	if(using_map?.name != "Southern Cross")
		return
	var/carrier_id = SSflight_operations.destination_id_named("Exploration Carrier")
	var/datum/flight_destination/carrier = SSflight_operations.destinations[carrier_id]
	TEST_ASSERT_NOTNULL(carrier, "Flight registry omitted the Exploration Carrier")
	TEST_ASSERT_EQUAL(carrier.orbit_parent_id, SSflight_operations.planet_id_named("Sif"), "The carrier does not independently orbit Sif")
	var/obj/effect/overmap/visitable/ship/carrier_ship = carrier.target
	var/datum/flight_vessel/carrier_vessel = SSflight_operations.vessel_for_ship(carrier_ship)
	TEST_ASSERT_NULL(carrier_vessel?.docked_port_id, "The carrier was incorrectly registered as docked to another destination")

/datum/unit_test/dq_live_flight_payload_preserves_carrier_hierarchy

/datum/unit_test/dq_live_flight_payload_preserves_carrier_hierarchy/Run()
	if(using_map?.name != "Southern Cross")
		return
	var/datum/flight_vessel/viewing_vessel
	for(var/id in SSflight_operations.vessels)
		viewing_vessel = SSflight_operations.vessels[id]
		if(viewing_vessel)
			break
	TEST_ASSERT_NOTNULL(viewing_vessel, "The live flight registry has no vessel with which to serialize the UI payload")
	var/datum/flight_operations_ui/flight_ui = new(src, viewing_vessel)
	var/list/data = flight_ui.tgui_data(null)
	var/list/sif_payload
	var/list/carrier_payload
	var/sif_count = 0
	var/carrier_count = 0
	for(var/list/destination in data["destinations"])
		if(destination["name"] == "Sif")
			sif_count++
			sif_payload = destination
		else if(destination["name"] == "Exploration Carrier")
			carrier_count++
			carrier_payload = destination
	TEST_ASSERT_EQUAL(sif_count, 1, "The live UI payload must emit exactly one Sif destination")
	TEST_ASSERT_EQUAL(carrier_count, 1, "The live UI payload must emit exactly one Exploration Carrier destination")
	TEST_ASSERT_NOTNULL(sif_payload, "Sif was filtered out of the live UI payload")
	TEST_ASSERT_NOTNULL(carrier_payload, "The Exploration Carrier was filtered out of the live UI payload")
	TEST_ASSERT_EQUAL(carrier_payload["scene_role"], "orbital", "The live UI payload classified the carrier as docked")
	TEST_ASSERT_EQUAL(carrier_payload["orbit_parent_id"], sif_payload["id"], "The emitted carrier parent does not reference the emitted Sif destination")
	TEST_ASSERT_NULL(carrier_payload["docked_port_id"], "The live UI payload emitted a carrier docking port")
	TEST_ASSERT_NULL(carrier_payload["docked_host_id"], "The live UI payload emitted a carrier docking host")
	qdel(flight_ui)

/datum/unit_test/dq_live_flight_payload_attaches_carrier_craft

/datum/unit_test/dq_live_flight_payload_attaches_carrier_craft/Run()
	if(using_map?.name != "Southern Cross")
		return
	var/carrier_id = SSflight_operations.destination_id_named("Exploration Carrier")
	TEST_ASSERT_NOTNULL(carrier_id, "The live flight registry omitted the carrier host destination")
	var/datum/flight_vessel/viewing_vessel
	for(var/id in SSflight_operations.vessels)
		viewing_vessel = SSflight_operations.vessels[id]
		if(viewing_vessel)
			break
	TEST_ASSERT_NOTNULL(viewing_vessel, "The live flight registry has no vessel with which to serialize the UI payload")
	var/datum/flight_operations_ui/flight_ui = new(src, viewing_vessel)
	var/list/data = flight_ui.tgui_data(null)
	var/static/list/carrier_dock_tags = list(
		"stargazer_dock",
		"baby_mammoth_dock",
		"ursula_dock",
		"needle_dock",
		"echidna_dock",
	)
	var/list/expected_destination_ids = list()
	for(var/id in SSflight_operations.vessels)
		var/datum/flight_vessel/vessel = SSflight_operations.vessels[id]
		if(!(vessel.shuttle?.current_location?.landmark_tag in carrier_dock_tags))
			continue
		var/datum/flight_destination/destination = SSflight_operations.destination_for_target(vessel.ship)
		TEST_ASSERT_NOTNULL(destination, "Carrier craft [vessel.name] has no render destination")
		expected_destination_ids[destination.id] = vessel.name
		var/datum/flight_port/port = SSflight_operations.ports[vessel.docked_port_id]
		TEST_ASSERT_NOTNULL(port, "Carrier craft [vessel.name] did not resolve its current landmark to a flight port")
		TEST_ASSERT_EQUAL(port.host_destination_id, carrier_id, "Carrier craft [vessel.name] resolved to the wrong physical host")
	TEST_ASSERT(length(expected_destination_ids) > 0, "No carrier-docked craft were found in the live registry")
	var/validated = 0
	for(var/list/destination in data["destinations"])
		var/vessel_name = expected_destination_ids[destination["id"]]
		if(!vessel_name)
			continue
		validated++
		TEST_ASSERT_EQUAL(destination["scene_role"], "docked", "Carrier craft [vessel_name] serialized as an independent orbital")
		TEST_ASSERT_EQUAL(destination["docked_host_id"], carrier_id, "Carrier craft [vessel_name] did not serialize the carrier as its host")
		TEST_ASSERT_NOTNULL(destination["docked_port_id"], "Carrier craft [vessel_name] serialized without its physical port")
	TEST_ASSERT_EQUAL(validated, length(expected_destination_ids), "One or more carrier-docked craft were filtered out of the production payload")
	qdel(flight_ui)

/datum/unit_test/dq_station_flight_never_substitutes_carrier_port

/datum/unit_test/dq_station_flight_never_substitutes_carrier_port/Run()
	if(using_map?.name != "Southern Cross")
		return
	var/datum/flight_destination/station
	for(var/id in SSflight_operations.destinations)
		var/datum/flight_destination/candidate = SSflight_operations.destinations[id]
		if(candidate.kind == FLIGHT_DEST_STATION && lowertext(candidate.name) == "southern cross")
			station = candidate
			break
	TEST_ASSERT_NOTNULL(station, "Southern Cross is absent from the live flight registry")
	var/datum/flight_vessel/vessel
	for(var/id in SSflight_operations.vessels)
		var/datum/flight_vessel/candidate = SSflight_operations.vessels[id]
		if(candidate.shuttle)
			vessel = candidate
			break
	TEST_ASSERT_NOTNULL(vessel, "No landable expedition vessel was registered")
	var/datum/flight_plan/plan = new(vessel, null, station)
	TEST_ASSERT(plan.start(), "Southern Cross flight failed preflight")
	TEST_ASSERT_NOTNULL(plan.arrival_port, "Southern Cross flight planned an orbital fallback instead of a physical landing")
	TEST_ASSERT(plan.arrival_port.landmark.landmark_tag in list("hangar_3_expedition", "hangar_3_echidna"), "Southern Cross flight did not reserve Hangar Three")
	TEST_ASSERT(plan.arrival_port.reserved_by == plan, "Reserved arrival port does not own the flight plan lease")
	TEST_ASSERT_EQUAL(plan.arrival_port.host_destination_id, station.id, "Southern Cross flight substituted a berth on another physical host")
	qdel(plan)

/datum/unit_test/dq_station_route_rejects_carrier_port_alias

/datum/unit_test/dq_station_route_rejects_carrier_port_alias/Run()
	var/datum/flight_destination/station = new
	station.id = "unit-station"
	var/datum/flight_destination/carrier = new
	carrier.id = "unit-carrier"
	var/datum/flight_port/port = new
	port.host_destination_id = carrier.id
	port.serves_destination_ids = list(carrier.id)
	TEST_ASSERT(!port.serves(station.id), "A carrier berth incorrectly advertised itself as a Southern Cross arrival")
	qdel(port)
	qdel(carrier)
	qdel(station)

/datum/unit_test/dq_southern_cross_berth_fits_every_expedition_craft

/datum/unit_test/dq_southern_cross_berth_fits_every_expedition_craft/Run()
	var/tested_vessels = 0
	for(var/id in SSflight_operations.vessels)
		var/datum/flight_vessel/vessel = SSflight_operations.vessels[id]
		if(!vessel.shuttle || !(vessel.capabilities & FLIGHT_CAP_EXPEDITION))
			continue
		tested_vessels++
		var/found_valid_berth = FALSE
		for(var/tag in list("hangar_3_expedition", "hangar_3_echidna"))
			var/obj/effect/shuttle_landmark/southern_cross/expedition_station/berth = SSshuttles.registered_shuttle_landmarks[tag]
			if(berth?.accepts_shuttle(vessel.shuttle) && berth.is_valid(vessel.shuttle))
				found_valid_berth = TRUE
				break
		TEST_ASSERT(found_valid_berth, "Hangar Three cannot physically fit [vessel.name]")
	TEST_ASSERT(tested_vessels > 0, "No expedition craft were available to validate Hangar Three geometry")

/datum/unit_test/dq_station_arrival_without_berth_fails_preflight

/datum/unit_test/dq_station_arrival_without_berth_fails_preflight/Run()
	var/obj/effect/overmap/visitable/ship/ship = new(null)
	var/obj/effect/target = new(null)
	var/datum/flight_destination/station = new
	station.id = "unit-station-orbit"
	station.kind = FLIGHT_DEST_STATION
	station.target = target
	var/datum/flight_vessel/vessel = new
	vessel.ship = ship
	vessel.capabilities = FLIGHT_CAP_STRATEGIC
	var/datum/flight_plan/plan = new(vessel, null, station)
	TEST_ASSERT(!plan.start(), "A station flight without a berth launched despite having nowhere to land")
	TEST_ASSERT_NULL(plan.arrival_port, "A station flight reserved an unrelated physical berth")
	TEST_ASSERT_EQUAL(plan.state, FLIGHT_PLAN_FAILED, "A berthless station flight did not fail during preflight")
	qdel(plan)
	vessel.ship = null
	station.target = null
	qdel(vessel)
	qdel(station)
	qdel(target)
	qdel(ship)

/datum/unit_test/dq_failed_flight_releases_all_leases

/datum/unit_test/dq_failed_flight_releases_all_leases/Run()
	var/datum/flight_destination/destination = new
	destination.id = "unit-failure-destination"
	var/datum/flight_vessel/vessel = new
	var/datum/flight_port/port = new
	var/datum/flight_plan/plan = new(vessel, null, destination)
	vessel.active_plan = plan
	plan.arrival_port = port
	port.reserved_by = plan
	plan.fail("Intentional unit-test failure")
	TEST_ASSERT_NULL(port.reserved_by, "A failed flight retained its arrival-port reservation")
	TEST_ASSERT(!LAZYLEN(destination.active_plans), "A failed flight retained its destination lease")
	qdel(plan)
	qdel(port)
	qdel(vessel)
	qdel(destination)

/datum/unit_test/dq_expedition_generation_begins_in_transit

/datum/unit_test/dq_expedition_generation_begins_in_transit/Run()
	var/datum/expedition_site/site = new
	var/datum/flight_destination/destination = new
	destination.id = "unit-expedition-destination"
	destination.expedition = site
	var/datum/flight_vessel/vessel = new
	var/datum/flight_plan/plan = new(vessel, null, destination)
	TEST_ASSERT_EQUAL(plan.generation_state, FLIGHT_GENERATION_QUEUED, "An ungenerated expedition was not queued")
	plan.start()
	TEST_ASSERT_EQUAL(plan.generation_state, FLIGHT_GENERATION_RUNNING, "Engaging an expedition did not arm generation")
	TEST_ASSERT_EQUAL(plan.generation_stage, "Reserving destination", "Expedition generation began before transit")
	qdel(plan)
	destination.expedition = null
	qdel(vessel)
	qdel(destination)
	qdel(site)
