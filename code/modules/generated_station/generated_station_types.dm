/// Authored department contract shared by generated station specifications.
/datum/generated_station_department_definition
	var/id
	var/name = "Unnamed department"
	var/minimum_area = 1
	var/maximum_area = 0
	var/list/requirements
	var/list/provisions
	var/critical = FALSE

/datum/generated_station_department_definition/New()
	..()
	requirements = list()
	provisions = list()

/datum/generated_station_department_definition/Destroy()
	QDEL_LIST(requirements)
	QDEL_LIST(provisions)
	return ..()

/// A capability consumed by a department. Providers may be implemented later
/// by rooms, machinery, networks, or another department.
/datum/generated_station_capability_requirement
	var/capability_id
	var/amount = 1
	var/optional = FALSE

/datum/generated_station_capability_requirement/New(new_capability_id, new_amount = 1, new_optional = FALSE)
	..()
	capability_id = new_capability_id
	amount = new_amount
	optional = new_optional

/// A capability made available to the station dependency graph.
/datum/generated_station_capability_provision
	var/capability_id
	var/amount = 1

/datum/generated_station_capability_provision/New(new_capability_id, new_amount = 1)
	..()
	capability_id = new_capability_id
	amount = new_amount

/// Per-station realization of an authored department definition.
/datum/generated_station_department_instance
	var/id
	var/datum/generated_station_department_definition/definition
	var/desired_area = 1
	var/layout_node_id

/datum/generated_station_department_instance/Destroy()
	definition = null
	return ..()

/// Abstract layout vertex. Geometry generation consumes this graph later.
/datum/generated_station_layout_node
	var/id
	var/kind = GENERATED_STATION_NODE_DEPARTMENT
	var/department_instance_id
	var/desired_area = 1
	var/x = 0
	var/y = 0
	var/width = 0
	var/height = 0
	/// Circulation-facing tile selected before this department claims any floor area.
	var/frontage_x = 0
	var/frontage_y = 0
	/// Two-wide local-spine strip reserved before territory exclusions are applied.
	var/list/frontage_reservation
	var/frontage_spine_vertical = FALSE
	var/frontage_spine_coordinate = 0
	/// Sparse set of planner-local tiles owned by this department.
	var/list/territory
	/// Walkable department-local circulation. These cells never belong to a room.
	var/list/local_circulation
	/// One-cell structural partitions between rooms and local circulation.
	var/list/partition_walls
	/// Door sockets connecting the department to public circulation.
	var/list/frontage_sockets
	/// Exterior EVA vestibules reserved before room partitioning.
	var/list/eva_vestibules
	/// Semantic rooms partitioned from the remaining usable territory.
	var/list/room_program

/datum/generated_station_layout_node/New()
	..()
	territory = list()
	frontage_reservation = list()
	local_circulation = list()
	partition_walls = list()
	frontage_sockets = list()
	eva_vestibules = list()
	room_program = list()

/datum/generated_station_layout_node/Destroy()
	territory = null
	frontage_reservation = null
	local_circulation = null
	partition_walls = null
	QDEL_LIST(frontage_sockets)
	QDEL_LIST(eva_vestibules)
	QDEL_LIST(room_program)
	return ..()

/datum/generated_station_layout_node/proc/owns_tile(x, y)
	return territory["[x],[y]"]

/// A room allocation is geometry owned by the planner, not a live-map carving instruction.
/datum/generated_station_room_allocation
	var/id
	var/department_node_id
	var/role
	var/frontage_x
	var/frontage_y
	/// Walkable room cells; walls and door cells are represented separately.
	var/list/tiles
	/// Openings through the room boundary into department-local circulation.
	var/list/door_sockets

/datum/generated_station_room_allocation/New()
	..()
	tiles = list()
	door_sockets = list()

/datum/generated_station_room_allocation/Destroy()
	tiles = null
	QDEL_LIST(door_sockets)
	return ..()

/datum/generated_station_room_allocation/proc/add_tile(x, y)
	tiles["[x],[y]"] = TRUE

/// Planner-owned opening through a structural boundary.
/datum/generated_station_door_socket
	var/x
	var/y
	var/direction
	var/kind = "room"
	var/from_zone_id
	var/to_zone_id

/datum/generated_station_door_socket/New(new_x, new_y, new_direction, new_kind = "room", new_from_zone_id = null, new_to_zone_id = null)
	..()
	x = new_x
	y = new_y
	direction = new_direction
	kind = new_kind
	from_zone_id = new_from_zone_id
	to_zone_id = new_to_zone_id

