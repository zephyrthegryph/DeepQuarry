#define GENERATED_STATION_RUST_SCHEMA "dq.station.plan"
#define GENERATED_STATION_RUST_MAJOR 1
#define GENERATED_STATION_RUST_MINOR 0

/proc/generated_station_rust_room_roles(department_id)
	switch(department_id)
		if("command")
			return list("reception", "operations", "communications", "meeting", "briefing", "records", "liaison", "archive")
		if("ai")
			return list("foyer", "core", "satellite", "support", "robotics", "monitoring", "secure-storage", "server-closet")
		if("security")
			return list("reception", "operations", "brig", "armory", "interrogation", "evidence", "locker-room", "checkpoint")
		if("medical")
			return list("reception", "treatment", "surgery", "ward", "pharmacy", "recovery", "storage", "exam")
		if("engineering")
			return list("foyer", "power", "atmospherics", "workshop", "equipment", "maintenance", "storage", "tool-room")
		if("logistics")
			return list("reception", "cargo", "processing", "warehouse", "dispatch", "sorting", "storage", "inventory")
		if("docking")
			return list("reception", "control", "berth", "security", "customs", "lounge", "equipment", "supply")
	return list("reception", "control", "support")

/proc/generated_station_rust_metadata(seed, width, height)
	var/datum/generated_station_prng/prng = new(seed)
	var/static/list/styles = list("industrial", "sterile", "fortified")
	var/static/list/factions = list("corporate", "military", "research", "salvage")
	var/list/metadata = list(
		"station_id" = "station-[num2text(round(seed), 20)]",
		"name" = generated_station_designation(seed),
		"architecture_style" = styles[prng.next_range(1, length(styles))],
		"faction_id" = factions[prng.next_range(1, length(factions))],
		"security_tier" = prng.next_range(1, 3),
		"size_class" = width * height < 3600 ? "compact" : (width * height > 6400 ? "large" : "standard"),
	)
	qdel(prng)
	return metadata

