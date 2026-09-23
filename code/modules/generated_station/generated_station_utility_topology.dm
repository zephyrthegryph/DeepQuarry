/// Owned collection of real power and LINDA atmosphere machinery for one station.
/obj/structure/cable/generated_station
	icon_state = "0-1"

/obj/structure/cable/generated_station/Initialize(mapload, generated_icon_state)
	if(generated_icon_state)
		icon_state = generated_icon_state
	return ..()

/obj/machinery/power/smes/generated_station
	should_be_mapped = TRUE
	circuit = null
	charge = 5e6
	output_attempt = TRUE
	output_level = 200000

/// A tangible station source feeding the shared grid; destroying it removes generation.
/obj/machinery/power/generator/generated_station
	name = "compact station turbine"
	desc = "A self-contained turbine-generator supplying the installation's main bus."
	anchored = TRUE
	var/generation_rate = 350000

/obj/machinery/power/generator/generated_station/process()
	if(stat & BROKEN)
		return
	add_avail(generation_rate)

/obj/machinery/atmospherics/pipe/tank/air/full/generated_station
	dir = EAST
	start_pressure = 50 * ONE_ATMOSPHERE
	connect_types = CONNECT_TYPE_SUPPLY
	piping_layer = PIPING_LAYER_SUPPLY

/obj/machinery/atmospherics/pipe/tank/air/full/generated_station/Initialize(mapload, generated_dir)
	if(generated_dir)
		dir = generated_dir
	return ..()

/obj/machinery/atmospherics/pipe/tank/generated_station_scrub
	dir = WEST
	connect_types = CONNECT_TYPE_SCRUBBER
	piping_layer = PIPING_LAYER_SCRUBBER

/obj/machinery/atmospherics/pipe/tank/generated_station_scrub/Initialize(mapload, generated_dir)
	if(generated_dir)
		dir = generated_dir
	return ..()

/obj/machinery/atmospherics/pipe/simple/hidden/supply/generated_station/Initialize(mapload, generated_dir)
	if(generated_dir)
		dir = generated_dir
	return ..()

/obj/machinery/atmospherics/pipe/simple/hidden/scrubbers/generated_station/Initialize(mapload, generated_dir)
	if(generated_dir)
		dir = generated_dir
	return ..()

/obj/machinery/atmospherics/pipe/manifold/hidden/supply/generated_station/Initialize(mapload, generated_dir)
	if(generated_dir)
		dir = generated_dir
	return ..()

/obj/machinery/atmospherics/pipe/manifold/hidden/scrubbers/generated_station/Initialize(mapload, generated_dir)
	if(generated_dir)
		dir = generated_dir
	return ..()

/obj/machinery/atmospherics/pipe/cap/hidden/supply/generated_station/Initialize(mapload, generated_dir)
	if(generated_dir)
		dir = generated_dir
	return ..()

/obj/machinery/atmospherics/pipe/cap/hidden/scrubbers/generated_station/Initialize(mapload, generated_dir)
	if(generated_dir)
		dir = generated_dir
	return ..()

/obj/machinery/atmospherics/unary/vent_pump/on/generated_station
	dir = WEST
	piping_layer = PIPING_LAYER_SUPPLY

/obj/machinery/atmospherics/unary/vent_pump/on/generated_station/Initialize(mapload, generated_dir)
	if(generated_dir)
		dir = generated_dir
	return ..()

/obj/machinery/atmospherics/unary/vent_scrubber/on/generated_station
	dir = EAST
	piping_layer = PIPING_LAYER_SCRUBBER

/obj/machinery/atmospherics/unary/vent_scrubber/on/generated_station/Initialize(mapload, generated_dir)
	if(generated_dir)
		dir = generated_dir
	return ..()

/datum/generated_station_utility_topology
	var/station_id
	var/list/power_objects
	var/list/atmos_objects
	var/list/apcs
	var/list/supply_vents
	var/list/supply_tanks
	var/list/scrubbers
	var/list/scrub_tanks
	var/list/alarms

/datum/generated_station_utility_topology/New()
	..()
	power_objects = list()
	atmos_objects = list()
	apcs = list()
	supply_vents = list()
	supply_tanks = list()
	scrubbers = list()
	scrub_tanks = list()
	alarms = list()

/datum/generated_station_utility_topology/Destroy()
	QDEL_LIST(power_objects)
	QDEL_LIST(atmos_objects)
	apcs = null
	supply_vents = null
	supply_tanks = null
	scrubbers = null
	scrub_tanks = null
	alarms = null
	return ..()

/datum/generated_station_utility_topology/proc/power_available()
	var/has_source = FALSE
	for(var/obj/machinery/power/generator/generated_station/generator in power_objects)
		if(!QDELETED(generator) && !(generator.stat & BROKEN) && generator.powernet)
			has_source = TRUE
			break
	for(var/obj/machinery/power/smes/SMES in power_objects)
		if(has_source)
			break
		if(QDELETED(SMES) || (SMES.stat & BROKEN) || SMES.charge <= 0)
			continue
		for(var/obj/machinery/power/terminal/terminal in SMES.terminals)
			if(terminal.powernet)
				has_source = TRUE
				break
		if(has_source)
			break
	if(!has_source)
		return FALSE
	for(var/obj/machinery/power/apc/APC in apcs)
		if(!QDELETED(APC) && !(APC.stat & BROKEN) && APC.cell && APC.terminal?.powernet)
			return TRUE
	return FALSE