/// Semantic maintenance opening emitted by the authoritative layout planner.
/datum/generated_station_maintenance_door
	var/direction
	var/owner_node_id
	var/from_zone_id
	var/to_zone_id

/datum/generated_station_maintenance_door/New(new_direction, new_owner_node_id, new_from_zone_id, new_to_zone_id)
	..()
	direction = new_direction
	owner_node_id = new_owner_node_id
	from_zone_id = new_from_zone_id
	to_zone_id = new_to_zone_id

/// Reserved pressure-safe transition at an exterior-facing department boundary.
/datum/generated_station_eva_vestibule
	var/id
	var/department_node_id
	var/list/tiles
	var/list/door_sockets

/datum/generated_station_eva_vestibule/New()
	..()
	tiles = list()
	door_sockets = list()

/datum/generated_station_eva_vestibule/Destroy()
	tiles = null
	QDEL_LIST(door_sockets)
	return ..()

/// Abstract relationship between two layout vertices.
/datum/generated_station_layout_edge
	var/id
	var/from_node_id
	var/to_node_id
	var/kind = GENERATED_STATION_EDGE_ADJACENT
	var/service_id
	var/minimum_width = 1
	var/required = TRUE
	/// Public circulation hierarchy used by materialization and diagnostics.
	var/corridor_class = "connector"
	var/list/path

/datum/generated_station_layout_edge/New()
	..()
	path = list()

/datum/generated_station_layout_edge/Destroy()
	path = null
	return ..()

/// One actionable validation finding.
/datum/generated_station_validation_issue
	var/severity = GENERATED_STATION_ISSUE_ERROR
	var/code
	var/message
	var/subject_id

/datum/generated_station_validation_issue/New(new_severity, new_code, new_message, new_subject_id)
	..()
	severity = new_severity
	code = new_code
	message = new_message
	subject_id = new_subject_id

/// Immutable-by-convention result returned by station specification validation.
/datum/generated_station_validation_result
	var/list/issues

/datum/generated_station_validation_result/New()
	..()
	issues = list()

/datum/generated_station_validation_result/Destroy()
	QDEL_LIST(issues)
	return ..()

/datum/generated_station_validation_result/proc/add(severity, code, message, subject_id = null)
	issues += new /datum/generated_station_validation_issue(severity, code, message, subject_id)

/datum/generated_station_validation_result/proc/is_valid()
	for(var/datum/generated_station_validation_issue/issue in issues)
		if(issue.severity == GENERATED_STATION_ISSUE_ERROR)
			return FALSE
	return TRUE

/datum/generated_station_validation_result/proc/count_severity(severity)
	var/count = 0
	for(var/datum/generated_station_validation_issue/issue in issues)
		if(issue.severity == severity)
			count++
	return count

/// Complete declarative input to a future station layout/materialization pass.
/datum/generated_station_spec
	var/id
	var/name = "Generated Station"
	var/seed
	var/maximum_area = 0
	var/grid_width = 0
	var/grid_height = 0
	var/architecture_style = "industrial"
	var/faction_id = "independent"
	var/security_tier = 1
	var/size_class = "standard"
	/// Macro circulation pattern selected by the layout candidate scorer.
	var/layout_archetype = "offset_loop"
	/// Unitless quality score used for diagnostics and deterministic candidate selection.
	var/layout_aesthetic_score = 0
	/// Orientation of the dominant public circulation route.
	var/primary_corridor_axis = "network"
	var/list/department_definitions
	var/list/departments
	var/list/layout_nodes
	var/list/layout_edges
	/// Immutable-by-convention public circulation mask established before departments.
	var/list/circulation_tiles
	/// Back-of-house walkable topology, physically distinct from public halls.
	var/list/maintenance_tiles
	/// Maintenance floor coordinates containing access airlocks.
	var/list/maintenance_doors
	/// Interstitial coordinates deliberately classified as structural mass.
	var/list/structural_tiles

/datum/generated_station_spec/New()
	..()
	departments = list()
	department_definitions = list()
	layout_nodes = list()
	layout_edges = list()
	circulation_tiles = list()
	maintenance_tiles = list()
	maintenance_doors = list()
	structural_tiles = list()

/datum/generated_station_spec/Destroy()
	QDEL_LIST(departments)
	QDEL_LIST(department_definitions)
	QDEL_LIST(layout_nodes)
	QDEL_LIST(layout_edges)
	circulation_tiles = null
	maintenance_tiles = null
	QDEL_LIST_ASSOC_VAL(maintenance_doors)
	structural_tiles = null
	return ..()

