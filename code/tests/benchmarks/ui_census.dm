// The ui_data census: every window the build declares (the generated tgui/packages/tgui/interfaces/generated/*.d.ts name each window's type),
// built for a dummy viewer: what one ui_data() and one static data build cost, how big each payload is, and whether two builds in a row are
// identical (a push the window drops as unchanged). UI_CENSUS lines rank them by the cost of an update.
//
// Run: tools/build/build.sh bench --scenario=ui_census

#define UI_CENSUS_DIR "tgui/packages/tgui/interfaces/generated/"
#define UI_CENSUS_BUILDS 5

/datum/benchmark/ui_census
	id = "ui_census"
	description = "Every window's ui_data and static data: build time and payload size, ranked"

/// Window name -> the type path declaring it, read from the generated window types' headers.
/datum/benchmark/ui_census/proc/declared_windows()
	. = list()
	for(var/filename in flist(UI_CENSUS_DIR))
		if(copytext(filename, -5) != ".d.ts")
			continue
		var/text = file2text("[UI_CENSUS_DIR][filename]")
		var/at = findtext(text, " of /")
		if(!at)
			continue
		var/stop = findtext(text, " (", at + 4)
		var/path_text = copytext(text, at + 4, stop)
		var/path = text2path(path_text)
		if(path)
			.[copytext(filename, 1, -5)] = path

/datum/benchmark/ui_census/Run()
	wait_for_assets()
	var/turf/T = locate(world.maxx / 2, world.maxy / 2, 1)
	var/mob/living/carbon/human/user = new(T)
	var/list/windows = declared_windows()
	count_metric("windows_declared", length(windows), "windows")
	var/list/rows = list()
	var/built = 0
	var/failed = 0
	for(var/window in windows)
		var/path = windows[window]
		var/datum/holder
		try
			holder = ispath(path, /atom) ? new path(T) : new path()
		catch(var/exception/e)
			failed++
			log_world("UI_CENSUS [window] ([path]): could not be made ([e])")
			continue
		if(!holder)
			failed++
			continue
		var/list/row = measure(window, holder, user)
		if(row)
			built++
			rows += list(row)
		// An atom made here goes again; a datum is left (some windows' datums are singletons nothing may delete).
		if(isatom(holder) && !QDELETED(holder))
			try
				qdel(holder)
			catch(var/exception/e3)
				log_world("UI_CENSUS [window] ([path]): could not be deleted ([e3])")
	count_metric("windows_built", built, "windows", better = "higher")
	count_metric("windows_unbuildable", failed, "windows")
	// Ranked by the cost of an update (what every push of an open window pays).
	rows = sortTim(rows, GLOBAL_PROC_REF(cmp_ui_census_rows))
	var/rank = 0
	for(var/list/row as anything in rows)
		rank++
		log_world("UI_CENSUS #[rank] [row["window"]] ([row["type"]]): ui_data [row["data_ms"]] ms [row["data_bytes"]] B [row["stable"] ? "stable" : "CHANGES EVERY BUILD"]; static [row["static_ms"]] ms [row["static_bytes"]] B")
	detail("ui_census", rows)

/// One window's numbers: a row, or null when its data could not be built.
/datum/benchmark/ui_census/proc/measure(window, datum/holder, mob/user)
	var/list/first
	var/list/data
	var/started = TICK_USAGE_REAL
	try
		for(var/i in 1 to UI_CENSUS_BUILDS)
			data = list()
			present_tgui_data(holder, user, data)
			if(!first)
				first = data
	catch(var/exception/e)
		log_world("UI_CENSUS [window] ([holder.type]): ui_data failed ([e])")
		return null
	var/data_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / UI_CENSUS_BUILDS
	var/list/static_data
	started = TICK_USAGE_REAL
	try
		static_data = holder.tgui_static_data(user)
	catch(var/exception/e2)
		log_world("UI_CENSUS [window] ([holder.type]): static data failed ([e2])")
	var/static_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	var/data_json = json_encode(data)
	return list(
		"window" = window,
		"type" = "[holder.type]",
		"data_ms" = round(data_ms, 0.001),
		"data_bytes" = length(data_json),
		"stable" = json_encode(first) == data_json,
		"static_ms" = round(static_ms, 0.001),
		"static_bytes" = length(json_encode(static_data)),
	)

/proc/cmp_ui_census_rows(list/a, list/b)
	return b["data_ms"] - a["data_ms"]

#undef UI_CENSUS_DIR
#undef UI_CENSUS_BUILDS