/datum/generated_station_utility_topology/proc/atmosphere_available()
	for(var/obj/machinery/atmospherics/unary/vent_pump/vent in supply_vents)
		if(!QDELETED(vent) && !(vent.stat & BROKEN) && vent.node && vent.network && vent.air_contents?.return_pressure() > ONE_ATMOSPHERE)
			return TRUE
	return FALSE

/datum/generated_station_utility_topology/proc/power_network_is_global()
	var/datum/powernet/shared
	for(var/obj/machinery/power/apc/APC in apcs)
		if(!APC.terminal?.powernet)
			return FALSE
		if(!shared)
			shared = APC.terminal.powernet
		else if(APC.terminal.powernet != shared)
			return FALSE
	if(!shared)
		return FALSE
	for(var/obj/machinery/power/generator/generated_station/generator in power_objects)
		if(generator.powernet == shared)
			return TRUE
	return FALSE

/datum/generated_station_utility_topology/proc/power_network_summary()
	var/list/parts = list()
	for(var/obj/machinery/power/apc/APC in apcs)
		parts += "APC@[generated_station_coordinate(APC)] terminal=[generated_station_coordinate(APC.terminal)] network=[APC.terminal?.powernet ? REF(APC.terminal.powernet) : "null"]"
	for(var/obj/machinery/power/generator/generated_station/generator in power_objects)
		parts += "generator@[generated_station_coordinate(generator)] network=[generator.powernet ? REF(generator.powernet) : "null"]"
	return jointext(parts, "; ")

/datum/generated_station_utility_topology/proc/atmosphere_networks_are_global()
	var/datum/pipe_network/supply_network
	for(var/obj/machinery/atmospherics/unary/vent_pump/vent in supply_vents)
		if(!vent.network)
			return FALSE
		if(!supply_network)
			supply_network = vent.network
		else if(vent.network != supply_network)
			return FALSE
	var/datum/pipe_network/scrub_network
	for(var/obj/machinery/atmospherics/unary/vent_scrubber/scrubber in scrubbers)
		if(!scrubber.network)
			return FALSE
		if(!scrub_network)
			scrub_network = scrubber.network
		else if(scrubber.network != scrub_network)
			return FALSE
	if(!supply_network || !scrub_network)
		return FALSE
	return supply_network != scrub_network

/datum/generated_station_utility_topology/proc/atmosphere_network_summary()
	var/list/parts = list()
	for(var/obj/machinery/atmospherics/unary/vent_pump/vent in supply_vents)
		parts += "vent@[generated_station_coordinate(vent)] node=[REF(vent.node)] network=[REF(vent.network)]"
	for(var/obj/machinery/atmospherics/unary/vent_scrubber/scrubber in scrubbers)
		parts += "scrubber@[generated_station_coordinate(scrubber)] node=[REF(scrubber.node)] network=[REF(scrubber.network)]"
	return jointext(parts, "; ")

/datum/generated_station_utility_topology/proc/atmosphere_network_break_summary()
	var/list/parts = list()
	for(var/obj/machinery/atmospherics/pipe/pipe in atmos_objects)
		if(pipe.piping_layer != PIPING_LAYER_SUPPLY || !pipe.parent?.network)
			continue
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor_turf = get_step(pipe, direction)
			for(var/obj/machinery/atmospherics/pipe/neighbor in neighbor_turf)
				if(neighbor.piping_layer == PIPING_LAYER_SUPPLY && neighbor.parent?.network && neighbor.parent.network != pipe.parent.network)
					parts += "[generated_station_coordinate(pipe)] [pipe.type] dir=[pipe.dir] net=[REF(pipe.parent.network)] beside [generated_station_coordinate(neighbor)] [neighbor.type] dir=[neighbor.dir] net=[REF(neighbor.parent.network)]"
	return jointext(parts, "; ")

/proc/generated_station_utility_topology(station_id)
	for(var/key in SSexpedition?.sites)
		var/datum/expedition_site/site = SSexpedition.sites[key]
		if(site.station_spec?.id == station_id)
			return site.station_utilities
	return null

/datum/generated_station_utility_builder
	var/datum/generated_station_spec/spec
	var/datum/generated_station_materialization/materialization
	var/datum/generated_station_utility_topology/result

