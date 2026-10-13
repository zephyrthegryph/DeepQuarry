// The staleness checker (doc/rewrite/final_api.html section 7, "The staleness checker").
//
// Everything the engine caches on the promise "an input publishes before it changes" is recomputed from scratch and compared:
//
//   stat      a stat served from its var or its record (stat_value(), recompute.dm) and every stat var of a tracked holder (the sweep)
//   draw      an atom whose draw() the engine did not re-run because no declared read changed (state_changed() notes the var that was skipped;
//             the next presentation drain re-draws it dry and compares the look key), and every swept atom (the sweep)
//   derive    a derive() value (type_derive.dm) the sweep recomputes
//   image     a keyed shared image (look_cached_image()) rebuilt and compared on every hit
//
// A mismatch is a STALE report: the kind, the holder's type and the thing, the trigger that served the cache, what the fresh computation gave, the
// inputs that changed since the last clean check (the var that was written with no publish), and the frames that led to the read. Reads that do not
// go through a proc (a plain `L.density`) cannot be intercepted by DM, so the sweep covers them: it runs at the end of every test and on the
// presentation drain.
//
// Three modes, set by the build and the config:
//   strict   test builds (UNIT_TESTS, not BENCHMARK): every check runs, snapshots name the culprit var, a report fails the current test (or the
//            boot gate before the first one) unless a test expects it (GLOB.staleness_expected).
//   sampled  STALENESS_SAMPLE N in the config, any build: one check in N, logging only, no snapshots. 0 (the default) is off.
//   off      nothing runs; the cost on a stat read is one global read.

#if defined(UNIT_TESTS) && !defined(BENCHMARK)
#define STALENESS_STRICT_BUILD TRUE
#else
#define STALENESS_STRICT_BUILD FALSE
#endif

/// Entities checked per presentation drain by the sweep (strict), and per sampled drain (one in N).
#define STALENESS_SWEEP_BUDGET 40
/// Older entities a test-end sweep checks beyond the ones created during the test.
#define STALENESS_TEST_END_OLD 400
/// Longest read-path text in a report.
#define STALENESS_CHAIN_MAX 700

/// TRUE in test builds: every check runs and a report fails the current test.
GLOBAL_VAR_INIT(staleness_strict, STALENESS_STRICT_BUILD)
/// The sampled live mode: one check in this many (STALENESS_SAMPLE in the config), 0 for off.
GLOBAL_VAR_INIT(staleness_sample, 0)
/// Strict or sampled: the one flag the hot paths read.
GLOBAL_VAR_INIT(staleness_on, STALENESS_STRICT_BUILD)
/// A test that provokes a report on purpose sets this: reports are recorded and logged, but do not fail the test. Cleared at the end of each test.
GLOBAL_VAR_INIT(staleness_expected, FALSE)
/// Greater than 0 while a check recomputes: nested reads are not checked again (they are checked on their own).
GLOBAL_VAR_INIT(staleness_depth, 0)
GLOBAL_VAR_INIT(staleness_checks, 0)
/// Checks that did not run: the value was legitimately pending (a marked stat, a queued redraw) or the fresh computation could not run.
GLOBAL_VAR_INIT(staleness_skipped, 0)
GLOBAL_VAR_INIT(staleness_found, 0)
/// Every report text this run (the tests read it).
GLOBAL_LIST_EMPTY(staleness_reports)
/// "ref|kind|what" -> TRUE: one report per cached thing.
GLOBAL_LIST_EMPTY(staleness_seen)
/// "kind|type|what" -> how many holders were stale this run (the work list).
GLOBAL_LIST_EMPTY(staleness_census)
/// "ref|kind|what" -> assoc input -> value at the last clean check (strict only).
GLOBAL_LIST_EMPTY(staleness_good)
/// ref -> list of var names written while the engine decided the draw reads none of them; checked at the next presentation drain.
GLOBAL_LIST_EMPTY(staleness_served)
/// ref -> TRUE for every entity the sweep walks (stat holders and swept atoms). Refs, never the entities, so a deleted one is not kept alive.
GLOBAL_LIST_EMPTY(stale_all)
/// Refs added since the last test-end sweep.
GLOBAL_LIST_EMPTY(stale_new)
GLOBAL_VAR_INIT(stale_cursor, 1)

