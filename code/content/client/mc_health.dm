// The data of the MC Health panel (tgui-panel/statpanel/McHealth.tsx; the Health page of the stat panel's Server view). Built only while an
// admin has the panel open (statpanel_service.dm), a slice of a few ms a fire, from numbers the kernel, the garbage collector, the registries
// and the Rust metrics already keep. Nothing here walks a big table in one go and nothing is built per client:
//  - the payload is groups of sections (GLOB.mc_health_groups): the fast one (the tick graph, the header, the 5 s window) every MC_HEALTH_FAST_EVERY,
//    the slow ones every MC_HEALTH_SLOW_EVERY;
//  - a group is built by units (mc_health_unit()); a unit is bounded work or one slice of a table walk (the attribution table, the ledger, the
//    sample windows, the churn counts), and mc_health_pump() runs units until MC_HEALTH_PUMP_MS is spent, so a group completes over several fires;
//  - each finished section is JSON- and url-encoded once (publish()); every admin's send is the pieces that changed for it, joined
//    (statpanel_service.dm set_MC_tab()), so a send costs a loop over the sections and one string.
// The few new readings: the entity census (every MC_HEALTH_CENSUS_EVERY), the Rust process memory and frame histogram
// (verdigris/ffi/src/frame.rs) and a churn read that leaves the metrics source's window alone (/datum/churn_census/proc/peek()).

/// How long one census of objects, turfs and areas is used before it is taken again.
#define MC_HEALTH_CENSUS_EVERY (1 MINUTES)
/// The recorded ticks the panel draws.
#define MC_HEALTH_TICKS 120
/// The busiest keys of each churn kind the panel lists.
#define MC_HEALTH_CHURN_TOP 5
/// How often the fast sections (the header, the 5 s window, the recent ticks) are built, and the slow ones (the longer windows, the kernel, the
/// attribution table, the collector, the counts, the census, the native metrics).
#define MC_HEALTH_FAST_EVERY (1 SECONDS)
#define MC_HEALTH_SLOW_EVERY (5 SECONDS)
/// How often the ledger (the kernel's time by category, with the heaviest names of each: several thousand rows to rank) is built: its own group, and the slowest.
#define MC_HEALTH_LEDGER_EVERY (30 SECONDS)
/// The ms one pump (one fire of the stat panel system) spends building: units run until it is spent, and a walk takes only what is left of it. A
/// native call or one section's JSON cannot be cut, so a unit may pass it a little (MC_HEALTH_UNIT_LOG_MS logs one that does).
#define MC_HEALTH_PUMP_MS 1.5
/// A unit at least this long is logged (MC_HEALTH).
#define MC_HEALTH_UNIT_LOG_MS 2
/// The most one client's MC send may take (assembling and sending its pieces: what the panel adds to a client's turn). A longer one is logged.
#define MC_HEALTH_TURN_MS 2
/// The systems the attribution group expands: the panel's top 8 (km_panel_data()'s are sorted heaviest first), as two sections of four.
#define MC_HEALTH_ATTRIBUTION_SYSTEMS 8
#define MC_HEALTH_ATTRIBUTION_FIRST 4

#define MC_GROUP_FAST "fast"
#define MC_GROUP_WINDOWS "windows"
#define MC_GROUP_KERNEL "kernel"
#define MC_GROUP_ATTRIBUTION "attribution"
#define MC_GROUP_LEDGER "ledger"
#define MC_GROUP_COUNTS "counts"
#define MC_GROUP_CENSUS "census"
#define MC_GROUP_RUST "rust"

/// The Rust metric families the panel reads, in one call that refreshes the sampled gauges first (verdigris_metrics_panel(), about once a
/// second while the panel is open; it does not wait for the server metrics source, which may be off).
GLOBAL_LIST_INIT(mc_health_rust_families, list("sim.", "frame.", "ffi.calls_total", "ffi.errors_total", "jobs.pending", "alloc.", "process.", "world.awake.", "world.stepped."))