/// Reserves fixtures and station-wide routes against local coordinates before live turfs exist.
/datum/generated_station_materializer/proc/plan_generated_station_utilities()
	var/datum/generated_station_tile_plan/plan = result?.tile_plan
	if(!plan)
		return FALSE
	var/list/reserved = list()
	var/list/route_targets = list()
	plan.index_utility_floors()
	var/engineering_owner
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		var/datum/generated_station_department_instance/department = department_for_node(node)
		if(department?.definition?.id == "engineering")
			engineering_owner = node.id
	for(var/datum/generated_station_module/module in result.modules)
		var/datum/generated_station_tile_intent/apc = planned_utility_floor(plan, module.department_node_id, reserved, TRUE, module.id)
		var/list/vent = planned_utility_pair(plan, module.department_node_id, reserved, module.id)
		var/list/scrubber = planned_utility_pair(plan, module.department_node_id, reserved, module.id)
		var/datum/generated_station_tile_intent/alarm = planned_utility_floor(plan, module.department_node_id, reserved, TRUE, module.id)
		var/datum/generated_station_tile_intent/fire_alarm = planned_utility_floor(plan, module.department_node_id, reserved, TRUE, module.id)
		if(!apc || !vent || !scrubber || !alarm || !fire_alarm)
			plan.errors += "No complete utility fixture set for [module.id]."
			return FALSE
		var/datum/generated_station_tile_intent/vent_device = vent["device"]
		var/datum/generated_station_tile_intent/vent_connector = vent["connector"]
		var/datum/generated_station_tile_intent/scrubber_device = scrubber["device"]
		var/datum/generated_station_tile_intent/scrubber_connector = scrubber["connector"]
		if(!plan.claim_utility_fixture(apc.local_x, apc.local_y, module.department_node_id, GENERATED_STATION_UTILITY_APC) || !plan.claim_utility(apc.local_x, apc.local_y, module.department_node_id, GENERATED_STATION_UTILITY_APC_TERMINAL) || !plan.claim_utility_fixture(alarm.local_x, alarm.local_y, module.department_node_id, GENERATED_STATION_UTILITY_AIR_ALARM) || !plan.claim_utility_fixture(fire_alarm.local_x, fire_alarm.local_y, module.department_node_id, GENERATED_STATION_UTILITY_FIRE_ALARM) || !plan.claim_utility_fixture(vent_device.local_x, vent_device.local_y, module.department_node_id, GENERATED_STATION_UTILITY_VENT) || !plan.claim_utility_fixture(scrubber_device.local_x, scrubber_device.local_y, module.department_node_id, GENERATED_STATION_UTILITY_SCRUBBER))
			return FALSE
		route_targets |= vent_connector
		route_targets |= scrubber_connector
		route_targets |= apc
		if(!plan_generated_station_lights(plan, module.department_node_id, reserved, module.id))
			return FALSE
	if(!engineering_owner)
		plan.errors += "Utility planning requires an engineering department."
		return FALSE
	var/list/smes = planned_utility_pair(plan, engineering_owner, reserved)
	var/list/generator = planned_utility_pair(plan, engineering_owner, reserved)
	var/list/supply_tank = planned_utility_pair(plan, engineering_owner, reserved)
	var/list/scrub_tank = planned_utility_pair(plan, engineering_owner, reserved)
	if(!smes || !generator || !supply_tank || !scrub_tank)
		plan.errors += "Engineering has no complete source fixture set."
		return FALSE
	var/datum/generated_station_tile_intent/smes_device = smes["device"]
	var/datum/generated_station_tile_intent/smes_connector = smes["connector"]
	var/datum/generated_station_tile_intent/generator_device = generator["device"]
	var/datum/generated_station_tile_intent/supply_device = supply_tank["device"]
	var/datum/generated_station_tile_intent/supply_connector = supply_tank["connector"]
	var/datum/generated_station_tile_intent/scrub_device = scrub_tank["device"]
	var/datum/generated_station_tile_intent/scrub_connector = scrub_tank["connector"]
	if(!plan.claim_utility_fixture(smes_device.local_x, smes_device.local_y, engineering_owner, GENERATED_STATION_UTILITY_SMES) || !plan.claim_utility_fixture(generator_device.local_x, generator_device.local_y, engineering_owner, GENERATED_STATION_UTILITY_GENERATOR) || !plan.claim_utility_fixture(supply_device.local_x, supply_device.local_y, engineering_owner, GENERATED_STATION_UTILITY_SUPPLY_TANK) || !plan.claim_utility_fixture(scrub_device.local_x, scrub_device.local_y, engineering_owner, GENERATED_STATION_UTILITY_SCRUB_TANK))
		return FALSE
	route_targets |= smes_connector
	route_targets |= generator_device
	route_targets |= supply_connector
	route_targets |= scrub_connector
	var/list/route = planned_global_utility_route(plan, route_targets)
	if(!length(route))
		plan.errors += "The abstract station floor graph cannot connect all utility sockets."
		return FALSE
	for(var/key in route)
		var/datum/generated_station_tile_intent/intent = route[key]
		if(!plan.claim_utility(intent.local_x, intent.local_y, intent.owner_id, GENERATED_STATION_UTILITY_POWER_ROUTE) || !plan.claim_utility(intent.local_x, intent.local_y, intent.owner_id, GENERATED_STATION_UTILITY_SUPPLY_ROUTE) || !plan.claim_utility(intent.local_x, intent.local_y, intent.owner_id, GENERATED_STATION_UTILITY_SCRUB_ROUTE))
			return FALSE
	return !length(plan.errors)