/// Reads the config once it is loaded (world/ConfigLoaded()).
/proc/staleness_configure()
	GLOB.staleness_sample = max(0, round(CONFIG_GET(number/staleness_sample)))
	GLOB.staleness_on = GLOB.staleness_strict || GLOB.staleness_sample > 0
	if(GLOB.staleness_sample > 0)
		log_world("STALENESS: sampled live mode on, one check in [GLOB.staleness_sample] (logging only)")

/// Whether this read is checked: not while a check runs, not while a map loads, always in strict mode, one in N when sampled.
/proc/staleness_gate()
	if(GLOB.staleness_depth)
		return FALSE
	if(materialization_host().map_loading())
		return FALSE
	if(GLOB.staleness_strict)
		return TRUE
	return GLOB.staleness_sample > 0 && rand(1, GLOB.staleness_sample) == 1

/// The sweep walks E from now on (it has stats, or it is swept for its look).
/proc/staleness_track(datum/E)
	if(!GLOB.staleness_on)
		return
	var/ref = REF(E)
	if(GLOB.stale_all[ref])
		return
	GLOB.stale_all[ref] = TRUE
	GLOB.stale_new += ref

/// Drops a destroyed entity from the sweep's index. The sweep prunes a dead ref only when it reaches it, so without this a
/// short-lived entity (anything with stats) leaves its ref in stale_all until then.
/proc/staleness_forget(datum/E)
	if(!GLOB.staleness_on)
		return
	var/ref = REF(E)
	GLOB.stale_all -= ref
	GLOB.stale_new -= ref

// ---------------------------------------------------------------- reporting

/// The frames that led to the check, innermost first, as text.
/proc/staleness_read_path()
	var/chain = ""
	for(var/callee/frame = caller; frame && length(chain) < STALENESS_CHAIN_MAX; frame = frame.caller)
		chain += " <- [frame.proc]"
	return chain

/// Files one report. `what` names the cached thing (a stat, "draw", a derive var, an image key), `detail` what the fresh computation gave,
/// `culprit` the inputs that moved without publishing (or the candidates when none was recorded).
/proc/staleness_report(kind, datum/E, what, trigger, detail, culprit)
	GLOB.staleness_found++
	var/census_key = "[kind]|[E ? E.type : "global"]|[what]"
	GLOB.staleness_census[census_key] = (GLOB.staleness_census[census_key] || 0) + 1
	var/seen_key = "[E ? REF(E) : "global"]|[kind]|[what]"
	if(GLOB.staleness_seen[seen_key])
		return
	GLOB.staleness_seen[seen_key] = TRUE
	var/path = staleness_read_path()
	var/msg = "STALE [kind]: [E ? E.type : "global"] [what] served from cache by [trigger], a fresh computation gives [detail]; [culprit ? culprit : "no input was recorded"][path]"
	GLOB.staleness_reports += msg
	log_world("STALENESS|[kind]|[E ? E.type : "global"]|[what]|[trigger]|[staleness_flat(detail)]|[staleness_flat(culprit ? culprit : "-")]")
	log_runtime(msg)
	if(!GLOB.staleness_strict || GLOB.staleness_expected)
		return
#if defined(UNIT_TESTS)
	if(GLOB.current_test)
		GLOB.current_test.Fail(msg, __FILE__, __LINE__)
		return
#endif
	stack_trace(msg)

/// Text with the log line's separators and line breaks taken out, so a report stays one `|`-separated row.
/proc/staleness_flat(text)
	text = replacetext("[text]", "|", "/")
	text = replacetext(text, "\n", " ")
	return copytext(text, 1, 300)

/// A fresh computation could not run (it threw, or it needs state the check cannot set up): counted, logged once per type and thing.
/proc/staleness_unchecked(kind, datum/E, what, exception/fault)
	GLOB.staleness_skipped++
	var/key = "unchecked|[kind]|[E?.type]|[what]"
	if(GLOB.staleness_seen[key])
		return
	GLOB.staleness_seen[key] = TRUE
	log_world("STALENESS|unchecked|[kind]|[E?.type]|[what]|[fault ? "[fault.name] at [fault.file]:[fault.line]" : "no cause"]")

