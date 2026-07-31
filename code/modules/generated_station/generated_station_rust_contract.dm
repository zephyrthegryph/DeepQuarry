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

/// Builds the authoritative fixture registry without stringifying type paths.
/// Rust sees stable semantic IDs; DM retains the corresponding compile-time
/// type paths for safe materialization.
/proc/generated_station_rust_fixture_registry()
	var/list/registry = list()
	var/list/catalog = generated_station_department_catalog()
	for(var/datum/generated_station_department_definition/department in catalog)
		for(var/role in generated_station_rust_room_roles(department.id))
			var/datum/generated_room_definition/definition = generated_room_definition_for(department.id, role)
			for(var/fragment_type in definition?.fragment_options)
				if(!ispath(fragment_type, /datum/generated_room_fragment/activity_motif))
					continue
				var/datum/generated_room_fragment/activity_motif/fragment = new fragment_type
				for(var/feature_type in fragment.feature_types)
					var/datum/generated_room_feature/feature = new feature_type
					if(feature.id && feature.atom_type)
						registry[feature.id] = feature.atom_type
					qdel(feature)
				qdel(fragment)
			qdel(definition)
	QDEL_LIST(catalog)
	return registry

/// Every Rust-authored fixture ID is paired with its real game appearance for
/// sprite-accurate previews. Keep this vocabulary in lockstep with
/// generated_station_rust_fixture_type(); an omitted ID becomes an obvious
/// preview failure instead of a misleading generic marker.
/proc/generated_station_rust_fixture_ids()
	return list(
		"operating_table", "anesthetic", "medical_bed", "privacy_screen", "medical_console",
		"instrument_table", "experiment_table", "workbench", "conference_table", "food_prep",
		"serving_counter", "loading_table", "reception_desk", "worktable", "table", "side_table",
		"packing_table", "medical_cabinet", "reagent_storage", "evidence_cabinet", "parts_bin",
		"parts_cabinet", "medicine_cart", "medical_locker", "stool", "analyzer", "plant_analyzer",
		"package_scanner", "role_console", "visitor_console", "control_console", "data_terminal",
		"research_console", "id_console", "robotics_console", "autolathe", "armory_autolathe",
		"electrical_locker", "security_records", "reinforced_table", "chem_master", "reagent_grinder",
		"sleeper", "iv_drip", "medical_vendor", "air_sensor", "supply_console",
		"communications_console", "disposal_unit", "security_console", "flash", "weapon_rack",
		"secure_locker", "department_locker", "locker", "tool_rack", "supply_locker", "chair",
		"waiting_bench", "visitor_bench", "executive_chair", "engineering_console",
		"generator_control", "command_console", "holotable", "filing_cabinet", "manifest_board",
		"notice_board", "grill", "sink", "wash_station", "fridge", "produce_bin", "water_cooler",
		"hydroponics_tray", "seed_extractor", "iv_stand", "water_tank", "freight_cart", "tool_cart",
		"crate_rack", "supply_crate", "pallet", "cargo_bin", "cargo_console", "ai_core",
		"server_rack", "server", "coolant_unit", "plant", "display_case", "shelf",
		"work_chair", "operator_chair", "crew_monitor", "ai_upload", "power_monitor",
		"atmos_control", "equipment_recharger", "charger_table", "engineering_vendor", "air_canister", "oxygen_canister",
	)