/datum/generated_station_materializer/proc/planned_utility_floor(datum/generated_station_tile_plan/plan, owner_id, list/reserved, against_hull = FALSE, zone_id)
	for(var/datum/generated_station_tile_intent/intent in plan.utility_floors(owner_id, zone_id))
		var/key = plan.coordinate_key(intent.local_x, intent.local_y)
		if(intent.owner_id != owner_id || (zone_id && intent.zone_id != zone_id) || intent.structure_kind != GENERATED_STATION_TILE_FLOOR || intent.door_type)
			continue
		if(against_hull)
			var/wall_reservation = "wall-floor:[key]"
			if(reserved[wall_reservation])
				continue
			var/has_hull = FALSE
			for(var/list/offset in list(list(1, 0), list(-1, 0), list(0, 1), list(0, -1)))
				var/wall_x = intent.local_x + offset[1]
				var/wall_y = intent.local_y + offset[2]
				if(plan.tile(wall_x, wall_y)?.structure_kind == GENERATED_STATION_TILE_HULL)
					has_hull = TRUE
					break
			if(!has_hull)
				continue
			// Wall fixtures may share the floor with one vent or scrubber, but two
			// wall-mounted machines may not occupy the same floor coordinate.
			reserved[wall_reservation] = TRUE
		else
			if(reserved[key])
				continue
			reserved[key] = TRUE
		return intent
	return null

/datum/generated_station_materializer/proc/planned_utility_pair(datum/generated_station_tile_plan/plan, owner_id, list/reserved, zone_id)
	for(var/datum/generated_station_tile_intent/device in plan.utility_floors(owner_id, zone_id))
		var/key = plan.coordinate_key(device.local_x, device.local_y)
		if(device.owner_id != owner_id || (zone_id && device.zone_id != zone_id) || device.structure_kind != GENERATED_STATION_TILE_FLOOR || device.door_type || reserved[key])
			continue
		for(var/list/offset in list(list(1, 0), list(-1, 0), list(0, 1), list(0, -1)))
			var/datum/generated_station_tile_intent/connector = plan.tile(device.local_x + offset[1], device.local_y + offset[2])
			if(!connector || connector.owner_id != owner_id || (zone_id && connector.zone_id != zone_id) || connector.structure_kind != GENERATED_STATION_TILE_FLOOR || connector.door_type)
				continue
			// The connector is underfloor routing, not another physical fixture.
			// Supply and scrubber pipes use separate layers and may share this tile
			// with each other, cables, or a wall-mounted APC/alarm. Reserving it as
			// occupied made otherwise valid compact rooms require seven clear tiles
			// for five actual machines.
			reserved[key] = TRUE
			return list("device" = device, "connector" = connector)
	return null

/// Wall lights are placed on clear floor sockets directly adjacent to structure.
/datum/generated_station_materializer/proc/plan_generated_station_lights(datum/generated_station_tile_plan/plan, owner_id, list/reserved, zone_id)
	var/list/candidates = list()
	for(var/datum/generated_station_tile_intent/intent in plan.utility_floors(owner_id, zone_id))
		if(intent.owner_id != owner_id || (zone_id && intent.zone_id != zone_id) || intent.structure_kind != GENERATED_STATION_TILE_FLOOR || intent.door_type)
			continue
		// Wall fixtures are owned per structural edge, not per floor tile. A
		// corner floor may therefore support (for example) an alarm on one wall
		// and a light on the other; claim_utility_fixture selects a free edge.
		var/has_free_wall_edge = FALSE
		for(var/list/offset in list(list(1, 0), list(-1, 0), list(0, 1), list(0, -1)))
			var/datum/generated_station_tile_intent/support = plan.tile(intent.local_x + offset[1], intent.local_y + offset[2])
			if(!support?.is_structural_wall())
				continue
			var/direction
			if(offset[1] > 0)
				direction = EAST
			else if(offset[1] < 0)
				direction = WEST
			else if(offset[2] > 0)
				direction = NORTH
			else
				direction = SOUTH
			var/edge_key = "[support.local_x],[support.local_y],[direction]"
			if(!plan.wall_fixture_edges[edge_key])
				has_free_wall_edge = TRUE
				break
		if(has_free_wall_edge)
			candidates += intent
		generation_checkpoint("Selecting utility fixtures", 32)
	if(!length(candidates))
		plan.errors += "No wall light socket is available for [zone_id || owner_id]."
		return FALSE
	var/light_count = max(1, CEILING(length(candidates) / 25, 1))
	var/list/selected = list()
	for(var/index in 1 to light_count)
		var/datum/generated_station_tile_intent/light
		var/best_distance = -1
		for(var/datum/generated_station_tile_intent/candidate in candidates)
			if(candidate in selected)
				continue
			var/nearest = 1.0e31
			if(!length(selected))
				nearest = abs(candidate.local_x - round(plan.grid_width / 2)) + abs(candidate.local_y - round(plan.grid_height / 2))
			else
				for(var/datum/generated_station_tile_intent/placed in selected)
					nearest = min(nearest, abs(candidate.local_x - placed.local_x) + abs(candidate.local_y - placed.local_y))
			if(nearest > best_distance)
				best_distance = nearest
				light = candidate
			generation_checkpoint("Spacing station lights", 32)
		if(!light)
			break
		selected += light
		var/key = plan.coordinate_key(light.local_x, light.local_y)
		reserved[key] = TRUE
		if(!plan.claim_utility_fixture(light.local_x, light.local_y, owner_id, GENERATED_STATION_UTILITY_LIGHT))
			return FALSE
	return TRUE

