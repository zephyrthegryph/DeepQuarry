/datum/unit_test/dq_generated_station_rust_catalog_is_canonical

/datum/unit_test/dq_generated_station_rust_catalog_is_canonical/Run()
	var/first = generated_station_rust_catalog_request(987654, 96, 96)
	var/second = generated_station_rust_catalog_request(987654, 96, 96)
	TEST_ASSERT_EQUAL(first, second, "Identical Rust planner requests did not serialize canonically")
	var/list/request = json_decode(first)
	rustg_file_write(first, "[GLOB.log_directory]/generated-station-rust-catalog-fixture.json")
	var/list/large_seed_request = json_decode(generated_station_rust_catalog_request(900059001, 96, 96))
	TEST_ASSERT_EQUAL(large_seed_request["seed"], num2text(round(900059001), 20), "Large station seeds must serialize as canonical decimal integers")
	TEST_ASSERT_EQUAL(request["schema"], "dq.station.catalog", "Catalog request has the wrong schema")
	TEST_ASSERT(length(request["departments"]) >= 7, "Catalog request omitted departments")
	TEST_ASSERT(length(request["rooms"]) >= 12, "Catalog request omitted room contracts")
	TEST_ASSERT(request["catalog_hash"], "Catalog request omitted its content hash")
	var/list/metadata = request["metadata"]
	TEST_ASSERT_EQUAL(metadata["station_id"], "station-987654", "Catalog omitted the authoritative station ID")
	TEST_ASSERT(metadata["name"] && metadata["architecture_style"] && metadata["faction_id"] && metadata["size_class"], "Catalog omitted authoritative station metadata")
	var/list/settings = request["settings"]
	TEST_ASSERT_EQUAL(settings["hull_thickness"], 1, "Catalog omitted hull geometry settings")
	TEST_ASSERT_EQUAL(settings["corridor_width"], 2, "Catalog omitted corridor geometry settings")
	TEST_ASSERT_EQUAL(settings["maintenance_width"], 2, "Catalog did not request the Rust planner's two-tile maintenance geometry")
	TEST_ASSERT(settings["candidate_count"] > 1 && length(settings["architecture_choices"]) >= 5, "Catalog omitted architecture search settings")
	var/list/room = request["rooms"][1]
	TEST_ASSERT_EQUAL(room["min_count"], 1, "Room occurrence minimum was not exported")
	TEST_ASSERT_EQUAL(room["max_count"], 1, "Room occurrence maximum was not exported")
	TEST_ASSERT(room["content_area"] >= room["min_width"] * room["min_height"], "Room content area is smaller than its minimum footprint")
	TEST_ASSERT(room["minimum_usable_tiles"] >= room["min_width"] * room["min_height"], "Room usable-tile requirement is smaller than its minimum footprint")
	TEST_ASSERT(room["min_entrances"] >= 1 && room["max_entrances"] >= room["min_entrances"], "Room entrance constraints were not exported")
	var/list/sprite_previews = request["sprite_previews"]
	TEST_ASSERT(length(sprite_previews) >= 80, "Catalog omitted the complete live fixture appearance vocabulary")
	TEST_ASSERT(sprite_previews["operating_table"]["icon_file"] && sprite_previews["operating_table"]["icon_state"], "Operating table preview lacks its real icon/state")
	var/authored_feature_count = 0
	for(var/list/room_contract in request["rooms"])
		for(var/list/fragment in room_contract["fragments"])
			authored_feature_count += length(fragment["features"])
	TEST_ASSERT(authored_feature_count >= 100, "Authored room motifs did not export enough exact fixture placements")
	TEST_ASSERT(!findtext(first, "/datum/"), "Catalog leaked DM type paths across the Rust boundary")

/datum/unit_test/dq_generated_station_rust_catalog_accepts_callers