/proc/generated_station_rust_sprite_previews()
	var/list/previews = list()
	for(var/fixture_id in generated_station_rust_fixture_ids())
		var/atom/movable/preview_atom_type = generated_station_rust_fixture_type(fixture_id)
		if(!preview_atom_type)
			continue
		previews[fixture_id] = list(
			"icon_file" = "[initial(preview_atom_type.icon)]",
			"icon_state" = "[initial(preview_atom_type.icon_state)]",
		)
	return previews

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
				if(!ispath(fragment_type, /datum/generated_room_fragment/activity_motif))
					continue
				var/datum/generated_room_fragment/activity_motif/fragment = new fragment_type
				var/list/features = list()
				for(var/feature_index in 1 to min(length(fragment.feature_types), length(fragment.occupied_offsets)))
					var/feature_type = fragment.feature_types[feature_index]
					var/datum/generated_room_feature/feature = new feature_type
					var/atom/movable/preview_atom_type = feature.atom_type
					var/list/offset = fragment.occupied_offsets[feature_index]
					features += list(list(
						"id" = feature.id,
						"dx" = offset[1],
						"dy" = offset[2],
						"placement_kind" = feature.placement_kind,
						"icon_file" = "[initial(preview_atom_type.icon)]",
						"icon_state" = "[initial(preview_atom_type.icon_state)]",
					))
					qdel(feature)
				fragments += list(list(
					"id" = fragment.id,
					"width" = fragment.width,
					"height" = fragment.height,
					"allow_rotation" = fragment.allow_rotation,
					"allow_mirroring" = fragment.allow_mirroring,
					"anchor_kind" = fragment.anchor_kind,
					"anchor_edge" = generated_station_rust_direction_name(fragment.anchor_edge),
					"occupied_offsets" = fragment.occupied_offsets.Copy(),
					"features" = features,
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
				// The signature role is guaranteed at full scale. Other required
				// semantics are guaranteed through their compact-capable variants
				// below, allowing Rust to choose full geometry when space permits.
				"min_count" = role_index == 1 ? 1 : 0,
				"max_count" = role_index == 1 ? 1 : 3,
				"entrances" = definition.min_entrances,
				// Rust owns room allocation, so it must receive the complete authored
				// capacity contract. Capping this at 21 let a 7x7 program be assigned
				// to a 40-tile room which DM could only reject during materialization.
				"content_area" = definition.min_width * definition.min_height,
				"minimum_usable_tiles" = definition.min_width * definition.min_height,
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
			// Compact contracts are first-class planner options, not a DM rescue.
			// They let Rust intentionally assign a small residual bay while keeping
			// the same semantic role and its role-defining compact furnishings.
			rooms += list(list(
				"id" = "[department.id]-[role]-compact",
				"department_id" = department.id,
				"definition_id" = "[department.id]-compact-[role]",
				"role" = role,
				"min_width" = 3,
				"max_width" = 7,
				"min_height" = 3,
				"max_height" = 7,
				"min_entrances" = 1,
				"max_entrances" = 1,
				"min_count" = 0,
				"max_count" = 3,
				"entrances" = 1,
				// Two role-defining fixtures, a door route, and a utility socket cannot
				// coexist in a 2x2 footprint. Rust must reserve real usable capacity.
				"content_area" = definition.requires_center_activity ? 12 : 9,
				"minimum_usable_tiles" = definition.requires_center_activity ? 12 : 9,
				"ideal_usable_tiles" = definition.requires_center_activity ? 16 : 12,
				"min_short_side" = 2,
				"max_aspect_ratio_millis" = 6000,
				"requires_center_activity" = definition.requires_center_activity,
				"density_min_micros" = 250000,
				"density_max_micros" = 700000,
				"circulation_min_micros" = 200000,
				"wall_utilization_micros" = 0,
				"aesthetic_id" = definition.room_style.aesthetic_id,
				"fragments" = list(),
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
		"sprite_previews" = generated_station_rust_sprite_previews(),
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
	var/list/content_room_rows = root["content_rooms"]
	var/list/fixture_rows = root["fixtures"]
	var/list/network_rows = root["networks"]
	if(!islist(metadata) || !islist(department_rows) || !islist(node_rows) || !islist(room_rows) || !islist(door_rows) || !islist(edge_rows) || !islist(tile_rows) || !islist(content_room_rows) || !islist(fixture_rows) || !islist(network_rows))
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
			var/datum/generated_room_definition/full_definition = generated_room_definition_for(room_department.definition.id, row["role"])
			var/compact_definition_id = "[room_department.definition.id]-compact-[row["role"]]"
			if(full_definition?.id == row["definition_id"])
				room_definition = full_definition
				full_definition = null
			else if(row["definition_id"] == compact_definition_id)
				room_definition = generated_compact_room_definition_for(room_department.definition.id, row["role"])
			else if(row["definition_id"] == "[room_department.definition.id]-micro-[row["role"]]")
				room_definition = generated_micro_room_definition_for(room_department.definition.id, row["role"])
			qdel(full_definition)
		var/list/allowed_roles = room_department ? generated_station_rust_room_roles(room_department.definition.id) : list()
		var/valid_room_definition = room_definition && (row["role"] in allowed_roles) && room_definition.id == row["definition_id"]
		qdel(room_definition)
		if(!istext(id) || !length(id))
			return generated_station_rust_decode_failure(spec, errors, "Room record has no valid ID.")
		if(rooms[id])
			return generated_station_rust_decode_failure(spec, errors, "Room record duplicates ID [id].")
		if(!node)
			return generated_station_rust_decode_failure(spec, errors, "Room [id] references unknown node [row["node_id"]].")
		if(!valid_room_definition)
			return generated_station_rust_decode_failure(spec, errors, "Room [id] uses invalid definition [row["definition_id"]] for role [row["role"]] in [room_department?.definition?.id].")
		if(!generated_station_rust_integer(row["frontage_x"], 1, width) || !generated_station_rust_integer(row["frontage_y"], 1, height))
			return generated_station_rust_decode_failure(spec, errors, "Room [id] has invalid frontage [row["frontage_x"]],[row["frontage_y"]].")
		var/datum/generated_station_room_allocation/room = new
		room.id = id; room.department_node_id = node.id; room.role = row["role"]; room.definition_id = row["definition_id"]
		room.rust_room_id = row["rust_room_id"]
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
	if(!generated_station_rust_decode_content(spec, rooms, content_room_rows, fixture_rows, network_rows, root["content_quality"], errors))
		qdel(spec)
		return null
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

/proc/generated_station_rust_content_direction(value)
	switch(value)
		if("North") return NORTH
		if("East") return EAST
		if("South") return SOUTH
		if("West") return WEST
	return 0

/// Decodes the Rust-authored furnishing plane. Coordinates in the native
/// blueprint are zero-based; all DM station-local coordinates are one-based.
/proc/generated_station_rust_decode_content(datum/generated_station_spec/spec, list/rooms, list/content_room_rows, list/fixture_rows, list/network_rows, list/quality, list/errors)
	var/list/rooms_by_native_id = list()
	for(var/room_id in rooms)
		var/datum/generated_station_room_allocation/room = rooms[room_id]
		if(!generated_station_rust_integer(room.rust_room_id, 1, 65535) || rooms_by_native_id["[room.rust_room_id]"])
			errors += "Structural room [room.id] has an invalid native Rust room ID."
			return FALSE
		rooms_by_native_id["[room.rust_room_id]"] = room
	for(var/list/row in content_room_rows)
		if(!islist(row) || !generated_station_rust_integer(row["room_id"], 1, 65535))
			errors += "Rust content blueprint contains an invalid room record."
			return FALSE
		var/datum/generated_station_room_allocation/room = rooms_by_native_id["[row["room_id"]]"]
		var/list/center = row["activity_center"]
		var/list/circulation = row["circulation"]
		var/list/fixture_ids = row["fixture_ids"]
		if(!room || !istext(row["semantic_role"]) || row["semantic_role"] != room.role || !istext(row["selected_variant"]) || !length(row["selected_variant"]) || !istext(row["area_name"]) || !length(row["area_name"]) || !istext(row["aesthetic_id"]) || !istext(row["floor_style"]) || !istext(row["accent_style"]) || !islist(center) || !islist(circulation) || !islist(fixture_ids) || !generated_station_rust_integer(row["occupancy_micros"], 0, 1000000))
			errors += "Rust content room [row["room_id"]] does not match its structural allocation."
			return FALSE
		room.selected_variant = row["selected_variant"]
		room.area_name = row["area_name"]
		room.aesthetic_id = row["aesthetic_id"]
		room.floor_style = row["floor_style"]
		room.accent_style = row["accent_style"]
		room.activity_center_x = center["x"] + 1
		room.activity_center_y = center["y"] + 1
		room.occupancy_micros = row["occupancy_micros"]
		for(var/list/point in circulation)
			if(!generated_station_rust_content_point_valid(point, spec.grid_width, spec.grid_height))
				errors += "Rust content room [room.id] has invalid circulation coordinates."
				return FALSE
			room.content_circulation["[point["x"] + 1],[point["y"] + 1]"] = TRUE
		for(var/fixture_id in fixture_ids)
			if(!generated_station_rust_integer(fixture_id, 1, 2147483647))
				errors += "Rust content room [room.id] references an invalid fixture ID."
				return FALSE
			room.fixture_ids += fixture_id
	if(length(content_room_rows) != length(rooms))
		errors += "Rust content blueprint does not describe every structural room."
		return FALSE
	var/list/fixture_ids_seen = list()
	for(var/list/row in fixture_rows)
		var/list/point = row["at"]
		var/direction = generated_station_rust_content_direction(row["facing"])
		var/room_numeric_id = row["room_id"]
		if(!islist(row) || !generated_station_rust_integer(row["id"], 1, 2147483647) || fixture_ids_seen["[row["id"]]"] || !istext(row["fixture_id"]) || !length(row["fixture_id"]) || !generated_station_rust_content_point_valid(point, spec.grid_width, spec.grid_height) || !direction || !(row["layer"] in list("Floor", "Furniture", "Machine", "Wall", "Ceiling")) || (room_numeric_id && !rooms_by_native_id["[room_numeric_id]"]) || !generated_station_rust_integer(row["variant"], 0, 65535) || !islist(row["required_access"]))
			errors += "Rust content blueprint contains an invalid fixture record."
			return FALSE
		var/datum/generated_station_fixture_placement/fixture = new
		fixture.id = row["id"]
		fixture.fixture_id = row["fixture_id"]
		fixture.x = point["x"] + 1
		fixture.y = point["y"] + 1
		fixture.direction = direction
		fixture.layer = row["layer"]
		fixture.department_numeric_id = row["department_id"]
		fixture.room_numeric_id = room_numeric_id
		fixture.network_id = row["network_id"]
		fixture.variant = row["variant"]
		fixture.blocks_movement = !!row["blocks_movement"]
		for(var/list/access_point in row["required_access"])
			if(!generated_station_rust_content_point_valid(access_point, spec.grid_width, spec.grid_height))
				qdel(fixture)
				errors += "Rust fixture [row["id"]] has invalid access coordinates."
				return FALSE
			fixture.required_access["[access_point["x"] + 1],[access_point["y"] + 1]"] = TRUE
		fixture_ids_seen["[fixture.id]"] = TRUE
		spec.fixture_blueprint += fixture
	for(var/list/row in network_rows)
		if(!islist(row) || !istext(row["id"]) || !length(row["id"]) || !istext(row["kind"]) || !length(row["kind"]) || !islist(row["backbone"]) || !islist(row["endpoint_fixture_ids"]))
			errors += "Rust content blueprint contains an invalid network record."
			return FALSE
		var/datum/generated_station_network_blueprint/network = new
		network.id = row["id"]
		network.kind = row["kind"]
		for(var/list/point in row["backbone"])
			if(!generated_station_rust_content_point_valid(point, spec.grid_width, spec.grid_height))
				qdel(network)
				errors += "Rust network [row["id"]] has invalid backbone coordinates."
				return FALSE
			network.backbone += list(list(point["x"] + 1, point["y"] + 1))
		for(var/fixture_id in row["endpoint_fixture_ids"])
			if(!fixture_ids_seen["[fixture_id]"])
				qdel(network)
				errors += "Rust network [row["id"]] references an unknown endpoint fixture."
				return FALSE
			network.endpoint_fixture_ids += fixture_id
		spec.network_blueprint += network
	spec.content_quality = islist(quality) ? quality.Copy() : list()
	return TRUE

/proc/generated_station_rust_content_point_valid(list/point, width, height)
	return islist(point) && generated_station_rust_integer(point["x"], 0, width - 1) && generated_station_rust_integer(point["y"], 0, height - 1)

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