/// The groups of sections, in the order a panel that has none of them is filled in (the tick graph first); "attribution" reads the systems the kernel group found.
GLOBAL_LIST_INIT(mc_health_groups, list(MC_GROUP_FAST, MC_GROUP_WINDOWS, MC_GROUP_KERNEL, MC_GROUP_ATTRIBUTION, MC_GROUP_LEDGER, MC_GROUP_COUNTS, MC_GROUP_CENSUS, MC_GROUP_RUST))

/// What the panel's data is built into: the sections' encoded pieces, which group is being built and how far, and the counters the bounds are tested against.
/datum/mc_health_build
	/// section -> its version (a counter that rises when the section is published) and its piece: the url-encoded JSON of "section":value, ready to join.
	/// Insertion order is the order a whole send lists them in.
	var/list/versions
	var/list/pieces
	/// section -> the value as published (tests, and the rare payload that needs the admin-link pass).
	var/list/values
	var/version = 0
	/// group -> world time it was last started.
	var/list/started_at
	/// The group being built, the unit it is at, and what its units carry to the next one.
	var/group
	var/step = 1
	var/list/pending
	/// The state a sliced unit carries between pumps: a table walk, a sample window, the churn read (the one its group is at is set, the rest are null).
	var/datum/km_ledger_walk/ledger_walk
	var/datum/km_attr_sys_walk/attr_walk
	var/datum/mc_churn_walk/churn_walk
	var/datum/perf_window_walk/window_walk
	/// The systems the kernel group last found (the attribution group expands the first MC_HEALTH_ATTRIBUTION_SYSTEMS of them).
	var/list/systems
	/// The recent-tick rows as last built, and how many ticks the flight recorder had counted then (only the new ticks are read each time).
	var/list/tick_rows
	var/list/tick_pieces
	var/tick_count = 0
	/// TRUE when a published section holds the admin-link placeholder (its piece cannot be shared: send_message() fills it per client).
	var/has_href = FALSE
	// ---- the counters the bounds are tested against ----
	var/pumps = 0
	var/units = 0
	var/groups_built = 0
	/// The ms of the dearest pump and unit so far, and the ms spent in all pumps.
	var/max_pump_ms = 0
	var/max_unit_ms = 0
	var/total_ms = 0
	/// Pumps that ran well past their budget (a native call or one section's JSON cannot be cut).
	var/overruns = 0
	/// Rows and samples walked in slices, and the slices.
	var/walked = 0
	var/slices = 0
	/// The ms the group being built has taken over its pumps, and the dearest group so far.
	var/group_ms = 0
	var/group_max_ms = 0

CAPABILITIES(/datum/mc_health_build)
	owns_one(nameof(ledger_walk), /datum/km_ledger_walk)
	owns_one(nameof(attr_walk), /datum/km_attr_sys_walk)
	owns_one(nameof(churn_walk), /datum/mc_churn_walk)
	owns_one(nameof(window_walk), /datum/perf_window_walk)

/datum/mc_health_build/New()
	. = ..()
	versions = list()
	pieces = list()
	values = list()
	started_at = list()

/// Encodes `value` once as the section `name` and gives it a new version.
/datum/mc_health_build/proc/publish(name, value)
	var/json = json_encode(value)
	if(findtext(json, HREF_TOKEN_PLACEHOLDER))
		has_href = TRUE
	values[name] = value
	pieces[name] = url_encode("\"[name]\":[json]")
	versions[name] = ++version