// ---------------------------------------------------------------- input snapshots (strict mode names the culprit)

/// TRUE when two input values are the same, lists by content.
/proc/staleness_same(a, b)
	if(islist(a) || islist(b))
		if(!islist(a) || !islist(b))
			return FALSE
		var/list/la = a
		var/list/lb = b
		if(length(la) != length(lb))
			return FALSE
		for(var/i in 1 to length(la))
			if(la[i] != lb[i])
				return FALSE
		return TRUE
	return a == b

/// A list is copied so the snapshot does not follow an in-place change; anything else is itself.
/proc/staleness_copy(value)
	if(islist(value))
		var/list/L = value
		return L.Copy()
	return value

/// One input of a cached value: a var of the holder ("name"), or a var of what a single-valued link names ("link.name"). Null for anything else.
/proc/staleness_input_value(datum/E, input)
	if(!istext(input))
		return null
	var/dot = findtext(input, ".")
	if(!dot)
		if(input in E.vars)
			return staleness_copy(E.vars[input])
		return null
	var/link = copytext(input, 1, dot)
	var/rest = copytext(input, dot + 1)
	if(!(link in E.vars) || findtext(rest, ".") || findtext(rest, "\["))
		return null
	var/linked = E.vars[link]
	if(!isdatum(linked))
		return null
	var/datum/D = linked
	if(rest in D.vars)
		return staleness_copy(D.vars[rest])
	return null

/// The inputs of a cached value as text, from the generated reads: a var or "link.var".
/proc/staleness_input_names(list/inputs)
	. = list()
	for(var/input in inputs)
		if(!istext(input))
			continue
		if(findtext(input, "sys:") == 1 || findtext(input, "stat:") == 1 || findtext(input, "capkey:") == 1 || findtext(input, ":"))
			continue
		. |= input

/// Records the inputs' values after a clean check, so the next mismatch can name the one that moved.
/proc/staleness_snapshot(datum/E, snap_key, list/inputs)
	if(!GLOB.staleness_strict || !length(inputs))
		return
	var/list/snap = list()
	for(var/input in inputs)
		snap[input] = list(staleness_input_value(E, input))
	GLOB.staleness_good[snap_key] = snap

/// The culprit text for a mismatch: the inputs whose value moved since the last clean check, else the candidates.
/proc/staleness_culprit(datum/E, snap_key, list/inputs, extra)
	var/list/snap = GLOB.staleness_good[snap_key]
	var/list/moved = list()
	if(snap)
		for(var/input in snap)
			var/list/box = snap[input]
			var/now = staleness_input_value(E, input)
			if(!staleness_same(box[1], now))
				moved += "[input] ([islist(box[1]) ? "list" : box[1]] -> [islist(now) ? "list" : now])"
	var/text
	if(length(moved))
		text = "changed with no publish since the last clean check: [jointext(moved, ", ")]"
	else if(snap)
		text = "none of its recorded reads moved ([jointext(inputs, ", ")]): a read the generated reads do not list"
	else
		text = "no earlier clean check; its reads: [length(inputs) ? jointext(inputs, ", ") : "none recorded"]"
	if(extra)
		text += "; [extra]"
	return text

// ---------------------------------------------------------------- stats

/// TRUE when a cached stat value and a fresh one are the same for every reader. null, "", 0 and FALSE are one value here: a stat var nothing has
/// recomputed yet holds the var's own default, and every reader treats that as the falsy value it composes to. Lists and masks compare by content.
/proc/staleness_stat_equal(cached, fresh)
	if(!islist(cached) && !islist(fresh) && !cached && !fresh)
		return TRUE
	return stat_values_equal(cached, fresh)