/datum/unit_test/dq_generated_station_rust_catalog_accepts_callers/Run()
	var/list/catalog = generated_station_department_catalog()
	var/datum/generated_station_department_definition/first_department = catalog[1]
	first_department.name = "Synthetic Command Contract"
	var/list/settings = list("corridor_width" = 4, "candidate_count" = 7)
	var/encoded = generated_station_rust_catalog_request(11, 64, 64, catalog, settings)
	var/list/request = json_decode(encoded)
	TEST_ASSERT_EQUAL(request["departments"][1]["name"], "Synthetic Command Contract", "Catalog exporter ignored a caller-supplied catalog")
	TEST_ASSERT_EQUAL(request["settings"]["corridor_width"], 4, "Catalog exporter ignored caller-supplied geometry settings")
	TEST_ASSERT_EQUAL(request["settings"]["candidate_count"], 7, "Catalog exporter ignored caller-supplied search settings")
	TEST_ASSERT(!findtext(encoded, "/datum/"), "Caller-supplied catalog leaked a DM type path")
	QDEL_LIST(catalog)

/datum/unit_test/dq_generated_station_rust_decoder_rejects_bad_rle

/datum/unit_test/dq_generated_station_rust_decoder_rejects_bad_rle/Run()
	var/list/errors = list()
	var/list/response = list(
		"schema" = "dq.station.plan", "major" = 1, "minor" = 0,
		"catalog_hash" = "fixture", "seed" = "1", "width" = 16, "height" = 16,
		"metadata" = list(), "departments" = list(), "nodes" = list(), "rooms" = list(), "doors" = list(), "edges" = list(),
		"tile_rows" = list(list("y" = 1, "runs" = list(list("x" = 2, "len" = 15, "class" = "exterior")))),
	)
	var/datum/generated_station_spec/spec = generated_station_spec_from_rust_json(json_encode(response), "fixture", errors)
	TEST_ASSERT_NULL(spec, "Rust decoder accepted a tile row with an initial RLE gap")
	TEST_ASSERT(length(errors), "Rust decoder rejected malformed RLE without a diagnostic")

/datum/unit_test/dq_generated_station_rust_decoder_rejects_version_mismatch

/datum/unit_test/dq_generated_station_rust_decoder_rejects_version_mismatch/Run()
	var/list/errors = list()
	var/datum/generated_station_spec/spec = generated_station_spec_from_rust_json("{\"schema\":\"dq.station.plan\",\"major\":2}", null, errors)
	TEST_ASSERT_NULL(spec, "Rust decoder accepted an unsupported major version")
	TEST_ASSERT(length(errors), "Version rejection produced no diagnostic")

/proc/generated_station_rust_valid_fixture()
	var/list/department_ids = list("command", "ai", "security", "medical", "engineering", "logistics", "docking")
	var/list/role_ids = list("reception", "foyer", "reception", "reception", "foyer", "reception", "reception")
	var/list/departments = list()
	var/list/nodes = list()
	var/list/rooms = list()
	var/list/content_rooms = list()
	var/list/fixtures = list()
	var/list/edges = list()
	var/list/x_starts = list(1, 6, 11, 16, 21, 25, 29)
	var/list/widths = list(5, 5, 5, 5, 4, 4, 4)
	for(var/i in 1 to length(department_ids))
		var/department_id = department_ids[i]
		var/instance_id = "[department_id]-1"
		var/node_id = "node-[department_id]"
		var/room_id = "room-[department_id]"
		var/datum/generated_room_definition/definition = generated_room_definition_for(department_id, role_ids[i])
		departments += list(list("id" = instance_id, "definition_id" = department_id, "desired_area" = 48, "node_id" = node_id))
		nodes += list(list("id" = node_id, "department_id" = instance_id, "desired_area" = 48, "x" = x_starts[i], "y" = 1, "width" = widths[i], "height" = 16, "frontage_x" = x_starts[i], "frontage_y" = 1, "frontage_spine_vertical" = TRUE, "frontage_spine_coordinate" = x_starts[i]))
		rooms += list(list("id" = room_id, "rust_room_id" = i, "node_id" = node_id, "definition_id" = definition.id, "role" = role_ids[i], "frontage_x" = x_starts[i], "frontage_y" = 1))
		content_rooms += list(list(
			"allocation_id" = room_id,
			"room_id" = i,
			"department_id" = i,
			"semantic_role" = role_ids[i],
			"selected_variant" = definition.id,
			"area_name" = "Station Fixture [capitalize(department_id)]",
			"aesthetic_id" = "fixture",
			"floor_style" = "fixture",
			"accent_style" = "fixture",
			"activity_center" = list("x" = x_starts[i] - 1, "y" = 1),
			"circulation" = list(list("x" = x_starts[i] - 1, "y" = 1)),
			"fixture_ids" = list(i),
			"occupancy_micros" = 100000,
		))
		fixtures += list(list(
			"id" = i,
			"fixture_id" = "chair",
			"at" = list("x" = x_starts[i] - 1, "y" = 1),
			"facing" = "South",
			"layer" = "Furniture",
			"department_id" = i,
			"room_id" = i,
			"network_id" = null,
			"variant" = 0,
			"blocks_movement" = TRUE,
			"required_access" = list(),
		))
		qdel(definition)
		if(i > 1)
			edges += list(list("id" = "edge-[i]", "from_node" = "node-[department_ids[i - 1]]", "to_node" = node_id, "kind" = "transit", "service_id" = null, "minimum_width" = 1, "required" = TRUE, "corridor_class" = "connector", "path" = list(list(x_starts[i], 1))))
	var/list/tile_rows = list()
	for(var/y in 1 to 16)
		var/list/runs = list()
		for(var/i in 1 to length(department_ids))
			runs += list(list("x" = x_starts[i], "len" = widths[i], "class" = "department_floor", "owner" = "node-[department_ids[i]]", "zone" = "room-[department_ids[i]]", "room" = "room-[department_ids[i]]", "flags" = 32))
		tile_rows += list(list("y" = y, "runs" = runs))
	return list(
		"schema" = "dq.station.plan", "major" = 1, "minor" = 0, "catalog_hash" = "fixture-hash", "seed" = "42", "width" = 32, "height" = 16,
		"metadata" = list("station_id" = "station-fixture", "name" = "Station Fixture", "architecture_style" = "industrial", "faction_id" = "corporate", "security_tier" = 1, "size_class" = "compact", "layout_archetype" = "fixture", "aesthetic_score" = 0),
		"departments" = departments, "nodes" = nodes, "rooms" = rooms, "doors" = list(), "edges" = edges, "tile_rows" = tile_rows,
		"content_rooms" = content_rooms, "fixtures" = fixtures, "networks" = list(), "content_quality" = list(),
	)

