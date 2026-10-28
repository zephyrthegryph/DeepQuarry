// Census of what an idle server spends its timers and tracked writes on (doc/rewrite/server_bench_20261027.md). Off unless the localhost probe turns it on
// (`census&on=1`), so the hot paths pay one global read. `census` returns the tables and `census&reset=1` clears them.
//   timers: "[handler]|[owner type]" -> list(fires, ms, owners)   state: "[type].[var]|[writer proc]" -> writes
GLOBAL_VAR_INIT(census_on, FALSE)
GLOBAL_LIST_EMPTY(census_timers)
GLOBAL_LIST_EMPTY(census_timer_owners)
GLOBAL_LIST_EMPTY(census_state)

/// One timer fire of `holder` calling `handler`, taking `ms`.
/proc/census_timer_note(datum/holder, handler, ms)
	var/key = "[handler]|[holder.type]"
	var/list/row = GLOB.census_timers[key]
	if(!row)
		row = list(0, 0, 0)
		GLOB.census_timers[key] = row
		GLOB.census_timer_owners[key] = list()
	row[1]++
	row[2] += ms
	var/list/owners = GLOB.census_timer_owners[key]
	if(!owners["\ref[holder]"])
		owners["\ref[holder]"] = TRUE
		row[3]++

/// One tracked write of `var_name` on `E` by the proc that called state_changed()'s setter.
/proc/census_state_note(datum/E, var_name, callee/writer)
	var/key = "[E.type].[var_name]|[writer?.caller ? writer.caller.proc : "?"]"
	GLOB.census_state[key]++

/// The census as text, the busiest 40 of each table.
/proc/census_report(reset = FALSE)
	var/list/out = list()
	var/list/timers = list()
	for(var/key in GLOB.census_timers)
		var/list/row = GLOB.census_timers[key]
		timers += list(list("callback" = key, "fires" = row[1], "ms" = round(row[2], 0.01), "ms_each" = round(row[2] / max(row[1], 1), 0.001), "owners" = row[3]))
	timers = sortTim(timers, GLOBAL_PROC_REF(cmp_census_ms_desc))
	if(length(timers) > 40)
		timers.Cut(41)
	out["timers"] = timers
	var/list/state = sortTim(GLOB.census_state.Copy(), GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	var/list/top = list()
	for(var/key in state)
		top[key] = state[key]
		if(length(top) >= 40)
			break
	out["state_writes"] = top
	if(reset)
		GLOB.census_timers = list()
		GLOB.census_timer_owners = list()
		GLOB.census_state = list()
	return json_encode(out)

/proc/cmp_census_ms_desc(list/a, list/b)
	return b["ms"] - a["ms"]