/datum/generated_station_spec/proc/validate()
	var/datum/generated_station_validation_result/result = new
	var/list/department_ids = list()
	var/list/node_ids = list()
	var/list/edge_ids = list()
	var/list/provided_capabilities = list()
	var/list/territory_owners = list()
	var/total_area = 0
	for(var/datum/generated_station_department_instance/department in departments)
		if(!department.id || department_ids[department.id])
			result.add(GENERATED_STATION_ISSUE_ERROR, "department-id", "Department instance IDs must be present and unique.", department.id)
		else
			department_ids[department.id] = TRUE
		if(!department.definition?.id)
			result.add(GENERATED_STATION_ISSUE_ERROR, "department-definition", "Department instance has no valid definition.", department.id)
			continue
		if(department.desired_area < department.definition.minimum_area)
			result.add(GENERATED_STATION_ISSUE_ERROR, "department-area-minimum", "Department area is below its definition minimum.", department.id)
		if(department.definition.maximum_area > 0 && department.desired_area > department.definition.maximum_area)
			result.add(GENERATED_STATION_ISSUE_ERROR, "department-area-maximum", "Department area exceeds its definition maximum.", department.id)
		total_area += max(0, department.desired_area)
		for(var/datum/generated_station_capability_provision/provision in department.definition.provisions)
			if(provision.capability_id && provision.amount > 0)
				provided_capabilities[provision.capability_id] = (provided_capabilities[provision.capability_id] || 0) + provision.amount
	for(var/datum/generated_station_layout_node/node in layout_nodes)
		if(!node.id || node_ids[node.id])
			result.add(GENERATED_STATION_ISSUE_ERROR, "layout-node-id", "Layout node IDs must be present and unique.", node.id)
		else
			node_ids[node.id] = TRUE
		if(node.kind == GENERATED_STATION_NODE_DEPARTMENT && !department_ids[node.department_instance_id])
			result.add(GENERATED_STATION_ISSUE_ERROR, "layout-node-department", "Department node references an unknown department instance.", node.id)
		if(node.width <= 0 || node.height <= 0 || node.x < 1 || node.y < 1 || (grid_width > 0 && node.x + node.width - 1 > grid_width) || (grid_height > 0 && node.y + node.height - 1 > grid_height))
			result.add(GENERATED_STATION_ISSUE_ERROR, "layout-node-bounds", "Layout node rectangle is invalid or outside the station grid.", node.id)
		if(!length(node.territory))
			result.add(GENERATED_STATION_ISSUE_ERROR, "layout-node-territory", "Department node has no spatial territory.", node.id)
		if(!node.owns_tile(node.frontage_x, node.frontage_y))
			result.add(GENERATED_STATION_ISSUE_ERROR, "layout-node-frontage", "Department frontage is not owned by its territory.", node.id)
		var/list/room_owners = list()
		var/list/classified_tiles = list()
		for(var/tile_key in node.local_circulation)
			if(!node.territory[tile_key])
				result.add(GENERATED_STATION_ISSUE_ERROR, "circulation-outside-territory", "Department circulation leaves its territory at [tile_key].", node.id)
			classified_tiles[tile_key] = "circulation"
		for(var/tile_key in node.partition_walls)
			if(!node.territory[tile_key])
				result.add(GENERATED_STATION_ISSUE_ERROR, "partition-outside-territory", "Department partition leaves its territory.", node.id)
			if(classified_tiles[tile_key])
				result.add(GENERATED_STATION_ISSUE_ERROR, "spatial-class-overlap", "A department tile has conflicting spatial classifications.", node.id)
			classified_tiles[tile_key] = "partition"
		for(var/datum/generated_station_eva_vestibule/vestibule in node.eva_vestibules)
			for(var/tile_key in vestibule.tiles)
				if(!node.territory[tile_key])
					result.add(GENERATED_STATION_ISSUE_ERROR, "eva-outside-territory", "EVA vestibule leaves its department territory.", vestibule.id)
				if(classified_tiles[tile_key])
					result.add(GENERATED_STATION_ISSUE_ERROR, "spatial-class-overlap", "Department tile [tile_key] is already classified as [classified_tiles[tile_key]] before EVA reservation.", vestibule.id)
				classified_tiles[tile_key] = "eva"
		for(var/datum/generated_station_room_allocation/room in node.room_program)
			if(!length(room.tiles))
				result.add(GENERATED_STATION_ISSUE_ERROR, "room-program-empty", "Planned room has no owned floor tiles.", room.id)
			for(var/tile_key in room.tiles)
				if(!node.territory[tile_key])
					result.add(GENERATED_STATION_ISSUE_ERROR, "room-outside-territory", "Planned room claims a tile outside its department.", room.id)
				if(room_owners[tile_key])
					result.add(GENERATED_STATION_ISSUE_ERROR, "room-overlap", "Two planned rooms claim the same tile.", node.id)
				if(classified_tiles[tile_key])
					result.add(GENERATED_STATION_ISSUE_ERROR, "spatial-class-overlap", "A room consumes a reserved circulation, wall, or EVA tile.", room.id)
				room_owners[tile_key] = room.id
				classified_tiles[tile_key] = "room"
		for(var/tile_key in node.territory)
			if(territory_owners[tile_key])
				result.add(GENERATED_STATION_ISSUE_ERROR, "territory-overlap", "Two departments claim the same spatial tile.", node.id)
			territory_owners[tile_key] = node.id
			if(!classified_tiles[tile_key])
				result.add(GENERATED_STATION_ISSUE_ERROR, "territory-unclassified", "Department tile [tile_key] has no room, circulation, wall, or vestibule classification.", node.id)
	for(var/datum/generated_station_department_instance/department in departments)
		if(!department.layout_node_id || !node_ids[department.layout_node_id])
			result.add(GENERATED_STATION_ISSUE_ERROR, "department-layout-node", "Department instance references an unknown layout node.", department.id)
		if(!department.definition)
			continue
		for(var/datum/generated_station_capability_requirement/requirement in department.definition.requirements)
			if(!requirement.capability_id || requirement.amount <= 0)
				result.add(GENERATED_STATION_ISSUE_ERROR, "capability-requirement", "Capability requirement is malformed.", department.id)
				continue
			if((provided_capabilities[requirement.capability_id] || 0) < requirement.amount)
				var/severity = requirement.optional ? GENERATED_STATION_ISSUE_WARNING : GENERATED_STATION_ISSUE_ERROR
				result.add(severity, "capability-missing", "Required station capability '[requirement.capability_id]' is not sufficiently provided.", department.id)
	for(var/datum/generated_station_layout_edge/edge in layout_edges)
		if(!edge.id || edge_ids[edge.id])
			result.add(GENERATED_STATION_ISSUE_ERROR, "layout-edge-id", "Layout edge IDs must be present and unique.", edge.id)
		else
			edge_ids[edge.id] = TRUE
		if(!node_ids[edge.from_node_id] || !node_ids[edge.to_node_id])
			result.add(GENERATED_STATION_ISSUE_ERROR, "layout-edge-endpoint", "Layout edge references an unknown endpoint.", edge.id)
		if(edge.from_node_id == edge.to_node_id)
			result.add(GENERATED_STATION_ISSUE_ERROR, "layout-edge-self", "Layout edge cannot connect a node to itself.", edge.id)
		if(edge.kind == GENERATED_STATION_EDGE_TRANSIT && !length(edge.path))
			result.add(GENERATED_STATION_ISSUE_ERROR, "layout-edge-route", "Transit edge has no routed corridor path.", edge.id)
	var/list/reachable = list()
	if(length(layout_nodes))
		var/datum/generated_station_layout_node/start = layout_nodes[1]
		var/list/frontier = list(start.id)
		reachable[start.id] = TRUE
		while(length(frontier))
			var/current = frontier[1]
			frontier.Cut(1, 2)
			for(var/datum/generated_station_layout_edge/edge in layout_edges)
				if(edge.kind != GENERATED_STATION_EDGE_TRANSIT)
					continue
				var/other
				if(edge.from_node_id == current)
					other = edge.to_node_id
				else if(edge.to_node_id == current)
					other = edge.from_node_id
				if(other && !reachable[other])
					reachable[other] = TRUE
					frontier += other
		if(length(reachable) != length(layout_nodes))
			result.add(GENERATED_STATION_ISSUE_ERROR, "layout-disconnected", "Transit graph does not connect every layout node.", id)
	if(maximum_area > 0 && total_area > maximum_area)
		result.add(GENERATED_STATION_ISSUE_ERROR, "station-area-maximum", "Department area exceeds the station specification maximum.", id)
	return result
#define GENERATED_STATION_TILE_EXTERIOR "exterior"
#define GENERATED_STATION_TILE_FLOOR "floor"
#define GENERATED_STATION_TILE_HULL "hull"