/datum/unit_test/dq_generated_station_rust_decoder_reconstructs_ownership

/datum/unit_test/dq_generated_station_rust_decoder_reconstructs_ownership/Run()
	var/list/errors = list()
	var/datum/generated_station_spec/spec = generated_station_spec_from_rust_json(json_encode(generated_station_rust_valid_fixture()), "fixture-hash", errors)
	TEST_ASSERT_NOTNULL(spec, "Valid Rust fixture failed reconstruction: [jointext(errors, "; ")]")
	TEST_ASSERT_EQUAL(length(spec.layout_nodes), 7, "Rust fixture lost department nodes")
	var/datum/generated_station_layout_node/command = spec.layout_nodes[1]
	TEST_ASSERT(command.territory["1,1"] && command.territory["5,16"], "Decoded command territory did not preserve row-RLE ownership")
	TEST_ASSERT_EQUAL(length(command.room_program), 1, "Decoded command room was not attached to its node")
	var/datum/generated_station_room_allocation/room = command.room_program[1]
	TEST_ASSERT(room.tiles["1,1"] && room.tiles["5,16"], "Decoded room did not preserve row-RLE membership")
	qdel(spec)

/datum/unit_test/dq_generated_station_rust_decoder_preserves_hull_tiles

/datum/unit_test/dq_generated_station_rust_decoder_preserves_hull_tiles/Run()
	var/list/fixture = generated_station_rust_valid_fixture()
	var/list/hull_run = fixture["tile_rows"][1]["runs"][1]
	hull_run["class"] = "hull"
	hull_run["owner"] = null
	hull_run["zone"] = null
	hull_run["room"] = null
	hull_run["flags"] = 0
	var/list/errors = list()
	var/datum/generated_station_spec/spec = generated_station_spec_from_rust_json(json_encode(fixture), "fixture-hash", errors)
	TEST_ASSERT_NOTNULL(spec, "Valid Rust hull fixture failed reconstruction: [jointext(errors, "; ")]")
	for(var/x in 1 to 5)
		TEST_ASSERT(spec.structural_tiles["[x],1"], "Rust hull tile [x],1 was discarded during DM decoding")
	qdel(spec)

/datum/unit_test/dq_generated_station_rust_decoder_accepts_consistent_doors

