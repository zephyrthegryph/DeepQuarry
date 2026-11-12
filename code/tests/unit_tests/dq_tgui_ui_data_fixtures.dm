// Captures real window data for the tgui render test (tgui/packages/tgui/interfaces/renderAll.test.tsx). For every /obj type and every
// datum window host that stands alone (a tgui module, a modular computer program, the tgui input modals; FIXTURE_DATUM_ROOTS) that declares
// interface(), one fresh instance per window name is spawned and its tgui_data() and static data (present_tgui_static_data()) for a fresh human viewer are written,
// keyed by window name, to TGUI_FIXTURES_FILE. Regenerate: `bash tools/dq_focused_test.sh /datum/unit_test/dq_tgui_ui_data_fixtures`, then
// copy data/tgui_fixtures/ui_data.json to tgui/packages/tgui/interfaces/__fixtures__/ui_data.json. A type that fails to spawn or whose data
// faults is logged and skipped (the next type with the same window is tried); the windows with no fixture are logged at the end.

#define TGUI_FIXTURES_FILE "data/tgui_fixtures/ui_data.json"
/// Datum window hosts that can be made bare (new type() with no host): a module or program made without its console still answers ui_data(), or
/// faults and is skipped with its error logged.
#define FIXTURE_DATUM_ROOTS list(/datum/tgui_module, /datum/computer_file/program, /datum/tgui_alert, /datum/tgui_input_text, /datum/tgui_input_number, /datum/tgui_list_input, /datum/tgui_checkbox_input, /datum/tgui_bitfield_input, /datum/tgui_color_picker, /datum/tgui_input_keycombo)

/datum/unit_test/dq_tgui_ui_data_fixtures

/datum/unit_test/dq_tgui_ui_data_fixtures/proc/spawn_host(type, mob/user)
	// The input modals are made for a viewer with the arguments their tgui_input_*() procs pass.
	switch(type)
		if(/datum/tgui_alert)
			return allocate(type, user, "Message", "Title", list("Yes", "No"), 0, TRUE, GLOB.tgui_always_state)
		if(/datum/tgui_bitfield_input)
			return allocate(type, user, "Title", list("FIRST" = 1, "SECOND" = 2), 1, null, 0)
		if(/datum/tgui_checkbox_input)
			return allocate(type, user, "Message", "Title", list("One", "Two"), 0, 2, 0, GLOB.tgui_always_state)
		if(/datum/tgui_color_picker)
			return allocate(type, user, "Message", "Title", "#ff0000", 0, TRUE, GLOB.tgui_always_state)
		if(/datum/tgui_input_keycombo)
			return allocate(type, user, "Message", "Title", "Ctrl+A", 0, GLOB.tgui_always_state)
		if(/datum/tgui_list_input)
			return allocate(type, user, "Message", "Title", list("One", "Two"), "One", 0, GLOB.tgui_always_state)
		if(/datum/tgui_input_number)
			return allocate(type, user, "Message", "Title", 5, 10, 0, 0, TRUE, GLOB.tgui_always_state)
		if(/datum/tgui_input_text)
			return allocate(type, user, "Message", "Title", "Text", 64, FALSE, TRUE, 0, GLOB.tgui_always_state)
	return allocate(type)

/datum/unit_test/dq_tgui_ui_data_fixtures/proc/window_data(datum/host, mob/user)
	var/list/data = list()
	var/list/static_data = present_tgui_static_data(host, user)
	if(islist(static_data))
		data += static_data
	var/list/dynamic = host.tgui_data(user)
	if(islist(dynamic))
		for(var/key in dynamic)
			data[key] = dynamic[key]
	// Round-trip through JSON as the transport does, so a value the client could never receive fails here.
	return json_decode(json_encode(data))