/// Stable catalog/settings request for the Rust geometry planner. DM type paths
/// are deliberately resolved here and never cross the wire.
/proc/generated_station_rust_catalog_request(seed, width, height, list/catalog_override, list/settings_override)
	var/static/list/template_cache = list()
	var/cache_key = "[width]x[height]"
	if(!islist(catalog_override) && !islist(settings_override) && template_cache[cache_key])
		var/list/cached_request = template_cache[cache_key]
		var/list/cached_instance = cached_request.Copy()
		cached_instance["seed"] = num2text(round(seed), 20)
		cached_instance["metadata"] = generated_station_rust_metadata(seed, width, height)
		var/cached_canonical = json_encode(cached_instance)
		cached_instance["catalog_hash"] = rustg_hash_string(RUSTG_HASH_SHA256, cached_canonical)
		return json_encode(cached_instance)
	var/list/departments = list()
	var/list/rooms = list()
	var/owns_catalog = !islist(catalog_override)
	var/list/catalog = owns_catalog ? generated_station_department_catalog() : catalog_override
	for(var/datum/generated_station_department_definition/department in catalog)
		var/list/requires = list()
		var/list/provides = list()
		for(var/datum/generated_station_capability_requirement/requirement in department.requirements)
			requires += list(list("id" = requirement.capability_id, "amount" = requirement.amount, "optional" = requirement.optional))
		for(var/datum/generated_station_capability_provision/provision in department.provisions)
			provides += list(list("id" = provision.capability_id, "amount" = provision.amount))
		var/list/roles = generated_station_rust_room_roles(department.id)
		departments += list(list(
			"id" = department.id,
			"definition_id" = department.id,
			"name" = department.name,
			"weight" = department.critical ? 2 : 1,
			"critical" = department.critical,
			"minimum_area" = department.minimum_area,
			"maximum_area" = department.maximum_area,
			"requires" = requires,
			"provides" = provides,
			"room_roles" = roles.Copy(),
		))
		for(var/role_index in 1 to length(roles))
			var/role = roles[role_index]
			var/datum/generated_room_definition/definition = generated_room_definition_for(department.id, role)
			if(!definition)
				continue
			var/list/fragments = list()
			for(var/fragment_type in definition.fragment_options)
				var/datum/generated_room_fragment/fragment = new fragment_type
				fragments += list(list(
					"id" = fragment.id,
					"width" = fragment.width,
					"height" = fragment.height,
					"allow_rotation" = fragment.allow_rotation,
					"allow_mirroring" = fragment.allow_mirroring,
					"anchor_kind" = fragment.anchor_kind,
					"anchor_edge" = generated_station_rust_direction_name(fragment.anchor_edge),
					"occupied_offsets" = fragment.occupied_offsets.Copy(),
				))
				qdel(fragment)
			rooms += list(list(
				"id" = "[department.id]-[role]",
				"department_id" = department.id,
				"definition_id" = definition.id,
				"role" = role,
				"min_width" = definition.min_width,
				"max_width" = definition.max_width,
				"min_height" = definition.min_height,
				"max_height" = definition.max_height,
				"min_entrances" = definition.min_entrances,
				"max_entrances" = definition.max_entrances,
				"min_count" = role_index <= 4 ? 1 : 0,
				"max_count" = role_index <= 4 ? 1 : 3,
				"entrances" = definition.min_entrances,
				"content_area" = min(definition.min_width * definition.min_height, 21),
				"minimum_usable_tiles" = min(definition.min_width * definition.min_height, 21),
				"ideal_usable_tiles" = definition.ideal_usable_tiles,
				"min_short_side" = definition.min_short_side,
				"max_aspect_ratio_millis" = definition.max_aspect_ratio_millis,
				"requires_center_activity" = definition.requires_center_activity,
				"density_min_micros" = round(definition.density_min * 1000000),
				"density_max_micros" = round(definition.density_max * 1000000),
				"circulation_min_micros" = round(definition.circulation_min * 1000000),
				"wall_utilization_micros" = round(definition.wall_utilization_target * 1000000),
				"aesthetic_id" = definition.room_style.aesthetic_id,
				"fragments" = fragments,
			))
			qdel(definition)
	var/list/settings = list(
		"hull_thickness" = 1,
		"corridor_width" = 2,
		"maintenance_width" = 2,
		"candidate_count" = 24,
		"room_jitter" = 3,
		"architecture_choices" = list("cross", "ring", "bent", "branch", "courtyard"),
	)
	if(islist(settings_override))
		for(var/key in settings_override)
			settings[key] = settings_override[key]
	var/list/request = list(
		"schema" = "dq.station.catalog",
		"major" = GENERATED_STATION_RUST_MAJOR,
		"minor" = GENERATED_STATION_RUST_MINOR,
		"seed" = num2text(round(seed), 20),
		"width" = width,
		"height" = height,
		"metadata" = generated_station_rust_metadata(seed, width, height),
		"settings" = settings,
		"departments" = departments,
		"rooms" = rooms,
	)
	if(!islist(catalog_override) && !islist(settings_override))
		var/list/template = request.Copy()
		template["seed"] = null
		template["metadata"] = null
		template_cache[cache_key] = template
	var/canonical = json_encode(request)
	request["catalog_hash"] = rustg_hash_string(RUSTG_HASH_SHA256, canonical)
	if(owns_catalog)
		QDEL_LIST(catalog)
	return json_encode(request)

/proc/generated_station_rust_direction_name(direction)
	switch(direction)
		if(NORTH) return "N"
		if(EAST) return "E"
		if(SOUTH) return "S"
		if(WEST) return "W"
	return null

/proc/generated_station_rust_direction(value)
	switch(value)
		if("N") return NORTH
		if("E") return EAST
		if("S") return SOUTH
		if("W") return WEST
	return 0

/proc/generated_station_rust_integer(value, minimum, maximum)
	return isnum(value) && value == round(value) && value >= minimum && value <= maximum

/proc/generated_station_rust_edge_kind(value)
	switch(value)
		if("transit") return GENERATED_STATION_EDGE_TRANSIT
		if("adjacent") return GENERATED_STATION_EDGE_ADJACENT
		if("utility") return GENERATED_STATION_EDGE_UTILITY
	return 0