/// The inputs of stat `def` on E, as text.
/proc/staleness_stat_inputs(datum/E, datum/stat_def/def, datum/stat_type_info/I)
	. = list()
	if(def.is_formula && istext(def.formula))
		. |= stat_generated_reads(E, def.formula)
		. |= def.formula_reads
	if(I)
		for(var/datum/stat_contrib/C as anything in I.contribs[def.skey])
			if(C.value_kind == CV_VAR && istext(C.value_spec))
				. |= C.value_spec
			else if(C.value_kind == CV_PROC && istext(C.value_spec))
				. |= stat_generated_reads(E, C.value_spec)
			. |= C.reads
	return staleness_input_names(.)

/// TRUE while a stat on E may legitimately differ from its cache: a settle is running, or a marked drain has work queued.
/proc/staleness_stat_pending(datum/E)
	if(GLOB.stat_settle_depth)
		return TRUE
	return length(GLOB.stat_marked) > 0

/// A stat just served from its cache (`cached`): recomputes it from scratch and compares.
/proc/staleness_check_stat(datum/E, datum/stat_def/def, datum/stat_type_info/I, cached, trigger)
	if(!staleness_gate())
		return
	if(QDELING(E))
		return // a hold teardown mid-destroy reads the stat between its releases: teardown, not staleness
	var/datum/stat_record/rec = E.rx?.stats
	if(!rec?.inited)
		return // the map's edits are not captured yet: the var still holds what the map set
	if(staleness_stat_pending(E))
		GLOB.staleness_skipped++
		return
	var/fresh
	var/failed = null
	GLOB.staleness_depth++
	try
		fresh = stat_compute(E, def, I, rec)
	catch(var/exception/fault_stat)
		failed = fault_stat
		GLOB.staleness_skipped++
		log_world("STALENESS|unchecked|stat|[E.type]|[def.name]|[fault_stat.name] at [fault_stat.file]:[fault_stat.line]")
	GLOB.staleness_depth--
	if(failed)
		return
	GLOB.staleness_checks++
	var/snap_key = "[REF(E)]|stat|[def.skey]"
	var/list/inputs
	if(GLOB.staleness_strict)
		inputs = staleness_stat_inputs(E, def, I)
	if(staleness_stat_equal(cached, fresh))
		staleness_snapshot(E, snap_key, inputs)
		return
	var/extra
	var/list/untracked = I?.untracked?[def.skey]
	if(GLOB.staleness_strict && !length(inputs) && (I ? I.has_var[def.skey] : (def.name in E.vars)))
		extra = "the stat var itself holds the cached value and nothing it reads moved: it was written outside the stat layer, or a map edit was not captured"
	if(length(untracked))
		extra = "[extra ? "[extra]; " : ""]the generator lists these inputs as untracked: [jointext(untracked, ", ")]"
	staleness_report("stat", E, def.name, trigger, "[islist(fresh) ? json_encode(fresh) : fresh] against the cached [islist(cached) ? json_encode(cached) : cached]", GLOB.staleness_strict ? staleness_culprit(E, snap_key, inputs, extra) : extra)

/// Every cached stat of E against a fresh computation (the sweep).
/proc/staleness_check_stats(datum/E, trigger)
	var/datum/stat_record/rec = E.rx?.stats
	if(!rec?.inited)
		return
	var/datum/stat_type_info/I = stat_type_of(E)
	if(!I)
		return
	for(var/datum/stat_def/def as anything in I.defs)
		var/has_var = I.has_var[def.skey]
		var/cached
		if(has_var)
			cached = E.vars[def.name]
		else if(!def.keyed && rec.virtual && (def.skey in rec.virtual) && stat_inputs_tracked(I, def))
			cached = rec.virtual[def.skey]
		else
			continue // composed on every read: never cached
		staleness_check_stat(E, def, I, cached, trigger)

// ---------------------------------------------------------------- draws and derive() values

/// The holder vars the draw of A reads, as the build generated them.
/proc/staleness_draw_inputs(atom/A)
	return staleness_input_names(derived_generated_draw_reads(A))