/datum/generated_station_materializer/proc/planned_global_utility_route(datum/generated_station_tile_plan/plan, list/targets)
	var/list/path = list()
	if(!length(targets))
		return path
	var/datum/generated_station_tile_intent/first = targets[1]
	path[plan.coordinate_key(first.local_x, first.local_y)] = first
	for(var/index in 2 to length(targets))
		var/datum/generated_station_tile_intent/target = targets[index]
		var/list/frontier = list(target)
		var/list/came_from = list()
		came_from[plan.coordinate_key(target.local_x, target.local_y)] = FALSE
		var/datum/generated_station_tile_intent/reached
		while(length(frontier))
			var/datum/generated_station_tile_intent/current = frontier[1]
			frontier.Cut(1, 2)
			var/current_key = plan.coordinate_key(current.local_x, current.local_y)
			if(path[current_key])
				reached = current
				break
			for(var/list/offset in list(list(1, 0), list(-1, 0), list(0, 1), list(0, -1)))
				var/datum/generated_station_tile_intent/next = plan.tile(current.local_x + offset[1], current.local_y + offset[2])
				var/next_key = next && plan.coordinate_key(next.local_x, next.local_y)
				if(!next || next.structure_kind != GENERATED_STATION_TILE_FLOOR || (next_key in came_from))
					continue
				came_from[next_key] = current
				frontier += next
			generation_checkpoint("Routing station utilities", 33)
		if(!reached)
			var/list/neighbor_descriptions = list()
			var/list/component_zones = list()
			var/list/component_doors = list()
			for(var/visited_key in came_from)
				var/datum/generated_station_tile_intent/visited = plan.tiles[visited_key]
				component_zones[visited?.zone_id] = (component_zones[visited?.zone_id] || 0) + 1
				if(visited?.door_type)
					component_doors += "[visited.local_x],[visited.local_y]"
			for(var/list/offset in list(list(1, 0), list(-1, 0), list(0, 1), list(0, -1)))
				var/datum/generated_station_tile_intent/neighbor = plan.tile(target.local_x + offset[1], target.local_y + offset[2])
				neighbor_descriptions += "[neighbor?.local_x],[neighbor?.local_y]=[neighbor?.owner_id]/[neighbor?.zone_id]/[neighbor?.structure_kind]"
			var/neighbor_summary = jointext(neighbor_descriptions, "; ")
			var/component_summary = json_encode(component_zones)
			var/door_summary = jointext(component_doors, ", ")
			plan.errors += "Utility target [target.owner_id]/[target.zone_id] at [target.local_x],[target.local_y] is disconnected; component zones=[component_summary], doors=[door_summary], neighbors: [neighbor_summary]."
			return list()
		var/datum/generated_station_tile_intent/current = reached
		while(current)
			var/current_key = plan.coordinate_key(current.local_x, current.local_y)
			path[current_key] = current
			current = came_from[current_key]
	return path