/// Strict response decoder. On failure it returns null and appends a diagnostic
/// to errors. The reconstructed spec still passes the normal DM validator.
/proc/generated_station_spec_from_rust_json(payload, expected_catalog_hash, list/errors)
	if(!islist(errors))
		return null
	var/list/root
	if(islist(payload))
		root = payload
	else
		try
			root = json_decode(payload)
		catch(var/exception/error)
			errors += "Rust station response is not valid JSON: [error]"
			return null
	if(!islist(root) || root["schema"] != GENERATED_STATION_RUST_SCHEMA || root["major"] != GENERATED_STATION_RUST_MAJOR)
		errors += "Rust station response has an unsupported schema version."
		return null
	if(expected_catalog_hash && root["catalog_hash"] != expected_catalog_hash)
		errors += "Rust station response catalog hash does not match the request."
		return null
	var/width = root["width"]
	var/height = root["height"]
	var/seed_text = root["seed"]
	var/seed = istext(seed_text) ? text2num(seed_text) : null
	if(!istext(seed_text) || !length(seed_text) || !generated_station_rust_integer(seed, 1, 2147483647) || num2text(seed, 20) != seed_text)
		errors += "Rust station response seed is not a canonical positive integer string."
		return null
	if(!generated_station_rust_integer(width, 16, 256) || !generated_station_rust_integer(height, 16, 256))
		errors += "Rust station response dimensions are invalid."
		return null
	var/list/metadata = root["metadata"]
	var/list/department_rows = root["departments"]
	var/list/node_rows = root["nodes"]
	var/list/room_rows = root["rooms"]
	var/list/door_rows = root["doors"]
	var/list/edge_rows = root["edges"]
	var/list/tile_rows = root["tile_rows"]
	if(!islist(metadata) || !islist(department_rows) || !islist(node_rows) || !islist(room_rows) || !islist(door_rows) || !islist(edge_rows) || !islist(tile_rows))
		errors += "Rust station response is missing a required record section."
		return null
	var/datum/generated_station_spec/spec = new
	if(!istext(metadata["station_id"]) || !length(metadata["station_id"]) || !istext(metadata["name"]) || !length(metadata["name"]) || !istext(metadata["architecture_style"]) || !length(metadata["architecture_style"]) || !istext(metadata["faction_id"]) || !length(metadata["faction_id"]) || !generated_station_rust_integer(metadata["security_tier"], 0, 100) || !istext(metadata["size_class"]) || !length(metadata["size_class"]) || !istext(metadata["layout_archetype"]) || !length(metadata["layout_archetype"]) || !isnum(metadata["aesthetic_score"]))
		return generated_station_rust_decode_failure(spec, errors, "Rust station metadata contains invalid fields.")
	spec.id = metadata["station_id"]
	spec.name = metadata["name"]
	spec.seed = seed
	spec.grid_width = width
	spec.grid_height = height
	spec.maximum_area = width * height
	spec.architecture_style = metadata["architecture_style"]
	spec.faction_id = metadata["faction_id"]
	spec.security_tier = metadata["security_tier"]
	spec.size_class = metadata["size_class"]
	spec.layout_archetype = metadata["layout_archetype"]
	spec.layout_aesthetic_score = metadata["aesthetic_score"]
	spec.department_definitions = generated_station_department_catalog()
	var/list/definitions = list()
	for(var/datum/generated_station_department_definition/definition in spec.department_definitions)
		definitions[definition.id] = definition
	var/list/departments = list()
	for(var/list/row in department_rows)
		if(!islist(row))
			return generated_station_rust_decode_failure(spec, errors, "Department section contains a non-record value.")
		var/id = row["id"]
		var/definition_id = row["definition_id"]
		if(!istext(id) || !length(id) || !istext(definition_id) || !length(definition_id) || departments[id] || !definitions[definition_id] || !generated_station_rust_integer(row["desired_area"], 1, width * height) || !istext(row["node_id"]) || !length(row["node_id"]))
			return generated_station_rust_decode_failure(spec, errors, "Invalid or duplicate department record.")
		var/datum/generated_station_department_instance/department = new
		department.id = id
		department.definition = definitions[definition_id]
		department.desired_area = row["desired_area"]
		department.layout_node_id = row["node_id"]
		departments[id] = department
		spec.departments += department
	var/list/nodes = list()
	for(var/list/row in node_rows)
		if(!islist(row))
			return generated_station_rust_decode_failure(spec, errors, "Node section contains a non-record value.")
		var/id = row["id"]
		if(!istext(id) || !length(id) || nodes[id] || !departments[row["department_id"]] || !generated_station_rust_integer(row["desired_area"], 1, width * height) || !generated_station_rust_integer(row["x"], 1, width) || !generated_station_rust_integer(row["y"], 1, height) || !generated_station_rust_integer(row["width"], 1, width) || !generated_station_rust_integer(row["height"], 1, height) || row["x"] + row["width"] - 1 > width || row["y"] + row["height"] - 1 > height || !generated_station_rust_integer(row["frontage_x"], 1, width) || !generated_station_rust_integer(row["frontage_y"], 1, height) || !generated_station_rust_integer(row["frontage_spine_coordinate"], 1, max(width, height)))
			return generated_station_rust_decode_failure(spec, errors, "Invalid or duplicate node record.")
		var/datum/generated_station_layout_node/node = new
		node.id = id
		node.department_instance_id = row["department_id"]
		node.desired_area = row["desired_area"]
		node.x = row["x"]; node.y = row["y"]; node.width = row["width"]; node.height = row["height"]
		node.frontage_x = row["frontage_x"]; node.frontage_y = row["frontage_y"]
		node.frontage_spine_vertical = !!row["frontage_spine_vertical"]
		node.frontage_spine_coordinate = row["frontage_spine_coordinate"]
		nodes[id] = node
		spec.layout_nodes += node
	var/list/rooms = list()
	for(var/list/row in room_rows)
		if(!islist(row))
			return generated_station_rust_decode_failure(spec, errors, "Room section contains a non-record value.")
		var/id = row["id"]
		var/datum/generated_station_layout_node/node = nodes[row["node_id"]]
		var/datum/generated_station_department_instance/room_department
		if(node)
			room_department = departments[node.department_instance_id]
		var/datum/generated_room_definition/room_definition
		if(room_department && istext(row["role"]) && length(row["role"]))
			room_definition = generated_room_definition_for(room_department.definition.id, row["role"])
		var/list/allowed_roles = room_department ? generated_station_rust_room_roles(room_department.definition.id) : list()
		var/valid_room_definition = room_definition && (row["role"] in allowed_roles) && room_definition.id == row["definition_id"]
		qdel(room_definition)
		if(!istext(id) || !length(id) || rooms[id] || !node || !valid_room_definition || !generated_station_rust_integer(row["frontage_x"], 1, width) || !generated_station_rust_integer(row["frontage_y"], 1, height))
			return generated_station_rust_decode_failure(spec, errors, "Invalid or duplicate room record.")
		var/datum/generated_station_room_allocation/room = new
		room.id = id; room.department_node_id = node.id; room.role = row["role"]
		room.frontage_x = row["frontage_x"]; room.frontage_y = row["frontage_y"]
		rooms[id] = room
		node.room_program += room
	var/list/tile_classes = list()
	var/list/tile_owners = list()
	var/list/tile_zones = list()
	var/list/tile_flags = list()
	if(!generated_station_rust_decode_tiles(spec, tile_rows, nodes, rooms, errors, tile_classes, tile_owners, tile_zones, tile_flags))
		qdel(spec)
		return null
	var/list/door_ids = list()
	var/list/door_coordinates = list()
	for(var/list/row in door_rows)
		if(!islist(row) || !istext(row["id"]) || !length(row["id"]) || door_ids[row["id"]])
			return generated_station_rust_decode_failure(spec, errors, "Invalid or duplicate door record.")
		door_ids[row["id"]] = TRUE
		var/direction = generated_station_rust_direction(row["direction"])
		var/datum/generated_station_layout_node/node = nodes[row["owner_id"]]
		var/x = row["x"]
		var/y = row["y"]
		var/key = "[x],[y]"
		if(!direction || !generated_station_rust_integer(x, 1, width) || !generated_station_rust_integer(y, 1, height) || !istext(row["kind"]) || !length(row["kind"]))
			return generated_station_rust_decode_failure(spec, errors, "Door references an invalid owner or direction.")
		if(door_coordinates[key] || !(tile_flags[key] & 1))
			return generated_station_rust_decode_failure(spec, errors, "Door coordinate is duplicated or lacks a door tile flag.")
		door_coordinates[key] = TRUE
		if(row["kind"] == "maintenance")
			if(!node || tile_classes[key] != "maintenance_floor" || !istext(row["from_zone"]) || !length(row["from_zone"]) || !istext(row["to_zone"]) || !length(row["to_zone"]))
				return generated_station_rust_decode_failure(spec, errors, "Maintenance door has invalid ownership or zone metadata.")
			var/datum/generated_station_maintenance_door/maintenance_door = new(direction, node.id, row["from_zone"], row["to_zone"])
			spec.maintenance_doors["[x],[y]"] = maintenance_door
			continue
		if(!node)
			return generated_station_rust_decode_failure(spec, errors, "Door references an unknown node owner.")
		if(tile_owners[key] != node.id)
			return generated_station_rust_decode_failure(spec, errors, "Door tile ownership does not match its node owner.")
		var/datum/generated_station_room_allocation/from_room = rooms[row["from_zone"]]
		if(row["kind"] == "room")
			if(!from_room || from_room.department_node_id != node.id || (tile_zones[key] != from_room.id && tile_zones[key] != node.id))
				return generated_station_rust_decode_failure(spec, errors, "Room door [row["id"]] at [key] has inconsistent owner or zone metadata: from=[row["from_zone"]], tile-zone=[tile_zones[key]], node=[node.id].")
		else if(row["kind"] == "frontage")
			if(row["from_zone"] != node.id || row["to_zone"] != "public-circulation")
				return generated_station_rust_decode_failure(spec, errors, "Frontage door has inconsistent zone metadata.")
		else
			return generated_station_rust_decode_failure(spec, errors, "Door uses an unknown kind.")
		var/datum/generated_station_door_socket/socket = new(x, y, direction, row["kind"], row["from_zone"], row["to_zone"])
		var/datum/generated_station_room_allocation/room = from_room
		if(room)
			room.door_sockets += socket
		else
			var/assigned_vestibule = FALSE
			for(var/datum/generated_station_eva_vestibule/vestibule in node.eva_vestibules)
				if(vestibule.id == row["from_zone"] || vestibule.id == row["to_zone"])
					vestibule.door_sockets += socket
					assigned_vestibule = TRUE
					break
			if(!assigned_vestibule)
				node.frontage_sockets += socket
	var/list/edge_ids = list()
	for(var/list/row in edge_rows)
		var/edge_kind = islist(row) ? generated_station_rust_edge_kind(row["kind"]) : 0
		if(!islist(row) || !istext(row["id"]) || !length(row["id"]) || edge_ids[row["id"]] || !nodes[row["from_node"]] || !nodes[row["to_node"]] || row["from_node"] == row["to_node"] || !edge_kind || !generated_station_rust_integer(row["minimum_width"], 1, max(width, height)) || !islist(row["path"]) || (edge_kind == GENERATED_STATION_EDGE_TRANSIT && !length(row["path"])))
			return generated_station_rust_decode_failure(spec, errors, "Edge references an invalid node.")
		edge_ids[row["id"]] = TRUE
		var/datum/generated_station_layout_edge/edge = new
		edge.id = row["id"]; edge.from_node_id = row["from_node"]; edge.to_node_id = row["to_node"]
		edge.kind = edge_kind; edge.service_id = row["service_id"]; edge.minimum_width = row["minimum_width"]
		edge.required = !!row["required"]; edge.corridor_class = row["corridor_class"]
		for(var/list/point in row["path"])
			if(!islist(point) || length(point) != 2 || !generated_station_rust_integer(point[1], 1, width) || !generated_station_rust_integer(point[2], 1, height))
				return generated_station_rust_decode_failure(spec, errors, "Edge contains an invalid path coordinate.")
			edge.path += list(list(point[1], point[2]))
		spec.layout_edges += edge
	var/datum/generated_station_validation_result/validation = spec.validate()
	if(!validation.is_valid())
		for(var/datum/generated_station_validation_issue/issue in validation.issues)
			if(issue.severity == GENERATED_STATION_ISSUE_ERROR)
				errors += "[issue.code]@[issue.subject_id]: [issue.message]"
		qdel(validation)
		qdel(spec)
		return null
	qdel(validation)
	return spec