/// What a client that holds the sections named in `sent` (section -> version, and "coord_entry" -> its last coordinates; updated here) lacks: null when
/// it lacks nothing, else list("payload" = the url-encoded JSON of the update_mc message's payload (the build's pieces joined, nothing encoded again), "sections" = how
/// many it carries, "whole" = TRUE when that is every section, "changed" = their values (only when a section holds an admin link, which send_message() must fill for the client)).
/datum/mc_health_build/proc/client_update(list/sent, coord)
	var/list/parts = list()
	var/list/changed
	for(var/section in versions)
		var/at = versions[section]
		if(sent[section] == at)
			continue
		sent[section] = at
		parts += pieces[section]
		if(has_href)
			LAZYSET(changed, section, values[section])
	if(!length(parts) && sent["coord_entry"] == coord)
		return null
	sent["coord_entry"] = coord
	var/whole = length(parts) == length(versions)
	var/payload
	if(!has_href)
		payload = "[url_encode("{\"mc_metrics\":{")][jointext(parts, url_encode(","))][url_encode("},\"partial\":[whole ? "false" : "true"],\"coord_entry\":[json_encode(coord)]}")]"
	return list("payload" = payload, "sections" = length(parts), "whole" = whole, "changed" = changed)

/// Gives the section `name` a new version with `piece` as its encoded form: for a section that keeps its own pieces and joins them (the tick graph), which
/// would otherwise be encoded whole every second.
/datum/mc_health_build/proc/publish_piece(name, value, piece)
	values[name] = value
	pieces[name] = piece
	versions[name] = ++version

/// The group `now` calls for: the first never built, else the one most overdue (its age over its period); null when none is due.
/datum/mc_health_build/proc/next_group(now)
	var/best
	var/best_ratio = 1
	for(var/g in GLOB.mc_health_groups)
		var/at = started_at[g]
		if(isnull(at))
			return g
		var/ratio = (now - at) / group_period(g)
		if(ratio >= best_ratio)
			best = g
			best_ratio = ratio
	return best

/// How often group `g` is built.
/datum/mc_health_build/proc/group_period(g)
	switch(g)
		if(MC_GROUP_FAST)
			return MC_HEALTH_FAST_EVERY
		if(MC_GROUP_LEDGER)
			return MC_HEALTH_LEDGER_EVERY
	return MC_HEALTH_SLOW_EVERY

/// Lets go of the walks a group left half done (a group started over).
/datum/mc_health_build/proc/drop_walks()
	rel_clear(src, nameof(ledger_walk))
	rel_clear(src, nameof(attr_walk))
	rel_clear(src, nameof(churn_walk))
	rel_clear(src, nameof(window_walk))

/// Starts building `g`.
/datum/mc_health_build/proc/begin_group(g, now)
	group = g
	step = 1
	pending = list()
	drop_walks()
	group_ms = 0
	started_at[g] = now

/// Runs units of the group being built (then of the next one due) until `budget_ms` is spent. Returns the ms it took.
/proc/mc_health_pump(datum/mc_health_build/B, budget_ms = MC_HEALTH_PUMP_MS)
	var/started = TICK_USAGE_REAL
	var/spent = 0
	B.pumps++
	while(spent < budget_ms)
		if(!B.group)
			var/now = TIME_NOW(CLOCK_WORLD)
			var/next = B.next_group(now)
			if(!next)
				break
			B.begin_group(next, now)
		var/unit_started = TICK_USAGE_REAL
		var/at_step = B.step
		var/group_name = B.group
		var/group_done = mc_health_unit(B, budget_ms - spent)
		var/unit_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - unit_started)
		B.units++
		B.group_ms += unit_ms
		B.max_unit_ms = max(B.max_unit_ms, unit_ms)
		if(unit_ms >= MC_HEALTH_UNIT_LOG_MS)
			log_world("MC_HEALTH: unit [at_step] of the [group_name] group took [round(unit_ms, 0.1)] ms (the slowest unit so far [round(B.max_unit_ms, 0.1)] ms)")
		if(group_done)
			B.groups_built++
			B.group_max_ms = max(B.group_max_ms, B.group_ms)
			if(B.group_ms >= 5)
				log_world("MC_HEALTH: the [group_name] group took [round(B.group_ms, 0.1)] ms over its units (the slowest group so far [round(B.group_max_ms, 0.1)] ms)")
			B.group = null
		spent = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	if(spent > budget_ms + MC_HEALTH_UNIT_LOG_MS)
		B.overruns++
	B.max_pump_ms = max(B.max_pump_ms, spent)
	B.total_ms += spent
	return spent

