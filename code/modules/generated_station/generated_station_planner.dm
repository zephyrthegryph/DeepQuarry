/// Deterministic PRNG used for DM-side content selection after Rust has fixed
/// the authoritative station geometry.
/datum/generated_station_prng
	var/state = 1

/datum/generated_station_prng/New(seed)
	..()
	state = max(1, abs(round(seed || 1)) % 2147483647)

/datum/generated_station_prng/proc/next()
	var/high = round(state / 44488)
	var/low = state % 44488
	var/next_state = 48271 * low - 3399 * high
	state = next_state > 0 ? next_state : next_state + 2147483647
	return state

/datum/generated_station_prng/proc/next_range(minimum, maximum)
	var/span = maximum - minimum + 1
	if(span <= 1)
		return minimum
	return minimum + min(span - 1, round((next() / 2147483647) * span))

/// Returns the stable public designation shared by a generated station and its areas.
/proc/generated_station_designation(seed)
	var/static/list/station_names = list("Theta", "Sigma", "Kappa", "Vega", "Orion", "Lyra", "Cygnus", "Draco")
	var/normalized_seed = max(1, abs(round(seed || 1)))
	var/station_name_index = (normalized_seed % length(station_names)) + 1
	return "Station [station_names[station_name_index]]-[(normalized_seed % 99) + 1]"

/proc/generated_station_department_catalog()
	var/list/catalog = list()
	var/list/rows = list(
		list("command", "Command", TRUE, list("power", "atmosphere"), list("coordination")),
		list("ai", "AI Core", TRUE, list("power", "data"), list("data")),
		list("security", "Security", TRUE, list("power", "coordination", "data"), list("security")),
		list("medical", "Medical", TRUE, list("power", "atmosphere"), list("medical")),
		list("engineering", "Engineering", TRUE, list("logistics"), list("power", "atmosphere")),
		list("logistics", "Logistics", FALSE, list("power"), list("logistics")),
		list("docking", "Docking", TRUE, list("power", "security"), list("docking")),
	)
	for(var/list/row in rows)
		var/datum/generated_station_department_definition/definition = new
		definition.id = row[1]
		definition.name = row[2]
		definition.critical = row[3]
		definition.minimum_area = definition.critical ? 48 : 36
		definition.maximum_area = 100
		for(var/capability in row[4])
			definition.requirements += new /datum/generated_station_capability_requirement(capability)
		for(var/capability in row[5])
			definition.provisions += new /datum/generated_station_capability_provision(capability)
		catalog += definition
	return catalog

/// DM supplies semantic room and department contracts; Rust exclusively owns
/// every spatial decision in the returned station specification.
/datum/generated_station_planner
	var/error_message

/datum/generated_station_planner/proc/plan(seed, width = 160, height = 160)
	error_message = null
	// BYOND numbers cannot preserve every integer above 24 bits or serialize
	// them without scientific notation. Keep the public seed in its exact range
	// before it crosses the strict Rust JSON contract.
	seed = max(1, abs(round(seed || 1)) % 16000000)
	var/list/errors = list()
	var/request_json = generated_station_rust_catalog_request(seed, width, height)
	#ifdef CITESTING
	rustg_file_write(request_json, "[GLOB.log_directory]/generated-station-rust-request-[num2text(round(seed), 20)].json")
	#endif
	var/list/request = json_decode(request_json)
	var/job_id
	var/list/response
	try
		job_id = vg_verdigris_submit_station_layout(request_json)
		if(!job_id)
			throw EXCEPTION("Rust planner did not return a job handle")
		while(TRUE)
			var/status = vg_verdigris_job_poll(job_id)
			if(status == "PENDING")
				// The worker owns only immutable Rust data. BYOND remains free to
				// service ordinary ticks until the serialized result is ready.
				sleep(0)
				continue
			if(findtext(status, "ERROR:") == 1)
				throw EXCEPTION(copytext(status, 7))
			if(status == "CANCELLED")
				throw EXCEPTION("Rust planning job was cancelled")
			break
		response = generated_station_fetch_rust_plan(job_id)
		vg_verdigris_job_finish(job_id)
		job_id = null
	catch(var/exception/error)
		if(job_id)
			vg_verdigris_job_finish(job_id)
		rustg_file_write(request_json, "[GLOB.log_directory]/generated-station-rust-request-[num2text(round(seed), 20)].json")
		log_world("Generated station Rust planner failed for seed [seed]: [error]")
		error_message = "[error]"
		return null
	var/datum/generated_station_spec/spec = generated_station_spec_from_rust_json(response, request["catalog_hash"], errors)
	if(!spec)
		log_world("Generated station Rust plan rejected for seed [seed]: [jointext(errors, "; ")]")
		error_message = jointext(errors, "; ")
		return null
	spec.fixture_type_registry = generated_station_rust_fixture_registry()
	return spec

/// Pull bounded slices from a completed Rust job so no json_decode call can
/// monopolize a BYOND tick. Tile rows use smaller pages because they contain
/// the dense run-length encoded tile plan.
/proc/generated_station_fetch_rust_plan(job_id)
	var/list/root = json_decode(vg_verdigris_station_layout_section(job_id, "header", "0", "0"))
	var/static/list/sections = list("departments", "nodes", "rooms", "doors", "edges", "tile_rows", "content_rooms", "fixtures", "networks")
	for(var/section in sections)
		var/list/rows = list()
		var/offset = 0
		var/page_size = section == "tile_rows" ? 4 : 24
		while(TRUE)
			var/list/page = json_decode(vg_verdigris_station_layout_section(job_id, section, num2text(offset, 20), num2text(page_size, 20)))
			if(!length(page))
				break
			rows += page
			offset += length(page)
			sleep(0)
		root[section] = rows
	return root