/// A's applied look against a dry draw now. `served` names the vars that were written while the engine said the draw reads none of them.
/// `forced` skips the sampling roll (the entity was already picked).
/proc/staleness_check_draw(atom/A, trigger, list/served, forced = FALSE)
	if(QDELETED(A) || A.refresh_queued)
		return
	if(GLOB.derived_evaluating || GLOB.refresh_running || GLOB.refresh_applying)
		return // a draw is running: the shared look builder is in use
	if(ismovable(A) && !(A.flags & ATOM_MATERIALIZED))
		return
	if(!forced && !staleness_gate())
		return
	if(GLOB.staleness_depth)
		return
	var/flags = type_derive_flags(A)
	if(!(flags & (TYPE_DERIVES_LOOK | TYPE_DERIVES_CAPS | TYPE_DERIVES_PENDING)) && isnull(A.rx?.look_key))
		return // a type known to draw nothing
	var/key
	var/failed = null
	GLOB.staleness_depth++
	try
		key = refresh_look(A, apply = FALSE)
	catch(var/exception/fault_draw)
		failed = fault_draw
		GLOB.staleness_skipped++
		log_world("STALENESS|unchecked|draw|[A.type]|draw|[fault_draw.name] at [fault_draw.file]:[fault_draw.line]")
	GLOB.staleness_depth--
	if(failed)
		return
	GLOB.staleness_checks++
	var/snap_key = "[REF(A)]|draw|draw"
	var/list/inputs
	if(GLOB.staleness_strict)
		inputs = staleness_draw_inputs(A)
	if(key == A.rx?.look_key)
		staleness_snapshot(A, snap_key, inputs)
		return
	var/extra
	if(length(served))
		extra = "written while the dependency graph said the draw reads none of: [jointext(served, ", ")]"
	var/detail = refresh_key_difference(A.rx?.look_key, key)
	staleness_report("draw", A, "draw", trigger, detail, GLOB.staleness_strict ? staleness_culprit(A, snap_key, inputs, extra) : extra)

/// The derive() values of A against a fresh computation.
/proc/staleness_check_derive(atom/A, trigger)
	var/datum/derived_table/T = derived_table_of(A)
	if(!T?.derived_vars || A.refresh_queued)
		return
	if(GLOB.derived_evaluating || GLOB.staleness_depth)
		return
	for(var/datum/derived_var/V as anything in T.derived_vars)
		var/value
		var/failed = null
		GLOB.staleness_depth++
		DERIVED_EVAL_BEGIN
		try
			value = call(A, V.proc_name)()
		catch(var/exception/fault_derive)
			failed = fault_derive
			GLOB.staleness_skipped++
			log_world("STALENESS|unchecked|derive|[A.type]|[V.name]|[fault_derive.name] at [fault_derive.file]:[fault_derive.line]")
		DERIVED_EVAL_END
		GLOB.staleness_depth--
		if(failed)
			continue
		GLOB.staleness_checks++
		if(!staleness_same(value, A.vars[V.name]))
			staleness_report("derive", A, V.name, trigger, "[islist(value) ? json_encode(value) : value] against the cached [islist(A.vars[V.name]) ? json_encode(A.vars[V.name]) : A.vars[V.name]]", "reads: [jointext(V.local_reads, ", ")]")

/// state_changed() wrote `var_name` on E and the dependency graph says no draw reads it: the cached look is served. The next drain checks that.
/proc/staleness_note_served(datum/E, var_name)
	if(!isatom(E))
		return
	var/atom/A = E
	if(isnull(A.rx?.look_key))
		return
	if(!GLOB.staleness_strict && !(GLOB.staleness_sample > 0 && rand(1, GLOB.staleness_sample) == 1))
		return
	var/ref = REF(A)
	var/list/names = GLOB.staleness_served[ref]
	if(!names)
		names = list()
		GLOB.staleness_served[ref] = names
	names |= var_name

/// The look-cache check of one entity: stats, draw, derive().
/proc/staleness_check_entity(datum/D, trigger)
	if(!D || QDELETED(D))
		return
	if(D.rx?.stats)
		staleness_check_stats(D, trigger)
	if(isatom(D) && D.rx?.refresh_swept)
		staleness_check_draw(D, trigger, forced = TRUE)
		staleness_check_derive(D, trigger)