/// Builds one station-wide physical power bus and shared supply/scrubber trunks.
/datum/generated_station_utility_builder/proc/build(datum/generated_station_spec/new_spec, datum/generated_station_materialization/new_materialization)
	if(!new_spec || !new_materialization)
		return null
	spec = new_spec
	materialization = new_materialization
	result = new
	result.station_id = spec.id
	var/list/path_targets = list()
	var/list/power_targets = list()
	var/list/supply_connections = list()
	var/list/scrub_connections = list()
	var/area/generated_station/engineering_area
	var/engineering_owner

	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		var/area/generated_station/department_area = materialization.department_areas[node.id]
		if(department_area?.department_id == "engineering-1")
			engineering_area = department_area
			engineering_owner = node.id
	for(var/datum/generated_station_module/module in materialization.modules)
		var/area/generated_station/A = materialization.module_areas[module.id]
		var/turf/apc_turf = planned_fixture_turf(module.department_node_id, GENERATED_STATION_UTILITY_APC, module.id)
		if(!apc_turf)
			return fail_global_build("no APC floor in [A]")
		var/apc_wall_direction = planned_fixture_direction(module.department_node_id, GENERATED_STATION_UTILITY_APC, module.id)
		if(!apc_wall_direction)
			return fail_global_build("APC socket in [A] is not wall-mounted")
		var/obj/machinery/power/apc/APC = new(apc_turf)
		// APC construction faces into its supporting wall, unlike generic wall frames.
		APC.set_dir(apc_wall_direction)
		result.power_objects += APC
		result.apcs += APC
		A.apc = APC
		var/turf/apc_terminal_turf = get_turf(APC.terminal)
		if(!apc_terminal_turf)
			return fail_global_build("APC in [A] did not create a terminal")
		path_targets += apc_terminal_turf
		power_targets += apc_terminal_turf

		var/list/supply_pair = planned_fixture_pair(module.department_node_id, GENERATED_STATION_UTILITY_VENT, module.id)
		var/list/scrub_pair = planned_fixture_pair(module.department_node_id, GENERATED_STATION_UTILITY_SCRUBBER, module.id)
		if(!supply_pair || !scrub_pair)
			return fail_global_build("no vent/scrubber pair in [A]")
		var/turf/supply_device = supply_pair["device"]
		var/turf/supply_connector = supply_pair["connector"]
		var/obj/machinery/atmospherics/unary/vent_pump/on/generated_station/vent = new(supply_device, get_dir(supply_device, supply_connector))
		result.atmos_objects += vent
		result.supply_vents += vent
		path_targets += supply_connector
		add_external_connection(supply_connections, supply_connector, get_dir(supply_connector, supply_device))

		var/turf/scrub_device = scrub_pair["device"]
		var/turf/scrub_connector = scrub_pair["connector"]
		var/obj/machinery/atmospherics/unary/vent_scrubber/on/generated_station/scrubber = new(scrub_device, get_dir(scrub_device, scrub_connector))
		result.atmos_objects += scrubber
		result.scrubbers += scrubber
		path_targets += scrub_connector
		add_external_connection(scrub_connections, scrub_connector, get_dir(scrub_connector, scrub_device))

		var/turf/alarm_turf = planned_fixture_turf(module.department_node_id, GENERATED_STATION_UTILITY_AIR_ALARM, module.id)
		if(!alarm_turf)
			return fail_global_build("no alarm floor in [A]")
		var/alarm_wall_direction = planned_fixture_direction(module.department_node_id, GENERATED_STATION_UTILITY_AIR_ALARM, module.id)
		if(!alarm_wall_direction)
			return fail_global_build("air alarm socket in [A] is not wall-mounted")
		var/obj/machinery/alarm/alarm = new(alarm_turf)
		alarm.set_dir(turn(alarm_wall_direction, 180))
		alarm.offset_airalarm()
		result.atmos_objects += alarm
		result.alarms += alarm

	if(!engineering_area)
		return fail_global_build("engineering area was not found")
	var/list/source_pair = planned_fixture_pair(engineering_owner, GENERATED_STATION_UTILITY_SMES)
	var/list/generator_pair = planned_fixture_pair(engineering_owner, GENERATED_STATION_UTILITY_GENERATOR)
	if(!source_pair || !generator_pair)
		return fail_global_build("no SMES/generator pairs in engineering")
	var/turf/smes_turf = source_pair["device"]
	var/turf/smes_terminal_turf = source_pair["connector"]
	var/obj/machinery/power/terminal/smes_terminal = new(smes_terminal_turf)
	smes_terminal.set_dir(get_dir(smes_terminal, smes_turf))
	result.power_objects += smes_terminal
	var/obj/machinery/power/smes/generated_station/SMES = new(smes_turf)
	result.power_objects += SMES
	path_targets += smes_terminal_turf
	power_targets += smes_terminal_turf
	var/turf/generator_turf = generator_pair["device"]
	var/obj/machinery/power/generator/generated_station/generator = new(generator_turf)
	result.power_objects += generator
	path_targets += generator_turf
	power_targets += generator_turf

	var/list/supply_source_pair = planned_fixture_pair(engineering_owner, GENERATED_STATION_UTILITY_SUPPLY_TANK)
	var/list/scrub_source_pair = planned_fixture_pair(engineering_owner, GENERATED_STATION_UTILITY_SCRUB_TANK)
	if(!supply_source_pair || !scrub_source_pair)
		return fail_global_build("no tank pairs in engineering")
	var/turf/supply_tank_turf = supply_source_pair["device"]
	var/turf/supply_tank_connector = supply_source_pair["connector"]
	var/obj/machinery/atmospherics/pipe/tank/air/full/generated_station/supply_tank = new(supply_tank_turf, get_dir(supply_tank_turf, supply_tank_connector))
	result.atmos_objects += supply_tank
	result.supply_tanks += supply_tank
	path_targets += supply_tank_connector
	add_external_connection(supply_connections, supply_tank_connector, get_dir(supply_tank_connector, supply_tank_turf))
	var/turf/scrub_tank_turf = scrub_source_pair["device"]
	var/turf/scrub_tank_connector = scrub_source_pair["connector"]
	var/obj/machinery/atmospherics/pipe/tank/generated_station_scrub/scrub_tank = new(scrub_tank_turf, get_dir(scrub_tank_turf, scrub_tank_connector))
	result.atmos_objects += scrub_tank
	result.scrub_tanks += scrub_tank
	path_targets += scrub_tank_connector
	add_external_connection(scrub_connections, scrub_tank_connector, get_dir(scrub_tank_connector, scrub_tank_turf))

	var/list/global_path = planned_route_turfs()
	if(!length(global_path))
		return fail_global_build("global floor routing failed")
	var/list/pipe_tree_directions = spanning_path_directions(global_path)
	build_global_cables(global_path)
	ensure_global_power_connections(global_path, power_targets)
	build_global_pipe_network(global_path, pipe_tree_directions, supply_connections, TRUE)
	build_global_pipe_network(global_path, pipe_tree_directions, scrub_connections, FALSE)
	build_planned_lights()
	initialize_global_atmos()
	publish_utility_state()
	return result

/// Proves that every department floor lies near a powered, intact, active fixture.
/datum/generated_station_utility_builder/proc/validate_operational_light_coverage(max_distance = 7)
	for(var/module_id in materialization.module_areas)
		var/area/generated_station/department_area = materialization.module_areas[module_id]
		var/list/working_lights = list()
		for(var/obj/machinery/light/light in department_area)
			if(light.status == LIGHT_OK && light.on && light.powered(LIGHT))
				working_lights += light
		if(!length(working_lights))
			return FALSE
		for(var/turf/simulated/floor/floor in department_area)
			var/covered = FALSE
			for(var/obj/machinery/light/light as anything in working_lights)
				if(get_dist(floor, light) <= max_distance)
					covered = TRUE
					break
			if(!covered)
				return FALSE
	return TRUE