/datum/unit_test/dq_generated_station_rust_decoder_accepts_consistent_doors/Run()
	var/list/fixture = generated_station_rust_valid_fixture()
	fixture["tile_rows"][1]["runs"][1]["flags"] = 33
	fixture["doors"] += list(list("id" = "door-room", "x" = 1, "y" = 1, "direction" = "N", "kind" = "room", "owner_id" = "node-command", "from_zone" = "room-command", "to_zone" = "node-command"))
	var/list/errors = list()
	var/datum/generated_station_spec/spec = generated_station_spec_from_rust_json(json_encode(fixture), "fixture-hash", errors)
	TEST_ASSERT_NOTNULL(spec, "Decoder rejected a spatially consistent room door: [jointext(errors, "; ")]")
	qdel(spec)

/datum/unit_test/dq_generated_station_rust_decoder_rejects_adversarial_payloads

/datum/unit_test/dq_generated_station_rust_decoder_rejects_adversarial_payloads/Run()
	var/list/cases = list()
	var/list/missing_row = generated_station_rust_valid_fixture()
	var/list/missing_tile_rows = missing_row["tile_rows"]
	missing_tile_rows.Cut(16, 17)
	cases["missing row"] = missing_row
	var/list/gapped = generated_station_rust_valid_fixture()
	gapped["tile_rows"][1]["runs"][1]["x"] = 2
	cases["gapped RLE"] = gapped
	var/list/overlapping = generated_station_rust_valid_fixture()
	overlapping["tile_rows"][1]["runs"][2]["x"] = 5
	cases["overlapping RLE"] = overlapping
	var/list/bad_owner = generated_station_rust_valid_fixture()
	bad_owner["tile_rows"][1]["runs"][1]["owner"] = "missing-node"
	cases["bad owner"] = bad_owner
	var/list/bad_room = generated_station_rust_valid_fixture()
	bad_room["tile_rows"][1]["runs"][1]["room"] = "missing-room"
	cases["bad room"] = bad_room
	var/list/bad_door = generated_station_rust_valid_fixture()
	bad_door["doors"] += list(list("id" = "door-1", "x" = 1, "y" = 1, "direction" = "N", "kind" = "room", "owner_id" = "missing-node", "from_zone" = "room-command", "to_zone" = "outside"))
	cases["bad door owner"] = bad_door
	var/list/oob_door = generated_station_rust_valid_fixture()
	oob_door["doors"] += list(list("id" = "door-1", "x" = 33, "y" = 1, "direction" = "N", "kind" = "room", "owner_id" = "node-command", "from_zone" = "room-command", "to_zone" = "outside"))
	cases["out-of-bounds door"] = oob_door
	var/list/duplicate_edge = generated_station_rust_valid_fixture()
	var/list/duplicate_edges = duplicate_edge["edges"]
	var/list/first_edge = duplicate_edges[1]
	duplicate_edges += list(first_edge.Copy())
	cases["duplicate edge id"] = duplicate_edge
	var/list/fractional_node = generated_station_rust_valid_fixture()
	fractional_node["nodes"][1]["x"] = 1.5
	cases["fractional coordinate"] = fractional_node
	var/list/bad_seed = generated_station_rust_valid_fixture()
	bad_seed["seed"] = "42oops"
	cases["malformed seed"] = bad_seed
	var/list/bad_metadata = generated_station_rust_valid_fixture()
	bad_metadata["metadata"]["architecture_style"] = null
	cases["malformed metadata"] = bad_metadata
	var/list/bad_flags = generated_station_rust_valid_fixture()
	bad_flags["tile_rows"][1]["runs"][1]["flags"] = 64
	cases["unknown tile flags"] = bad_flags
	var/list/cross_department = generated_station_rust_valid_fixture()
	cross_department["tile_rows"][1]["runs"][1]["owner"] = "node-ai"
	cases["cross-department room ownership"] = cross_department
	var/list/unknown_edge_kind = generated_station_rust_valid_fixture()
	unknown_edge_kind["edges"][1]["kind"] = "wormhole"
	cases["unknown edge kind"] = unknown_edge_kind
	var/list/self_edge = generated_station_rust_valid_fixture()
	self_edge["edges"][1]["to_node"] = self_edge["edges"][1]["from_node"]
	cases["self edge"] = self_edge
	var/list/empty_transit = generated_station_rust_valid_fixture()
	empty_transit["edges"][1]["path"] = list()
	cases["empty transit path"] = empty_transit
	var/list/door_without_flag = generated_station_rust_valid_fixture()
	door_without_flag["doors"] += list(list("id" = "door-1", "x" = 1, "y" = 1, "direction" = "N", "kind" = "room", "owner_id" = "node-command", "from_zone" = "room-command", "to_zone" = "node-command"))
	cases["door without tile flag"] = door_without_flag
	var/list/duplicate_door_id = generated_station_rust_valid_fixture()
	duplicate_door_id["tile_rows"][1]["runs"][1]["flags"] = 33
	duplicate_door_id["doors"] += list(
		list("id" = "door-1", "x" = 1, "y" = 1, "direction" = "N", "kind" = "room", "owner_id" = "node-command", "from_zone" = "room-command", "to_zone" = "node-command"),
		list("id" = "door-1", "x" = 2, "y" = 1, "direction" = "N", "kind" = "room", "owner_id" = "node-command", "from_zone" = "room-command", "to_zone" = "node-command"),
	)
	cases["duplicate door id"] = duplicate_door_id
	var/list/duplicate_door_coordinate = generated_station_rust_valid_fixture()
	duplicate_door_coordinate["tile_rows"][1]["runs"][1]["flags"] = 33
	duplicate_door_coordinate["doors"] += list(
		list("id" = "door-1", "x" = 1, "y" = 1, "direction" = "N", "kind" = "room", "owner_id" = "node-command", "from_zone" = "room-command", "to_zone" = "node-command"),
		list("id" = "door-2", "x" = 1, "y" = 1, "direction" = "S", "kind" = "room", "owner_id" = "node-command", "from_zone" = "room-command", "to_zone" = "node-command"),
	)
	cases["duplicate door coordinate"] = duplicate_door_coordinate
	var/list/door_owner_mismatch = generated_station_rust_valid_fixture()
	door_owner_mismatch["tile_rows"][1]["runs"][1]["flags"] = 33
	door_owner_mismatch["doors"] += list(list("id" = "door-1", "x" = 1, "y" = 1, "direction" = "N", "kind" = "room", "owner_id" = "node-ai", "from_zone" = "room-command", "to_zone" = "node-command"))
	cases["door tile owner mismatch"] = door_owner_mismatch
	var/list/door_zone_mismatch = generated_station_rust_valid_fixture()
	door_zone_mismatch["tile_rows"][1]["runs"][1]["flags"] = 33
	door_zone_mismatch["doors"] += list(list("id" = "door-1", "x" = 1, "y" = 1, "direction" = "N", "kind" = "room", "owner_id" = "node-command", "from_zone" = "room-ai", "to_zone" = "node-command"))
	cases["door zone mismatch"] = door_zone_mismatch
	var/list/bad_maintenance_owner = generated_station_rust_valid_fixture()
	bad_maintenance_owner["tile_rows"][1]["runs"][1]["class"] = "maintenance_floor"
	bad_maintenance_owner["tile_rows"][1]["runs"][1]["flags"] = 33
	bad_maintenance_owner["doors"] += list(list("id" = "door-1", "x" = 1, "y" = 1, "direction" = "N", "kind" = "maintenance", "owner_id" = "missing-node", "from_zone" = "maintenance", "to_zone" = "node-command"))
	cases["maintenance door owner"] = bad_maintenance_owner
	var/list/bad_hash = generated_station_rust_valid_fixture()
	bad_hash["catalog_hash"] = "wrong"
	cases["catalog hash"] = bad_hash
	var/list/bad_schema = generated_station_rust_valid_fixture()
	bad_schema["schema"] = "unknown.station.plan"
	cases["unknown schema"] = bad_schema
	var/list/bad_class = generated_station_rust_valid_fixture()
	bad_class["tile_rows"][1]["runs"][1]["class"] = "lava_castle"
	cases["unknown tile class"] = bad_class
	for(var/case_name in cases)
		var/list/errors = list()
		var/datum/generated_station_spec/spec = generated_station_spec_from_rust_json(json_encode(cases[case_name]), "fixture-hash", errors)
		TEST_ASSERT_NULL(spec, "Rust decoder accepted adversarial case '[case_name]'")
		TEST_ASSERT(length(errors), "Rust decoder rejected '[case_name]' without a diagnostic")