/// Builds every group in full, at once (tests and one-off reads): the sections by name.
/proc/mc_health_build_all(datum/mc_health_build/B)
	for(var/g in GLOB.mc_health_groups)
		B.begin_group(g, TIME_NOW(CLOCK_WORLD))
		while(!mc_health_unit(B, INFINITY))
			B.units++
		B.units++
		B.group = null
	return B.values

/// The whole payload of the panel, built now into a build of its own (tests).
/proc/mc_health_data()
	return mc_health_build_all(new /datum/mc_health_build)

/// One unit of the group being built: bounded work, a slice of at most `slice_ms` when it is a walk. TRUE when the group is complete (all its sections published).
/proc/mc_health_unit(datum/mc_health_build/B, slice_ms)
	switch(B.group)
		if(MC_GROUP_FAST)
			// The tick graph is the first section built and sent: it is on the panel from the first send, before any slow group.
			if(B.step == 1)
				var/list/tick_rows = mc_health_recent_ticks(B)
				var/ticks_head = url_encode("\"ticks\":\[")
				var/ticks_tail = url_encode("]")
				B.publish_piece("ticks", tick_rows, "[ticks_head][jointext(B.tick_pieces, url_encode(","))][ticks_tail]")
				B.step = 2
				return FALSE
			var/list/history = Kernel.perf_tick_usage
			B.publish("header", list(
				"tick_budget_ms" = world.tick_lag * 100,
				"target_tps" = world.fps,
				"current_usage" = history.len ? history[history.len] : 0,
				"maptick" = MAPTICK_LAST_INTERNAL_TICK_USAGE,
				"tidi" = time_track_time_dilation_current(),
			))
			B.publish("window_5s", Kernel.performance_window(5))
			B.publish("stalls", km_meter().stalls || list())
			return TRUE
		if(MC_GROUP_WINDOWS)
			switch(B.step)
				if(1)
					if(mc_health_window_step(B, 30, slice_ms))
						B.publish("window_30s", B.pending["window"])
						B.step = 2
				if(2)
					if(mc_health_window_step(B, 300, slice_ms))
						B.publish("window_5m", B.pending["window"])
						B.step = 3
				else
					B.publish("outliers", Kernel.perf_outliers.Copy())
					return TRUE
			return FALSE
		if(MC_GROUP_KERNEL)
			switch(B.step)
				if(1)
					B.publish("subsystems", mc_health_subsystems())
					B.step = 2
				if(2)
					var/list/panel = km_panel_data()
					B.systems = panel["systems"]
					B.publish("kernel", panel)
					B.step = 3
				else
					B.publish("runtime", list(
						"cpu" = world.cpu,
						"clients" = length(GLOB.clients),
						"tick_drift" = Kernel.tickdrift,
						"kernel_ticks" = kernel().ticks,
						"kernel_last_tick_ms" = kernel().last_tick_ms,
					))
					return TRUE
			return FALSE
		// Every ms of the kernel's iteration by category with its heaviest names: its own group, a slice at a time, the slowest to come round.
		if(MC_GROUP_LEDGER)
			var/datum/km_ledger/ledger = GLOB.km_ledger
			if(!B.ledger_walk)
				rel_set(B, nameof(B.ledger_walk), ledger.walk_begin(KM_LEDGER_TOP))
			var/at_before = B.ledger_walk.at
			var/ledger_done = ledger.walk_step(B.ledger_walk, slice_ms)
			B.walked += B.ledger_walk.at - at_before
			B.slices++
			if(!ledger_done)
				return FALSE
			B.publish("ledger", ledger.walk_result(B.ledger_walk))
			rel_clear(B, nameof(B.ledger_walk))
			return TRUE
		// The callbacks behind the panel's top 8 systems (two sections of four): one walk of the attribution table, a slice at a time.
		if(MC_GROUP_ATTRIBUTION)
			var/datum/km_attr/attr = km_meter().attr
			if(!attr || !length(B.systems))
				B.publish("attribution", list())
				B.publish("attribution_rest", list())
				return TRUE
			if(!B.attr_walk)
				var/datum/km_systems/registry = km_systems()
				var/list/wanted = list()
				for(var/i in 1 to min(length(B.systems), MC_HEALTH_ATTRIBUTION_SYSTEMS))
					var/list/S = B.systems[i]
					var/sys = registry.index_by_key?[S["key"]]
					if(sys)
						wanted["[sys]"] = list(S["key"], i)
				rel_set(B, nameof(B.attr_walk), attr.sys_walk_begin(5, wanted))
			var/visited_before = B.attr_walk.visited
			var/attr_done = attr.sys_walk_step(B.attr_walk, slice_ms)
			B.walked += B.attr_walk.visited - visited_before
			B.slices++
			if(!attr_done)
				return FALSE
			var/list/first = list()
			var/list/rest = list()
			var/datum/km_attr_sys_walk/finished = B.attr_walk
			for(var/sys_key in finished.best)
				var/list/rows = list()
				for(var/list/row as anything in finished.best[sys_key])
					var/list/data = attr.row_data(row)
					rows += list(list(data["source"], data["kind"], data["count"], data["total_ms"], data["max_ms"]))
				if(!length(rows))
					continue
				var/list/target = finished.wanted[sys_key]
				if(target[2] <= MC_HEALTH_ATTRIBUTION_FIRST)
					first[target[1]] = rows
				else
					rest[target[1]] = rows
			rel_clear(B, nameof(B.attr_walk))
			B.publish("attribution", first)
			B.publish("attribution_rest", rest)
			return TRUE
		if(MC_GROUP_COUNTS)
			if(B.step == 1)
				B.publish("gc", mc_health_gc())
				B.step = 2
				return FALSE
			if(!B.churn_walk)
				var/datum/mc_churn_walk/started_walk = new
				started_walk.kinds = GLOB.churn_census.peek()
				for(var/kind in started_walk.kinds)
					started_walk.names += kind
				rel_set(B, nameof(B.churn_walk), started_walk)
			var/churn_before = B.churn_walk.visited
			var/churn_done = mc_health_churn_step(B.churn_walk, slice_ms)
			B.walked += B.churn_walk.visited - churn_before
			B.slices++
			if(!churn_done)
				return FALSE
			B.publish("churn", B.churn_walk.out)
			rel_clear(B, nameof(B.churn_walk))
			return TRUE
		if(MC_GROUP_CENSUS)
			B.publish("entities", mc_health_entities())
			return TRUE
		if(MC_GROUP_RUST)
			B.publish("rust", mc_health_rust())
			return TRUE
	return TRUE

