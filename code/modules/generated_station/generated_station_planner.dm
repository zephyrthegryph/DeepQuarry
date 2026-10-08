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
	var/static/list/rows = list(
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
			rel_add(definition, nameof(definition.requirements), new /datum/generated_station_capability_requirement(capability))
		for(var/capability in row[5])
			rel_add(definition, nameof(definition.provisions), new /datum/generated_station_capability_provision(capability))
		catalog += definition
	return catalog


/// DM supplies semantic room and department contracts; Rust exclusively owns
/// every spatial decision in the returned station specification.
/datum/generated_station_planner
	var/error_message

/// The pending plan_async() job's state; plan_poll() polls it every tick while set (every()).
/datum/generated_station_planner/var/tmp/list/poll_state
TRACKED(/datum/generated_station_planner, poll_state)

CAPABILITIES(/datum/generated_station_planner)
	every(PROC_REF(poll_delay), then(PROC_REF(plan_poll)), when = nameof(poll_state))

/datum/generated_station_planner/proc/poll_delay(datum/act/A)
	return world.tick_lag

/datum/generated_station_planner/proc/plan(seed, width = 160, height = 160)
	error_message = null
	seed = generated_station_plan_seed(seed)
	var/request_json = plan_request(seed, width, height)
	var/job_id = vg_verdigris_submit_station_layout(request_json)
	var/list/state = list("job" = job_id, "request" = request_json, "seed" = seed)
	if(!job_id)
		return plan_failed(null, request_json, seed, "Rust planner did not return a job handle")
	// Blocking callers (tests, admin tools) wait on the Rust worker thread; the live game uses
	// plan_async(), which polls on a timer instead.
	var/status = vg_verdigris_job_poll(job_id)
	while(status == "PENDING")
		status = vg_verdigris_job_poll(job_id)
	if(!plan_ready(state, status))
		return state["spec"]
	while(!isnull(plan_fetch_slice(state)))
		continue
	return state["spec"]

/// plan() for the live game: the Rust job is polled on a timer and its result read back as lane
/// work (object_model_core.md §4.11), so nothing sleeps. When it ends, after(owner, 0, then, with = with + the spec, or
/// null: error_message says why) runs.
/datum/generated_station_planner/proc/plan_async(seed, width = 160, height = 160, then = null, datum/owner = null, list/with = null)
	error_message = null
	seed = generated_station_plan_seed(seed)
	var/request_json = plan_request(seed, width, height)
	var/job_id = vg_verdigris_submit_station_layout(request_json)
	var/list/state = list("job" = job_id, "request" = request_json, "seed" = seed, "then" = then, "owner" = owner, "with" = with)
	if(!job_id)
		return plan_async_end(state, plan_failed(null, request_json, seed, "Rust planner did not return a job handle"))
	// The worker owns only immutable Rust data; the game keeps its ticks until the result is ready.
	set_poll_state(state)

/// Polls the pending Rust job (every() while poll_state is set); once it is done, reads it back.
/datum/generated_station_planner/proc/plan_poll(datum/act/timer/A)
	var/list/state = poll_state
	if(!state)
		return
	var/status = vg_verdigris_job_poll(state["job"])
	if(status == "PENDING")
		return
	set_poll_state(null)
	if(plan_ready(state, status))
		job_cursor(src, PROC_REF(plan_fetch_slice), state)

/// The job finished: TRUE with the header read and the pages ready to fetch; FALSE when it failed
/// (the failure is handed on).
/datum/generated_station_planner/proc/plan_ready(list/state, status)
	if(findtext(status, "ERROR:") == 1)
		plan_async_end(state, plan_failed(state["job"], state["request"], state["seed"], copytext(status, 7)))
		return FALSE
	if(status == "CANCELLED")
		plan_async_end(state, plan_failed(state["job"], state["request"], state["seed"], "Rust planning job was cancelled"))
		return FALSE
	try
		state["root"] = json_decode(vg_verdigris_station_layout_section(state["job"], "header", "0", "0"))
	catch(var/exception/error) // ALLOW(silent_catch): the failure is returned through plan_failed()
		plan_async_end(state, plan_failed(state["job"], state["request"], state["seed"], "[error]"))
		return FALSE
	state["section"] = 1
	state["offset"] = 0
	state["rows"] = list()
	return TRUE

/// One page of the finished plan, so no json_decode call monopolizes a tick. Returns the state to
/// carry on with, or null once the plan is read (and handed on).
/datum/generated_station_planner/proc/plan_fetch_slice(list/state)
	var/list/sections = GLOB.generated_station_plan_sections
	var/section = sections[state["section"]]
	var/page_size = section == "tile_rows" ? 4 : 24
	var/list/page
	try
		page = json_decode(vg_verdigris_station_layout_section(state["job"], section, num2text(state["offset"], 20), num2text(page_size, 20)))
	catch(var/exception/error) // ALLOW(silent_catch): the failure is returned through plan_failed()
		plan_async_end(state, plan_failed(state["job"], state["request"], state["seed"], "[error]"))
		return null
	if(length(page))
		var/list/rows = state["rows"]
		rows += page
		state["offset"] += length(page)
		return state
	var/list/root = state["root"]
	root[section] = state["rows"]
	if(state["section"] < length(sections))
		state["section"]++
		state["offset"] = 0
		state["rows"] = list()
		return state
	vg_verdigris_job_finish(state["job"])
	plan_async_end(state, plan_from_response(root, state["request"], state["seed"]))
	return null

/datum/generated_station_planner/proc/plan_async_end(list/state, datum/generated_station_spec/spec)
	state["spec"] = spec
	if(state["then"])
		after(state["owner"], 0, state["then"], with = (state["with"] || list()) + list(spec))

/// The plan's array sections, read a page at a time by plan_fetch_slice().
GLOBAL_LIST_INIT(generated_station_plan_sections, list("departments", "nodes", "rooms", "doors", "edges", "tile_rows", "content_rooms", "fixtures", "networks"))

/// BYOND numbers cannot preserve every integer above 24 bits or serialize them without
/// scientific notation. Keep the public seed in its exact range before it crosses the strict
/// Rust JSON contract.
/proc/generated_station_plan_seed(seed)
	return max(1, abs(round(seed || 1)) % 16000000)

/datum/generated_station_planner/proc/plan_request(seed, width, height)
	. = generated_station_rust_catalog_request(seed, width, height)
	#ifdef CITESTING
	rustg_file_write(., "[GLOB.log_directory]/generated-station-rust-request-[num2text(round(seed), 20)].json")
	#endif

/datum/generated_station_planner/proc/plan_failed(job_id, request_json, seed, message)
	if(job_id)
		vg_verdigris_job_finish(job_id)
	rustg_file_write(request_json, "[GLOB.log_directory]/generated-station-rust-request-[num2text(round(seed), 20)].json")
	log_world("Generated station Rust planner failed for seed [seed]: [message]")
	error_message = "[message]"
	return null

/// The spec for a finished Rust plan, or null (error_message says why).
/datum/generated_station_planner/proc/plan_from_response(list/response, request_json, seed)
	var/list/request = json_decode(request_json)
	var/list/errors = list()
	var/datum/generated_station_spec/spec = generated_station_spec_from_rust_json(response, request["catalog_hash"], errors)
	if(!spec)
		log_world("Generated station Rust plan rejected for seed [seed]: [jointext(errors, "; ")]")
		error_message = jointext(errors, "; ")
		return null
	spec.fixture_type_registry = generated_station_rust_fixture_registry()
	return spec