/datum/generated_station_utility_builder/proc/planned_fixture_turf(owner_id, utility_id, zone_id)
	for(var/key in materialization.tile_plan.tiles)
		var/datum/generated_station_tile_intent/intent = materialization.tile_plan.tiles[key]
		if(intent.owner_id == owner_id && (!zone_id || intent.zone_id == zone_id) && (utility_id in intent.utility_intents))
			return materialization.world_turf(intent.local_x, intent.local_y)
	return null

/datum/generated_station_utility_builder/proc/planned_fixture_direction(owner_id, utility_id, zone_id)
	for(var/key in materialization.tile_plan.tiles)
		var/datum/generated_station_tile_intent/intent = materialization.tile_plan.tiles[key]
		if(intent.owner_id == owner_id && (!zone_id || intent.zone_id == zone_id) && (utility_id in intent.utility_intents))
			return intent.utility_wall_directions[utility_id]
	return 0

/datum/generated_station_utility_builder/proc/planned_fixture_pair(owner_id, utility_id, zone_id)
	var/datum/generated_station_tile_intent/device_intent
	for(var/key in materialization.tile_plan.tiles)
		var/datum/generated_station_tile_intent/intent = materialization.tile_plan.tiles[key]
		if(intent.owner_id == owner_id && (!zone_id || intent.zone_id == zone_id) && (utility_id in intent.utility_intents))
			device_intent = intent
			break
	if(!device_intent)
		return null
	var/datum/generated_station_tile_intent/connector_intent
	for(var/list/offset in list(list(1, 0), list(-1, 0), list(0, 1), list(0, -1)))
		var/datum/generated_station_tile_intent/candidate = materialization.tile_plan.tile(device_intent.local_x + offset[1], device_intent.local_y + offset[2])
		if(candidate?.structure_kind == GENERATED_STATION_TILE_FLOOR && (GENERATED_STATION_UTILITY_POWER_ROUTE in candidate.utility_intents))
			connector_intent = candidate
			break
	if(!connector_intent)
		return null
	return list(
		"device" = materialization.world_turf(device_intent.local_x, device_intent.local_y),
		"connector" = materialization.world_turf(connector_intent.local_x, connector_intent.local_y)
	)

/datum/generated_station_utility_builder/proc/planned_route_turfs()
	var/list/route = list()
	for(var/key in materialization.tile_plan.tiles)
		var/datum/generated_station_tile_intent/intent = materialization.tile_plan.tiles[key]
		if(GENERATED_STATION_UTILITY_POWER_ROUTE in intent.utility_intents)
			var/turf/T = materialization.world_turf(intent.local_x, intent.local_y)
			route[REF(T)] = T
	return route

/datum/generated_station_utility_builder/proc/build_planned_lights()
	for(var/key in materialization.tile_plan.tiles)
		var/datum/generated_station_tile_intent/intent = materialization.tile_plan.tiles[key]
		if(!(GENERATED_STATION_UTILITY_LIGHT in intent.utility_intents))
			continue
		var/turf/T = materialization.world_turf(intent.local_x, intent.local_y)
		var/wall_direction = intent.utility_wall_directions[GENERATED_STATION_UTILITY_LIGHT]
		if(!wall_direction)
			continue
		var/obj/machinery/light/light = new(T)
		// Light frames use reverse wall placement and therefore face their support.
		light.set_dir(wall_direction)
		switch(wall_direction)
			if(NORTH)
				light.pixel_x = (T.x % 2) ? 8 : -8
				light.pixel_y = 26
			if(SOUTH)
				light.pixel_x = (T.x % 2) ? 8 : -8
				light.pixel_y = -26
			if(EAST)
				light.pixel_x = 26
				light.pixel_y = (T.y % 2) ? 8 : -8
			if(WEST)
				light.pixel_x = -26
				light.pixel_y = (T.y % 2) ? 8 : -8
		result.power_objects += light

/// Publishes power and lighting only after the power and atmosphere graphs exist.
/datum/generated_station_utility_builder/proc/publish_utility_state()
	for(var/node_id in materialization.department_areas)
		var/area/generated_station/A = materialization.department_areas[node_id]
		A.power_change()
	materialization.transit_area?.power_change()

/datum/generated_station_utility_builder/proc/fail_global_build(reason)
	log_world("Generated station utility build failed for [spec?.id]: [reason]")
	QDEL_NULL(result)
	return null

/datum/generated_station_utility_builder/proc/add_external_connection(list/connections, turf/T, direction)
	var/key = REF(T)
	connections[key] = (connections[key] || 0) | direction

/datum/generated_station_utility_builder/proc/path_directions(list/path, turf/T)
	var/directions = 0
	for(var/direction in GLOB.cardinal)
		if(path[REF(get_step(T, direction))])
			directions |= direction
	return directions

/datum/generated_station_utility_builder/proc/direction_list(direction_mask)
	var/list/result_directions = list()
	for(var/direction in GLOB.cardinal)
		if(direction_mask & direction)
			result_directions += direction
	return result_directions

/datum/generated_station_utility_builder/proc/simple_pipe_direction(first, second)
	if((first == NORTH && second == SOUTH) || (first == SOUTH && second == NORTH))
		return NORTH
	if((first == EAST && second == WEST) || (first == WEST && second == EAST))
		return EAST
	return first | second