/// One slice of the sample window of the last `seconds` seconds, kept in B.window_walk, its result in B.pending["window"]. TRUE when it is complete.
/proc/mc_health_window_step(datum/mc_health_build/B, seconds, slice_ms)
	if(!B.window_walk)
		var/datum/perf_window_walk/started_walk = Kernel.performance_walk_begin(seconds)
		if(!started_walk)
			B.pending["window"] = GLOB.empty_performance_window
			return TRUE
		rel_set(B, nameof(B.window_walk), started_walk)
	var/samples_before = B.window_walk.samples
	var/done = Kernel.performance_walk_step(B.window_walk, slice_ms)
	B.walked += B.window_walk.samples - samples_before
	B.slices++
	if(done)
		B.pending["window"] = Kernel.performance_walk_result(B.window_walk)
		rel_clear(B, nameof(B.window_walk))
	return done

/// The last MC_HEALTH_TICKS ticks of the flight recorder: list(usage, list(top keys), list(top ms), pre-kernel usage, map send usage) each, oldest first.
/// `B` keeps the rows between builds, so only the ticks recorded since the last one are read (a build that finds the whole window new reads all of it).
/proc/mc_health_recent_ticks(datum/mc_health_build/B)
	var/datum/tick_meter/meter = km_meter()
	var/datum/km_systems/registry = km_systems()
	if(!B)
		B = new
	var/count = meter.ring_count
	var/fresh = count - B.tick_count
	var/first = B.tick_count + 1
	if(!B.tick_rows || fresh < 0 || fresh >= MC_HEALTH_TICKS)
		B.tick_rows = list()
		B.tick_pieces = list()
		first = max(1, count - MC_HEALTH_TICKS + 1)
	var/list/rows = B.tick_rows
	var/list/encoded = B.tick_pieces
	for(var/n in first to count)
		var/at = meter.ring_index(n)
		var/list/keys = list()
		var/list/mss = list()
		var/base = (at - 1) * KM_TOP_N
		for(var/k in 1 to KM_TOP_N)
			var/idx = meter.fr_top_sys[base + k]
			if(!idx)
				continue
			keys += registry.keys[idx]
			mss += round(meter.fr_top_ms[base + k], 0.01)
		var/list/row = list(round(meter.fr_usage[at], 0.1), keys, mss, round(meter.fr_pre[at], 0.1), round(meter.fr_maptick[at], 0.1))
		rows += list(row)
		encoded += url_encode(json_encode(row)) // each tick is encoded once, when it is first read
	if(length(rows) > MC_HEALTH_TICKS)
		rows.Cut(1, length(rows) - MC_HEALTH_TICKS + 1)
		encoded.Cut(1, length(encoded) - MC_HEALTH_TICKS + 1)
	B.tick_count = count
	return rows