/proc/generated_station_rust_decode_tiles(datum/generated_station_spec/spec, list/rows, list/nodes, list/rooms, list/errors, list/tile_classes, list/tile_owners, list/tile_zones, list/tile_flags)
	var/list/seen_rows = list()
	for(var/list/row in rows)
		if(!islist(row))
			errors += "Tile plane contains a non-record row."
			return FALSE
		var/y = row["y"]
		if(!isnum(y) || y < 1 || y > spec.grid_height || seen_rows["[y]"] || !islist(row["runs"]))
			errors += "Invalid or duplicate tile row."
			return FALSE
		seen_rows["[y]"] = TRUE
		var/expected_x = 1
		for(var/list/run in row["runs"])
			if(!islist(run))
				errors += "Tile row [y] contains a non-record run."
				return FALSE
			var/x = run["x"]
			var/run_length = run["len"]
			if(!generated_station_rust_integer(x, 1, spec.grid_width) || x != expected_x || !generated_station_rust_integer(run_length, 1, spec.grid_width) || x + run_length - 1 > spec.grid_width || !generated_station_rust_integer(run["flags"], 0, 63))
				errors += "Tile row [y] has overlapping, gapped, or out-of-bounds RLE."
				return FALSE
			for(var/tile_x in x to x + run_length - 1)
				if(!generated_station_rust_apply_tile(spec, nodes, rooms, tile_x, y, run, errors, tile_classes, tile_owners, tile_zones, tile_flags))
					return FALSE
			expected_x += run_length
		if(expected_x != spec.grid_width + 1)
			errors += "Tile row [y] does not cover the complete width."
			return FALSE
	if(length(seen_rows) != spec.grid_height)
		errors += "Tile plane does not contain exactly one row per coordinate."
		return FALSE
	return TRUE

