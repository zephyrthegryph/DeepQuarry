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

/datum/generated_station_planner/proc/plan(seed, width = 96, height = 96)
	// BYOND numbers cannot preserve every integer above 24 bits or serialize
	// them without scientific notation. Keep the public seed in its exact range
	// before it crosses the strict Rust JSON contract.
	seed = max(1, abs(round(seed || 1)) % 16000000)
	var/list/errors = list()
	var/request_json = generated_station_rust_catalog_request(seed, width, height)
	var/list/request = json_decode(request_json)
	var/response_json
	try
		response_json = verdigris_generate_station_layout(request_json)
	catch(var/exception/error)
		rustg_file_write(request_json, "[GLOB.log_directory]/generated-station-rust-request-[num2text(round(seed), 20)].json")
		log_world("Generated station Rust planner failed for seed [seed]: [error]")
		return null
	var/datum/generated_station_spec/spec = generated_station_spec_from_rust_json(response_json, request["catalog_hash"], errors)
	if(!spec)
		log_world("Generated station Rust plan rejected for seed [seed]: [jointext(errors, "; ")]")
		return null
	return spec