/// The hosted systems with periodic work: their cost per fire and that cost as a share of one tick ("usage", % of the tick budget).
/proc/mc_health_subsystems()
	. = list()
	var/budget_ms = world.tick_lag * 100
	for(var/datum/system/S as anything in kernel_pure_systems())
		if(!S.times_fired && !S.fire_cost)
			continue
		. += list(list(
			"name" = S.name,
			"usage" = budget_ms ? round(S.fire_cost / budget_ms * 100, 0.01) : 0,
			"overrun" = S.tick_overrun,
			"cost" = S.fire_cost,
			"fires" = S.times_fired,
			"ref" = handle_of(S),
		))

/// The garbage collector, as numbers the panel says in words.
/proc/mc_health_gc()
	var/datum/system/garbage/G = SSgarbage
	if(!G)
		return null
	var/list/queued = list()
	for(var/list/queue as anything in G.queues)
		queued += length(queue)
	return list(
		"queued" = queued,
		"deleted_cleanly" = G.totalgcs,
		"forced" = G.totaldels,
		"leaks" = G.total_leaks,
	)

/// Players and the registries every tick keeps, plus the census of objects, turfs and areas (taken at most every MC_HEALTH_CENSUS_EVERY), with
/// the previous census so the panel shows growth.
/proc/mc_health_entities()
	var/list/census = mc_health_census()
	return list(
		"players" = length(GLOB.clients),
		"mobs" = REGISTRY_COUNT(REGISTRY_MOBS),
		"living" = REGISTRY_COUNT(REGISTRY_LIVING_MOBS),
		"humans" = REGISTRY_COUNT(REGISTRY_HUMANS),
		"machines" = REGISTRY_COUNT(REGISTRY_MACHINES),
		"census" = census[1],
		"previous" = census[2],
	)

/// list(the latest census, the one before) of objects, turfs and areas, each list("objects", "turfs", "areas", "at" = now, "ms"). Turfs are
/// the map's size; areas the area types the registry holds (an area is one atom per type); objects what world.contents holds besides them and the mobs.
/proc/mc_health_census()
	var/static/list/latest
	var/static/list/previous
	var/now = TIME_NOW(CLOCK_WORLD)
	if(latest && now - latest["at"] < MC_HEALTH_CENSUS_EVERY)
		return list(latest, previous)
	var/started = TICK_USAGE_REAL
	var/turfs = world.maxx * world.maxy * world.maxz
	var/areas = length(GLOB.areas_by_type)
	var/objects = max(0, length(world.contents) - turfs - areas - REGISTRY_COUNT(REGISTRY_MOBS))
	previous = latest
	latest = list("objects" = objects, "turfs" = turfs, "areas" = areas, "at" = now, "ms" = round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - started), 0.01))
	return list(latest, previous)