/proc/generated_station_rust_apply_tile(datum/generated_station_spec/spec, list/nodes, list/rooms, x, y, list/run, list/errors, list/tile_classes, list/tile_owners, list/tile_zones, list/tile_flags)
	var/class = run["class"]
	var/key = "[x],[y]"
	var/datum/generated_station_layout_node/node = nodes[run["owner"]]
	var/datum/generated_station_room_allocation/room = rooms[run["room"]]
	tile_classes[key] = class
	tile_owners[key] = run["owner"]
	tile_zones[key] = run["zone"]
	tile_flags[key] = run["flags"]
	switch(class)
		if("exterior")
			return TRUE
		if("hull", "structural_fill")
			spec.structural_tiles[key] = TRUE
		if("public_circulation")
			spec.circulation_tiles[key] = TRUE
		if("maintenance_floor")
			spec.maintenance_tiles[key] = TRUE
		if("department_floor", "local_circulation", "partition_wall", "eva_floor")
			if(!node)
				errors += "Owned tile [key] references an unknown node."
				return FALSE
			node.territory[key] = TRUE
			if(class == "local_circulation") node.local_circulation[key] = TRUE
			else if(class == "partition_wall") node.partition_walls[key] = TRUE
			else if(class == "eva_floor")
				var/vestibule_id = run["zone"]
				if(!vestibule_id)
					errors += "EVA floor [key] has no vestibule zone."
					return FALSE
				var/datum/generated_station_eva_vestibule/target
				for(var/datum/generated_station_eva_vestibule/candidate in node.eva_vestibules)
					if(candidate.id == vestibule_id)
						target = candidate
						break
				if(!target)
					target = new
					target.id = vestibule_id
					target.department_node_id = node.id
					node.eva_vestibules += target
				target.tiles[key] = TRUE
			else if(room)
				if(room.department_node_id != node.id || run["zone"] != room.id)
					errors += "Department floor [key] has cross-department or inconsistent room ownership."
					return FALSE
				room.tiles[key] = TRUE
			else
				errors += "Department floor [key] has no room classification."
				return FALSE
		else
			errors += "Tile [key] uses unknown class '[class]'."
			return FALSE
	return TRUE

/proc/generated_station_rust_decode_failure(datum/generated_station_spec/spec, list/errors, message)
	errors += message
	qdel(spec)
	return null

#undef GENERATED_STATION_RUST_SCHEMA
#undef GENERATED_STATION_RUST_MAJOR
#undef GENERATED_STATION_RUST_MINOR