// ---------------------------------------------------------------- keyed images

/// A keyed shared image just served from its cache: rebuilt and compared. `rebuilt` is the builder's result for the same arguments.
/proc/staleness_check_image(key, image/cached, image/rebuilt)
	if(!cached || !rebuilt)
		return
	GLOB.staleness_checks++
	if(cached.appearance == rebuilt.appearance)
		return
	staleness_report("image", null, "[key]", "look_cached_image", "an image that differs from the cached one", "the key does not name everything that varies the image (icon, state, tint, plane, layer)")

// ---------------------------------------------------------------- the sweep

/// Checks one entity by ref text, dropping a ref that no longer names it.
/proc/staleness_check_ref(ref, trigger)
	var/datum/D = locate(ref)
	if(!D || QDELETED(D) || REF(D) != ref)
		GLOB.stale_all -= ref
		GLOB.staleness_served -= ref
		return FALSE
	staleness_check_entity(D, trigger)
	return TRUE

/// Brings the pending work to the state the next frame would: queued redraws run, marked stats drain. Used before a sweep so a value that is
/// only waiting for its drain is not reported.
/proc/staleness_settle()
	if(length(GLOB.refresh_queue))
		refresh_flush()
	if(length(GLOB.stat_marked))
		stat_drain_point()

/// Checks the entities that appeared since the last sweep, every one that noted a served draw, and `old_budget` of the rest. Returns the reports it filed.
/proc/staleness_sweep(trigger, settle = FALSE, old_budget = STALENESS_TEST_END_OLD)
	if(!GLOB.staleness_on || GLOB.staleness_depth)
		return 0
	if(settle)
		staleness_settle()
	var/before = GLOB.staleness_found
	var/list/served = GLOB.staleness_served
	GLOB.staleness_served = list()
	for(var/ref in served)
		var/datum/D = locate(ref)
		if(isatom(D) && REF(D) == ref)
			staleness_check_draw(D, trigger, served[ref], forced = TRUE)
	var/list/fresh = GLOB.stale_new
	GLOB.stale_new = list()
	for(var/ref in fresh)
		staleness_check_ref(ref, trigger)
	staleness_sweep_older(trigger, old_budget)
	return GLOB.staleness_found - before

/// `budget` entities from the rotating cursor over everything the sweep walks.
/proc/staleness_sweep_older(trigger, budget)
	var/list/all = GLOB.stale_all
	while(budget > 0 && length(all))
		budget--
		if(GLOB.stale_cursor > length(all))
			GLOB.stale_cursor = 1
		var/ref = all[GLOB.stale_cursor]
		if(staleness_check_ref(ref, trigger))
			GLOB.stale_cursor++

/// One presentation drain's share (appearance_drain()): the served draws noted since the last drain, then a slice of the rest. Sampled mode checks one
/// entity in N per drain.
/proc/staleness_drain_step()
	if(!GLOB.staleness_on)
		return
	if(GLOB.staleness_strict)
		staleness_sweep("presentation drain", old_budget = STALENESS_SWEEP_BUDGET)
		return
	var/list/served = GLOB.staleness_served
	GLOB.staleness_served = list()
	for(var/ref in served)
		var/datum/D = locate(ref)
		if(isatom(D) && REF(D) == ref)
			staleness_check_draw(D, "presentation drain", served[ref], forced = TRUE)
	if(length(GLOB.stale_all) && GLOB.staleness_sample > 0 && rand(1, GLOB.staleness_sample) == 1)
		staleness_check_ref(GLOB.stale_all[rand(1, length(GLOB.stale_all))], "presentation drain (sampled)")

/// The end of a test: queued work settles, then everything that appeared during the test and a slice of the rest is checked, against the test's own
/// result (a report fails it). The expectation flag is the test's own and ends with it.
/proc/staleness_test_end(test)
	if(!GLOB.staleness_strict)
		return
	var/found = staleness_sweep("end of test", settle = TRUE)
	if(found)
		log_world("STALENESS: [found] stale after [test]")
	GLOB.staleness_expected = FALSE