/// The busiest MC_HEALTH_CHURN_TOP keys of each churn kind in the current window, read without ending the window (the metrics source owns it).
/proc/mc_health_churn()
	var/datum/mc_churn_walk/W = new
	W.kinds = GLOB.churn_census.peek()
	for(var/kind in W.kinds)
		W.names += kind
	mc_health_churn_step(W, INFINITY)
	return W.out

/// The churn read, kept between slices: the counts are walked by position, a few keys at a time.
/datum/mc_churn_walk
	/// kind -> the live counts of the window (read, never written), the kinds' names, and the one being read.
	var/list/kinds
	var/list/names
	var/kind_at = 1
	var/kind
	var/list/counts
	var/key_at = 1
	var/list/top
	/// kind -> its busiest keys, list("key", count) each.
	var/list/out
	/// Keys read.
	var/visited = 0

/datum/mc_churn_walk/New()
	. = ..()
	names = list()
	out = list()

/// Reads churn keys for `budget_ms`, checked every KA_WALK_CHECK_ROWS keys. TRUE when every kind is read.
/proc/mc_health_churn_step(datum/mc_churn_walk/W, budget_ms)
	var/started = TICK_USAGE_REAL
	var/since_check = 0
	while(W.counts || W.kind_at <= length(W.names))
		if(!W.counts)
			W.kind = W.names[W.kind_at++]
			W.counts = W.kinds[W.kind]
			W.top = list()
			W.key_at = 1
			if(!length(W.counts))
				W.out[W.kind] = W.top
				W.counts = null
				continue
		var/list/counts = W.counts
		var/list/top = W.top
		while(W.key_at <= length(counts))
			var/key = counts[W.key_at++]
			var/n = counts[key]
			W.visited++
			var/at = length(top) + 1
			for(var/i in 1 to length(top))
				if(n > top[i][2])
					at = i
					break
			if(at <= MC_HEALTH_CHURN_TOP)
				top.Insert(at, list(list("[key]", n)))
				if(length(top) > MC_HEALTH_CHURN_TOP)
					top.len = MC_HEALTH_CHURN_TOP
			if(!(++since_check % KA_WALK_CHECK_ROWS) && TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) >= budget_ms)
				if(W.key_at > length(counts))
					W.out[W.kind] = top
					W.counts = null
				return FALSE
		W.out[W.kind] = top
		W.counts = null
	return TRUE

/// The Rust metrics of the families the panel reads, flat (name -> number; a histogram as its list), or null when the library did not answer.
/proc/mc_health_rust()
	var/list/out = verdigris_metrics_panel(GLOB.mc_health_rust_families)
	return length(out) ? out : null

// ---- the Advanced section's links: View Variables of a controller named by the link, not by a ref (the server resolves the name) ----

CAPABILITIES_PART(/datum/admins, mc_health)
	op("mc_vv", topic("mc_vv", arg("mc_vv", schema_text(16))), needs(req_rights(R_DEBUG)), then(PROC_REF(topic_mc_vv)))

/// The datum a MC Health link names: "kernel", "globals" or "config"; null for any other name.
/proc/mc_health_vv_target(name)
	switch(name)
		if("kernel")
			return Kernel
		if("globals")
			return GLOB
		if("config")
			return config
	return null

/// "View Kernel vars" and its siblings: View Variables of the named controller for the admin who clicked.
/datum/admins/proc/topic_mc_vv(datum/act/op/A, href_mc_vv)
	var/datum/target = mc_health_vv_target(href_mc_vv)
	if(!target)
		log_admin("[key_name(A.actor)] asked the MC Health panel for View Variables of an unknown name '[href_mc_vv]'.")
		return
	owner()?.debug_variables(target)