/datum/unit_test/dq_tgui_ui_data_fixtures/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	var/list/fixtures = list()
	var/list/failed = list()
	var/list/seen = list()
	var/list/attempts = list() // window -> types tried for it: three failures give up on that window
	var/tried = 0
	// The capture stops at a wall-clock budget so a focused run stays under its cap; what was captured is still written.
	var/deadline = REALTIMEOFDAY + 3 MINUTES
	// Hosts made bare change world state their console would own (a gravity generator's area gravity, the rogue miner's controller, an
	// init that faulted half-way); put it back once the capture is done so later tests start from the same world.
	var/area/test_area = get_area(run_loc_floor_bottom_left)
	var/old_gravity = test_area.has_gravity
	var/old_rm_controller = GLOB.rm_controller
	var/list/hosts = typesof(/obj)
	for(var/root in FIXTURE_DATUM_ROOTS)
		hosts += typesof(root)
	for(var/type in hosts)
		if(REALTIMEOFDAY > deadline)
			log_world("tgui fixtures: time budget reached at [type]; the rest have no fixture this run")
			break
		if(is_abstract(type))
			continue
		var/datum/type_table/T = table_of_type(type)
		if(!T || !length(T.items))
			continue
		var/list/found = compiled_entries(T, ENTRY_INTERFACE)
		if(!length(found))
			continue
		var/datum/centry/C = found[length(found)]
		var/datum/entry/declared = C.item
		var/window = declared.args["window"]
		if(istext(window) && (fixtures[window] || attempts[window] >= 3))
			continue
		if(istext(window))
			attempts[window]++
		if(!istext(window) && !declared.args["window_var"])
			continue
		tried++
		log_world("tgui fixtures: trying [type] for [window || declared.args["window_var"]]")
		var/datum/result/made = safe_call(PROC_REF(spawn_host), type, user)
		var/datum/host = made.value
		if(!made.ok || QDELETED(host))
			failed["[type]"] = "spawn: [made.error || "deleted itself"]"
			continue
		if(!istext(window))
			window = host.vars[declared.args["window_var"]]
		if(!istext(window) || fixtures[window])
			continue
		seen[window] = TRUE
		var/datum/result/read = safe_call(PROC_REF(window_data), host, user)
		if(!read.ok)
			failed["[type]"] = "[window]: [read.error]"
			continue
		fixtures[window] = read.value
	for(var/window in seen)
		if(!fixtures[window])
			log_world("tgui fixtures: no data for [window]")
	for(var/type in failed)
		log_world("tgui fixtures: [type]: [failed[type]]")
	// A machine spawned bare makes its parts, cell and terminal beside it, and drops its parts when deleted; nothing here allocated those, so clear the block.
	// A deleted machine drops its parts in turn, so sweep until a pass finds nothing.
	for(var/pass in 1 to 5)
		var/swept = 0
		for(var/turf/T in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
			for(var/atom/movable/AM as anything in T)
				if(AM != user && !ismob(AM) && !QDELETED(AM))
					qdel(AM)
					swept++
		if(!swept)
			break
	if(test_area.has_gravity != old_gravity)
		test_area.gravitychange(old_gravity)
	if(GLOB.rm_controller != old_rm_controller)
		log_world("tgui fixtures: a host made the rogue miner controller; dropping it")
		GLOB.rm_controller = old_rm_controller
	if(GLOB.atom_initializing)
		log_world("tgui fixtures: [GLOB.atom_initializing] faulted during its Initialize(); clearing GLOB.atom_initializing")
		GLOB.atom_initializing = null
	fdel(TGUI_FIXTURES_FILE)
	text2file(json_encode(fixtures), TGUI_FIXTURES_FILE)
	log_world("tgui fixtures: [length(fixtures)] windows from [tried] types, [length(failed)] failed; wrote [TGUI_FIXTURES_FILE]")
	TEST_ASSERT(length(fixtures) > 0, "at least one window's data was captured")

#undef TGUI_FIXTURES_FILE
#undef FIXTURE_DATUM_ROOTS
