// Captures real window data for the tgui render test (tgui/packages/tgui/interfaces/renderAll.test.tsx). For every /obj type that declares
// interface(), one fresh instance per window name is spawned and its tgui_data() and tgui_static_data() for a fresh human viewer are written,
// keyed by window name, to TGUI_FIXTURES_FILE. Regenerate: `bash tools/dq_focused_test.sh /datum/unit_test/dq_tgui_ui_data_fixtures`, then
// copy data/tgui_fixtures/ui_data.json to tgui/packages/tgui/interfaces/__fixtures__/ui_data.json. A type that fails to spawn or whose data
// faults is logged and skipped (the next type with the same window is tried); the windows with no fixture are logged at the end.

#define TGUI_FIXTURES_FILE "data/tgui_fixtures/ui_data.json"

/datum/unit_test/dq_tgui_ui_data_fixtures

/datum/unit_test/dq_tgui_ui_data_fixtures/proc/spawn_host(type)
	return allocate(type)

/datum/unit_test/dq_tgui_ui_data_fixtures/proc/window_data(datum/host, mob/user)
	var/list/data = list()
	var/list/static_data = host.tgui_static_data(user)
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
	for(var/type in typesof(/obj))
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
		var/datum/result/made = safe_call(PROC_REF(spawn_host), type)
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
	fdel(TGUI_FIXTURES_FILE)
	text2file(json_encode(fixtures), TGUI_FIXTURES_FILE)
	log_world("tgui fixtures: [length(fixtures)] windows from [tried] types, [length(failed)] failed; wrote [TGUI_FIXTURES_FILE]")
	TEST_ASSERT(length(fixtures) > 0, "at least one window's data was captured")

#undef TGUI_FIXTURES_FILE