/datum/generated_station_utility_builder/proc/build_global_cables(list/path)
	for(var/key in path)
		var/turf/T = path[key]
		var/list/directions = direction_list(path_directions(path, T))
		if(!length(directions))
			continue
		if(length(directions) <= 2)
			var/cable_state = length(directions) == 1 ? "0-[directions[1]]" : "[min(directions[1], directions[2])]-[max(directions[1], directions[2])]"
			result.power_objects += new /obj/structure/cable/generated_station(T, cable_state)
		else
			for(var/direction in directions)
				result.power_objects += new /obj/structure/cable/generated_station(T, "0-[direction]")

/// Gives every terminal/source an explicit center tap even when the routed cable bends on its tile.
/datum/generated_station_utility_builder/proc/ensure_global_power_connections(list/path, list/targets)
	for(var/turf/T as anything in targets)
		var/list/directions = direction_list(path_directions(path, T))
		if(!length(directions))
			continue
		var/required_state = "0-[directions[1]]"
		var/found = FALSE
		for(var/obj/structure/cable/cable in T)
			if(cable.icon_state == required_state)
				found = TRUE
				break
		if(!found)
			result.power_objects += new /obj/structure/cable/generated_station(T, required_state)

/datum/generated_station_utility_builder/proc/spanning_path_directions(list/path)
	var/list/tree_directions = list()
	var/list/visited = list()
	var/list/queue = list()
	for(var/key in path)
		queue += path[key]
		visited[key] = TRUE
		break
	while(length(queue))
		var/turf/current = queue[1]
		queue.Cut(1, 2)
		var/current_key = REF(current)
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor = get_step(current, direction)
			var/neighbor_key = REF(neighbor)
			if(!path[neighbor_key] || visited[neighbor_key])
				continue
			visited[neighbor_key] = TRUE
			queue += neighbor
			tree_directions[current_key] = (tree_directions[current_key] || 0) | direction
			tree_directions[neighbor_key] = (tree_directions[neighbor_key] || 0) | get_dir(neighbor, current)
	return tree_directions

/datum/generated_station_utility_builder/proc/build_global_pipe_network(list/path, list/tree_directions, list/external_connections, supply)
	for(var/key in path)
		var/turf/T = path[key]
		var/direction_mask = (tree_directions[key] || 0) | (external_connections[key] || 0)
		var/list/directions = direction_list(direction_mask)
		var/obj/machinery/atmospherics/pipe/pipe
		switch(length(directions))
			if(1)
				pipe = supply ? new /obj/machinery/atmospherics/pipe/cap/hidden/supply/generated_station(T, directions[1]) : new /obj/machinery/atmospherics/pipe/cap/hidden/scrubbers/generated_station(T, directions[1])
			if(2)
				var/generated_dir = simple_pipe_direction(directions[1], directions[2])
				pipe = supply ? new /obj/machinery/atmospherics/pipe/simple/hidden/supply/generated_station(T, generated_dir) : new /obj/machinery/atmospherics/pipe/simple/hidden/scrubbers/generated_station(T, generated_dir)
			if(3)
				var/missing_direction = (NORTH|SOUTH|EAST|WEST) & ~direction_mask
				pipe = supply ? new /obj/machinery/atmospherics/pipe/manifold/hidden/supply/generated_station(T, missing_direction) : new /obj/machinery/atmospherics/pipe/manifold/hidden/scrubbers/generated_station(T, missing_direction)
			if(4)
				pipe = supply ? new /obj/machinery/atmospherics/pipe/manifold4w/hidden/supply(T) : new /obj/machinery/atmospherics/pipe/manifold4w/hidden/scrubbers(T)
		if(pipe)
			result.atmos_objects += pipe

/datum/generated_station_utility_builder/proc/initialize_global_atmos()
	for(var/obj/machinery/atmospherics/AM in result.atmos_objects)
		AM.atmos_init()
	for(var/obj/machinery/atmospherics/AM in result.atmos_objects)
		AM.rust_allocate_pipe_ports()
	for(var/obj/machinery/atmospherics/AM in result.atmos_objects)
		AM.rust_register_pipe_port_data()
	for(var/obj/machinery/atmospherics/AM in result.atmos_objects)
		AM.rust_register_pipe_edges()
	SSair.rust_commit_pending_pipenets()
	for(var/obj/machinery/atmospherics/pipe/tank/air/full/generated_station/tank in result.supply_tanks)
		var/datum/pipe_network/network = tank.parent?.network
		if(!network?.air)
			continue
		var/datum/gas_mixture/network_air = network.air
		if(!network_air.total_moles())
			network_air.set_temperature(T20C)
			var/supply_moles = MOLES_CELLSTANDARD * (network_air.return_volume() / CELL_VOLUME) * 50
			network_air.adjust_multi(GAS_O2, supply_moles * O2STANDARD, GAS_N2, supply_moles * N2STANDARD)
		network.mark_dirty()
		network.process()

/datum/expedition_site
	var/datum/generated_station_utility_topology/station_utilities

/datum/expedition_site/proc/initialize_generated_station_utilities()
	if(!station_spec || !station_materialization || station_utilities)
		return FALSE
	var/datum/generated_station_utility_builder/builder = new
	station_utilities = builder.build(station_spec, station_materialization)
	qdel(builder)
	return !!station_utilities
