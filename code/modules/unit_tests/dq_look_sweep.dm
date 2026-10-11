/**
 * The look sweep: one pass over every creatable type that writes both the look tree pins and the look state pins.
 *
 * Look tree pins (code/modules/unit_tests/snapshots/look_trees/<root>.txt, test dq_look_tree_pin): the look of every creatable
 * subtype under a root, each row prefixed with its type. Abstract types and the unit tests' uncreatables are left out; a turf
 * type is made by turning the tile east of the test floor into it (and back); areas are not made.
 *
 * Look state pins (snapshots/look_states/<root>.txt, test dq_look_state_pin): how each creatable obj/mob subtype of a root looks
 * after the state its look reacts to changes. Per type, for each numeric var the type declares below its base (/obj or /mob; at
 * most DQ_LOOK_STATE_MAX_VARS of them, in declaration order, narrowed to the vars the analyzer's plan says a draw can read), the
 * var is written (0, 1 and 2, whichever differ from its made value; through its tracked setter when it has one, else the raw
 * var), a redraw is requested the way a caller does (update_icon(), then changed()), the presentation lane is flushed and the
 * look is compared with the made look. A row is the probe and what the look gained or lost:
 *
 *   <type> <var>=<n> +overlay: ...        <type> <var>=<n> -state: ...        <type> <var>=<n> runtime: <message>
 *
 * A probe that changes nothing writes no row. The rows are the look a conversion must keep: the same file before and after.
 *
 * One instance per type: the made thing is the tree row's subject and the state pins' base. Each probe writes the var, redraws,
 * captures, writes the original value back, redraws and checks the look came back to the made one. A draw is a function of the
 * state, so that is enough; when it is not (the look did not return, or a probe ran into a runtime) the type is listed under
 * "look sweep IMPURE" in the test log and its remaining probes use a fresh instance each, as the pin did before.
 *
 * Every unit (a type) starts from the same world: the block is emptied, its air and walls restored, the RNG reseeded from the
 * type's path and the presentation lane settled, so the rows do not depend on the order the types are made in.
 *
 * Test-only world params (set by tools/dq_focused_test.sh):
 *   look-plan=<file>    the analyzer's `look-keys` output (type TAB key TAB probes): narrows the var scan per type
 *   look-types=<file>   probe only these types (the incremental run: types whose key changed); one per line
 *   look-order=reverse | shuffle:<n>   the order the owned types are probed in (the determinism proof: the rows must not move)
 *   look-dump=<dir>     write the rows this run produced, sorted, under <dir>/look_trees and <dir>/look_states
 *   look-fresh=1        a fresh instance for every probe (how the pin probed before; the measuring baseline)
 *   look-trace=1        log every global scalar and list length a unit changed ("LOOK LEAK")
 * A sharded world (shard-index/shard-count params) probes the types whose index in the sorted list of all of them it owns
 * (sweep_owns) and compares only those; bless, and a new empty pin file, need an unsharded full run.
 */
#define DQ_LOOK_TREE_DIR "code/modules/unit_tests/snapshots/look_trees/"
#define DQ_LOOK_STATE_DIR "code/modules/unit_tests/snapshots/look_states/"
#define DQ_LOOK_STATE_MAX_VARS 24
/// Deadline passes a settle runs: work that queues more zero-delay work (a timer that arms a timer) needs the next one.
#define DQ_LOOK_SETTLE_PASSES 3

/// One type's results: the made look, the state probe rows, and what was done.
/datum/dq_look_result
	/// The look rows of the made thing (the tree pin's rows without their type prefix).
	var/list/made
	/// The state pin's rows for the type, type prefixed.
	var/list/probe_rows = list()
	/// Probes whose write-back did not return the look to the made one.
	var/list/impure = list()
	var/tree_done = FALSE
	var/state_done = FALSE

/// type => /datum/dq_look_result, for the types this world has swept. Filled by dq_look_sweep().
GLOBAL_LIST_EMPTY(dq_look_results)

/datum/unit_test/dq_look_tree_pin
	tier = TEST_TIER_EXHAUSTIVE
	timeout = 3600
	is_sweep_test = TRUE

/datum/unit_test/dq_look_tree_pin/Run()
	var/list/bad = list()
	var/list/expected_by_root = dq_snapshot_read_dir(DQ_LOOK_TREE_DIR, bad)
	if(!length(expected_by_root) && !length(bad))
		return
	dq_look_sweep(src, TRUE, !!(/datum/unit_test/dq_look_state_pin in GLOB.focused_tests) || !length(GLOB.focused_tests))
	TEST_ASSERT(isnull(dq_look_sweep_compare(DQ_LOOK_TREE_DIR, "look_trees", expected_by_root, bad, TRUE)), dq_look_report)

/datum/unit_test/dq_look_state_pin
	tier = TEST_TIER_EXHAUSTIVE
	timeout = 3600
	is_sweep_test = TRUE

/datum/unit_test/dq_look_state_pin/Run()
	var/list/bad = list()
	var/list/expected_by_root = dq_snapshot_read_dir(DQ_LOOK_STATE_DIR, bad)
	if(!length(expected_by_root) && !length(bad))
		return
	dq_look_sweep(src, !!(/datum/unit_test/dq_look_tree_pin in GLOB.focused_tests) || !length(GLOB.focused_tests), TRUE)
	TEST_ASSERT(isnull(dq_look_sweep_compare(DQ_LOOK_STATE_DIR, "look_states", expected_by_root, bad, FALSE)), dq_look_report)

/// The last compare's failure text (TEST_ASSERT wants the message after the condition).
/datum/unit_test/var/dq_look_report

// ---- eligibility ----

/// Whether the tree pin makes `type`.
/datum/unit_test/proc/dq_look_tree_eligible(type)
	if(!ispath(type, /obj) && !ispath(type, /mob) && !ispath(type, /turf))
		return FALSE
	return !is_abstract(type) && !(type in uncreatables)

/// Whether the state pin probes `type`.
/datum/unit_test/proc/dq_look_state_eligible(type)
	if(!ispath(type, /obj) && !ispath(type, /mob))
		return FALSE
	return !is_abstract(type) && !(type in uncreatables)

// ---- world params ----

/// The lines of the file a look-* world param names (CR dropped, blanks skipped); null when the param is absent or the file is.
/proc/dq_look_param_lines(param)
	var/file = world.params?[param]
	if(!file || !fexists(file))
		return null
	. = list()
	for(var/line in splittext(file2text(file), "\n"))
		line = replacetext(line, ascii2text(13), "")
		if(length(line))
			. += line

/// The analyzer plan: "[type]" => list(var names) or "*" (unknown: scan every numeric var).
/proc/dq_look_read_plan()
	var/list/lines = dq_look_param_lines("look-plan")
	if(!lines)
		return null
	. = list()
	for(var/line in lines)
		var/list/parts = splittext(line, "\t")
		if(length(parts) < 3)
			continue
		.[parts[1]] = parts[3] == "*" ? "*" : splittext(parts[3], ",")

/// `units` in the order the look-order param asks for (the determinism proof); unchanged without it. The shuffle is a small
/// linear congruential generator so it never touches the world RNG and gives the same order on every machine.
/proc/dq_look_order(list/units)
	var/mode = world.params?["look-order"]
	if(!mode)
		return units
	var/list/out = units.Copy()
	if(mode == "reverse")
		for(var/i in 1 to length(out) / 2)
			out.Swap(i, length(out) + 1 - i)
		return out
	var/state = text2num(copytext(mode, 9)) || 1
	for(var/i in length(out) to 2 step -1)
		state = (state * 75 + 74) % 65537
		out.Swap(1 + (state % i), i)
	return out


/// Constructors may change round counters and lazily populate clothing caches.
/// Snapshot each real prior value and give list caches a private copy, so both
/// null caches and already-populated cache identities survive fixture teardown.
/datum/unit_test/proc/dq_look_scope_globals()
	set_global(nameof(GLOB.narsie_cometh), GLOB.narsie_cometh)
	set_global(nameof(GLOB.queen_amount), GLOB.queen_amount)
	set_global(nameof(GLOB.round_seed), GLOB.round_seed)
	set_global(nameof(GLOB.roll_serial), GLOB.roll_serial)
	var/static/list/cache_keys = list(nameof(GLOB.status_policies), nameof(GLOB.chamelion_jumpsuit_choices), nameof(GLOB.chamelion_head_choices), nameof(GLOB.chamelion_suit_choices), nameof(GLOB.chamelion_shoe_choices), nameof(GLOB.chamelion_back_choices), nameof(GLOB.chamelion_glove_choices), nameof(GLOB.chamelion_mask_choices), nameof(GLOB.chamelion_belt_choices), nameof(GLOB.chamelion_accessory_choices))
	for(var/key in cache_keys)
		var/list/prior = GLOB.vars[key]
		set_global(key, islist(prior) ? prior.Copy() : prior)
	// These are owned catalogue templates, not allocate() children. Their real
	// teardown removes the every(host) watches; borrowed catalogue entries survive.
	scope_contagion_archive()

/datum/unit_test/dq_look_scope_probe
	abstract_type = /datum/unit_test/dq_look_scope_probe

/datum/unit_test/dq_look_sweep_scope_restores_globals/Run()
	var/list/existing = list("Existing choice" = /obj/item/clothing/under)
	set_global(nameof(GLOB.chamelion_jumpsuit_choices), existing)
	set_global(nameof(GLOB.chamelion_head_choices), null)
	set_global(nameof(GLOB.status_policies), null)
	var/narsie_before = GLOB.narsie_cometh
	var/queens_before = GLOB.queen_amount
	var/seed_before = GLOB.round_seed
	var/serial_before = GLOB.roll_serial
	var/list/archive_before = GLOB.archive_diseases
	var/datum/unit_test/dq_look_scope_probe/probe = allocate(/datum/unit_test/dq_look_scope_probe)
	var/datum/unit_test_block/block = probe.test_block
	defer_cleanup(src, PROC_REF(release_look_scope_probe), probe, block)
	probe.dq_look_scope_globals()
	var/list/populated_status = status_policies()
	TEST_ASSERT(length(populated_status), "Real lazy status policy lookup populates the scoped initially null cache")
	TEST_ASSERT(GLOB.chamelion_jumpsuit_choices != existing, "Existing choice cache is isolated before an in-place probe write")
	GLOB.chamelion_jumpsuit_choices["Added choice"] = /obj/item/clothing/head
	GLOB.chamelion_head_choices = list("Generated choice" = /obj/item/clothing/head)
	GLOB.narsie_cometh = !narsie_before
	GLOB.queen_amount = queens_before + 1
	rolls_fix_seed(seed_before + 1)
	GLOB.roll_serial = serial_before + 1
	TEST_ASSERT_EQUAL(length(existing), 1, "The borrowed cache contents never receive the scoped addition")
	TEST_ASSERT(GLOB.archive_diseases != archive_before, "Archive scope uses a private catalogue while borrowing existing templates")
	lifeform_end(probe, END_SCOPE)
	TEST_ASSERT_EQUAL(GLOB.chamelion_jumpsuit_choices, existing, "Real fixture teardown restores the exact existing cache identity")
	TEST_ASSERT_EQUAL(length(existing), 1, "Restored cache retains its original contents")
	TEST_ASSERT_NULL(GLOB.chamelion_head_choices, "Real teardown restores an originally null lazy cache")
	TEST_ASSERT_EQUAL(GLOB.narsie_cometh, narsie_before, "Real teardown restores the apocalypse counter")
	TEST_ASSERT_EQUAL(GLOB.queen_amount, queens_before, "Real teardown restores the queen count")
	TEST_ASSERT_EQUAL(GLOB.round_seed, seed_before, "Real teardown restores the exact native round seed")
	TEST_ASSERT_EQUAL(GLOB.roll_serial, serial_before, "Real teardown restores the exact native roll serial")
	TEST_ASSERT_EQUAL(GLOB.archive_diseases, archive_before, "Real teardown restores the borrowed archive identity")
	TEST_ASSERT_NULL(GLOB.status_policies, "Real sweep teardown restores the originally null status cache")
	// A pre-existing policy table is borrowed: scoped list edits must not touch it.
	set_global(nameof(GLOB.status_policies), populated_status)
	var/status_key = populated_status[1]
	var/status_policy_before = populated_status[status_key]
	var/status_count_before = length(populated_status)
	var/datum/unit_test/dq_look_scope_probe/second = allocate(/datum/unit_test/dq_look_scope_probe)
	defer_cleanup(src, PROC_REF(release_look_scope_probe), second, second.test_block)
	second.dq_look_scope_globals()
	TEST_ASSERT(GLOB.status_policies != populated_status, "Real scope isolates an already populated status table")
	GLOB.status_policies.Remove(status_key)
	TEST_ASSERT_EQUAL(length(populated_status), status_count_before, "Borrowed policy table retains its entry during scoped cache mutation")
	lifeform_end(second, END_SCOPE)
	TEST_ASSERT_EQUAL(GLOB.status_policies, populated_status, "Real teardown restores exact prior status cache identity")
	TEST_ASSERT_EQUAL(GLOB.status_policies[status_key], status_policy_before, "Restored table preserves the actual prior policy datum")


/datum/unit_test/dq_look_sweep_scope_restores_globals/proc/release_look_scope_probe(datum/unit_test/probe, datum/unit_test_block/block)
	if(!QDELETED(probe))
		lifeform_end(probe, END_SCOPE)
	var/reason = release_unit_test_block(block, probe)
	if(reason)
		Fail(reason)

// ---- the sweep ----

/// The sweep's partial flag: this world probes only some of the types (a shard, or the incremental list).
/proc/dq_look_sweep_partial()
	return GLOB.dq_test_shard_count > 1 || !isnull(world.params?["look-types"])

/**
 * Probes every type this world owns, once per world: `want_tree` and `want_state` say which results are needed (a pin that runs
 * beside the other asks for both, so each type is made once). A later call for a result the first one skipped probes only that.
 */
/datum/unit_test/proc/dq_look_sweep(datum/unit_test/owner, want_tree, want_state)
	owner.dq_look_scope_globals() // constructors and state probes may populate shared caches or archive owned disease templates
	var/list/universe = dq_look_universe(want_tree, want_state)
	var/list/plan = dq_look_read_plan()
	var/list/recorded = want_state ? dq_look_recorded_probe_names() : null
	var/list/only = dq_look_param_lines("look-types")
	var/list/only_set
	if(only)
		only_set = list()
		for(var/line in only)
			only_set[line] = TRUE
	var/list/work = list()
	var/index = 0
	for(var/type in universe)
		if(owner.sweep_owns(index) && (!only_set || only_set["[type]"]))
			work += type
		index++
	work = dq_look_order(work)
	var/turf/T = test_floor()
	var/list/base_vars_obj = dq_look_state_base_vars(/obj, T)
	var/list/base_vars_mob = dq_look_state_base_vars(/mob, T)
	var/trace = world.params?["look-trace"] == "1"
	var/fresh = world.params?["look-fresh"] == "1"
	log_test("look sweep: [length(work)] of [length(universe)] types in this world (shard [GLOB.dq_test_shard_index + 1]/[GLOB.dq_test_shard_count], order [world.params?["look-order"] || "path"], plan [isnull(plan) ? "none" : length(plan)])")
	for(var/type in work)
		var/datum/dq_look_result/res = GLOB.dq_look_results["[type]"]
		var/need_tree = want_tree && dq_look_tree_eligible(type) && !res?.tree_done
		var/need_state = want_state && dq_look_state_eligible(type) && !res?.state_done
		if(!need_tree && !need_state)
			continue
		if(!res)
			res = new
			GLOB.dq_look_results["[type]"] = res
		var/list/before
		if(trace)
			before = dq_look_globals_snapshot()
		if(ispath(type, /turf))
			dq_look_unit_turf(type, T, res)
		else
			dq_look_unit(type, T, ispath(type, /obj) ? base_vars_obj : base_vars_mob, plan, res, need_tree, need_state, fresh, recorded?["[type]"])
		if(trace)
			dq_look_globals_report(type, before)
	dq_look_reset(T) // the block is released clean: nothing of the last type is left on it

/// Every type either wanted pin makes, in the one order every shard agrees on (the sorted path text).
/datum/unit_test/proc/dq_look_universe(want_tree, want_state)
	var/list/seen = list()
	if(want_tree)
		var/list/bad = list()
		for(var/root in dq_snapshot_read_dir(DQ_LOOK_TREE_DIR, bad))
			for(var/type in typesof(root))
				if(dq_look_tree_eligible(type))
					seen["[type]"] = type
	if(want_state)
		var/list/bad = list()
		for(var/root in dq_snapshot_read_dir(DQ_LOOK_STATE_DIR, bad))
			for(var/type in typesof(root))
				if(dq_look_state_eligible(type))
					seen["[type]"] = type
	var/list/names = list()
	for(var/name in seen)
		names += name
	sortTim(names, GLOBAL_PROC_REF(cmp_text_asc))
	. = list()
	for(var/name in names)
		. += seen[name]

/**
 * Lets the work that is already owed run, the same way every time: the kernel stands on its injected clock (nothing live runs,
 * nothing periodic comes due), and its deadline phase runs the zero-delay work the last step queued (an after(0), a notice
 * handler, a refresh) until none is left. Without it a draw sees whatever happened to run since the thing was made: a shuttle
 * floor's underlay (what it landed on is recorded by an after(0) the tick that follows a turf change runs) depended on whether a
 * tick had passed, that is, on which type was made before it.
 */
/datum/unit_test/proc/dq_look_settle()
	kernel_test_begin() // idempotent: the clock is frozen for the rest of the test and handed back by end_test_world()
	for(var/pass in 1 to DQ_LOOK_SETTLE_PASSES)
		kernel_phase_run(KERNEL_PHASE_D)
	kernel_drain_now()

/// Puts the block back to the state every unit starts from: nothing but the landmarks on it, the template's air and floors, the
/// presentation lane and the stat drain settled. A thing left from the last unit, a mob that wandered off the tile or air a probe
/// heated would otherwise be in the next unit's look.
/datum/unit_test/proc/dq_look_reset(turf/T)
	for(var/turf/B as anything in block_turfs(test_block))
		dq_look_drain_turf(B)
		unit_test_block_reset_turf(B)
	dq_look_settle()

/// The var names of the base type `base`: what a probe leaves alone.
/datum/unit_test/proc/dq_look_state_base_vars(base, turf/T)
	rolls_fix_seed(dq_test_seed_for("[base]"))
	var/atom/A = allocate(base, T)
	. = list()
	for(var/name in A.vars)
		. += name
	qdel(A)
	own_turf_contents(T)

/// One turf type: `spot` east of the test floor is turned into it, drawn and turned back.
/datum/unit_test/proc/dq_look_unit_turf(type, turf/T, datum/dq_look_result/res)
	dq_look_reset(T)
	res.made = dq_look_capture_turf(type, get_step(T, EAST))
	res.tree_done = TRUE
	res.state_done = TRUE

/// A turf type: `spot` is turned into it, settled, drawn and turned back (and settled again, so the next unit starts from a
/// finished floor). The made turf is the look; the RNG is reseeded from the path.
/datum/unit_test/proc/dq_look_capture_turf(type, turf/spot)
	var/old_type = spot.type
	log_test("look pin: making [type]")
	rand_seed(dq_test_seed_for("[type]"))
	try
		rolls_fix_seed(dq_test_seed_for("[type]"))
		var/turf/made = spot.ChangeTurf(type)
		if(QDELETED(made))
			. = list("deleted itself on creation")
		else
			dq_look_settle() // the on_change reactions (a floor's edges follow the flooring it was laid with) and the after(0) work of the change run before it draws
			. = dq_look_pin_lines(made)
	catch(var/exception/e)
		. = list("runtime: [dq_look_state_error(e)]")
	var/turf/restored = locate(spot.x, spot.y, spot.z)
	rolls_fix_seed(dq_test_seed_for("[old_type]"))
	restored.ChangeTurf(old_type)
	dq_look_settle()

/**
 * One obj/mob type: made once on the test floor (the RNG reseeded from its path); its look is the tree row set and the state
 * pins' base; then the probes (see the file comment).
 */
/datum/unit_test/proc/dq_look_unit(type, turf/T, list/base_vars, list/plan, datum/dq_look_result/res, need_tree, need_state, force_fresh = FALSE, list/recorded_names = null)
	dq_look_reset(T)
	log_test("look pin: making [type]") // a type that hangs names itself in the log
	rand_seed(dq_test_seed_for("[type]"))
	var/atom/subject
	var/list/names = list()
	var/runtime
	try
		rolls_fix_seed(dq_test_seed_for("[type]"))
		subject = dq_snapshot_allocate(type, T)
		if(QDELETED(subject))
			res.made = list("deleted itself on creation")
		else
			dq_look_settle()
			res.made = dq_look_pin_lines(subject)
			if(need_state)
				names = dq_look_probe_names(subject, base_vars, plan?["[type]"], recorded_names)
	catch(var/exception/e)
		runtime = dq_look_state_error(e)
		res.made = list("runtime: [runtime]")
	if(need_tree)
		res.tree_done = TRUE
	if(!need_state)
		if(subject && !QDELETED(subject))
			qdel(subject)
		dq_look_drain_turf(T)
		return
	res.state_done = TRUE
	if(runtime)
		res.probe_rows += "[type] runtime: [runtime]"
		dq_look_drain_turf(T)
		return
	if(QDELETED(subject))
		dq_look_drain_turf(T)
		return
	var/list/base = res.made
	var/reuse = !force_fresh
	if(!reuse)
		qdel(subject) // fresh probes make their own: a second table on the tile does not flip
		dq_look_drain_turf(T)
	for(var/name in names)
		for(var/value in list(0, 1, 2))
			if(reuse && !QDELETED(subject))
				if(!dq_look_probe_reuse(subject, type, name, value, base, res))
					reuse = FALSE
					if(!QDELETED(subject))
						qdel(subject)
					dq_look_drain_turf(T)
			else
				res.probe_rows += dq_look_state_probe(type, T, name, value, base)
	if(subject && !QDELETED(subject))
		qdel(subject)
	dq_look_drain_turf(T)

/// Only names are recovered from prior rows; appearance payloads remain expectations, never new results.
/datum/unit_test/proc/dq_look_recorded_probe_names(list/expected)
	if(isnull(expected))
		var/list/bad = list()
		expected = dq_snapshot_read_dir(DQ_LOOK_STATE_DIR, bad)
		for(var/problem in bad)
			Fail("LOOK COVERAGE: cannot read prior state rows: [problem]")
	. = list()
	for(var/root in expected)
		for(var/row in expected[root])
			var/space = findtext(row, " ")
			var/equal = findtext(row, "=", space + 1)
			if(!space || !equal || findtext(copytext(row, space + 1, equal), " "))
				continue // made/runtime rows have no numeric probe assignment
			var/type_name = copytext(row, 1, space)
			var/field = copytext(row, space + 1, equal)
			var/list/names = .[type_name]
			if(!names)
				names = list()
				.[type_name] = names
			if(!(field in names))
				names += field

/// Restore-required coverage must name a real numeric field with the actual existing write path.
/datum/unit_test/proc/dq_look_recorded_probe_problem(atom/subject, name)
	if(!(name in subject.vars))
		return "recorded field [name] no longer exists on [subject.type]; migrate its real probe adapter or document its retirement"
	if(!isnum(subject.vars[name]))
		return "recorded field [name] is no longer numeric on [subject.type]; migrate its real probe adapter or document its retirement"
	try
		// This tests writability without choosing a new value; existing tracked setters still own writes.
		dq_look_write(subject, name, subject.vars[name])
	catch(var/exception/e)
		return "recorded field [name] cannot use its real write path on [subject.type]: [dq_look_state_error(e)]"
	return null

/// The numeric vars of `subject` worth writing: those it declares below its base, without time-like names, in declaration order, at
/// most DQ_LOOK_STATE_MAX_VARS of them. A concrete read plan filters candidates before that limit.
/datum/unit_test/proc/dq_look_probe_names(atom/subject, list/base_vars, plan_entry, list/recorded_names = null)
	var/list/found = list()
	if(plan_entry == "*" && length(recorded_names))
		if(length(recorded_names) > DQ_LOOK_STATE_MAX_VARS)
			Fail("LOOK COVERAGE: [subject.type] has [length(recorded_names)] required historical fields, exceeding the existing [DQ_LOOK_STATE_MAX_VARS] budget; none may be silently truncated")
			return found
		for(var/name in recorded_names)
			var/problem = dq_look_recorded_probe_problem(subject, name)
			if(problem)
				Fail("LOOK COVERAGE: [problem]")
				continue
			found += name
	for(var/name in subject.vars)
		if(name in base_vars || name in found)
			continue
		if(islist(plan_entry) && !(name in plan_entry))
			continue
		if(isnum(subject.vars[name]) && !findtext(name, "time") && !findtext(name, "cooldown") && !findtext(name, "last") && !findtext(name, "next"))
			found += name
	if(length(found) > DQ_LOOK_STATE_MAX_VARS)
		found.Cut(DQ_LOOK_STATE_MAX_VARS + 1)
	return found

/// Writes `value` to `target.vars[name]` the way a caller does (its tracked setter when it has one, else the raw var) and redraws.
/datum/unit_test/proc/dq_look_write(atom/target, name, value)
	var/setter = "set_[name]"
	if(hascall(target, setter))
		call(target, setter)(value)
	else
		target.vars[name] = value
	target.update_icon()
	changed(target)
	dq_look_settle()

/// One probe on the made instance: write, capture, write the original back, check the look returned to `base`. Returns FALSE when
/// the instance can no longer be trusted (a runtime, or the look did not come back); the rows it wrote stay.
/datum/unit_test/proc/dq_look_probe_reuse(atom/subject, type, name, value, list/base, datum/dq_look_result/res)
	rand_seed(dq_test_seed_for("[type]/[name]=[value]"))
	var/original = subject.vars[name]
	if(original == value)
		return TRUE
	try
		dq_look_write(subject, name, value)
		var/list/now = dq_look_pin_lines(subject)
		for(var/row in now - base)
			res.probe_rows += "[type] [name]=[value] +[row]"
		for(var/row in base - now)
			res.probe_rows += "[type] [name]=[value] -[row]"
		dq_look_write(subject, name, original)
		var/list/back = dq_look_pin_lines(subject)
		if(jointext(back, "\n") != jointext(base, "\n"))
			res.impure += "[type] [name]=[value] (back to [original]): [length(back - base)] rows gained, [length(base - back)] lost"
			log_test("look sweep IMPURE: [type] [name]=[value]: writing [original] back did not return the look to the made one; the rest of its probes use fresh instances")
			return FALSE
	catch(var/exception/e)
		res.probe_rows += "[type] [name]=[value] runtime: [dq_look_state_error(e)]"
		return FALSE
	return TRUE

/// One probe on a fresh instance (the way the pin always probed): a fresh `type` with `name` written to `value`, redrawn, against the
/// made look `base`; rows only for a difference.
/datum/unit_test/proc/dq_look_state_probe(type, turf/T, name, value, list/base)
	. = list()
	rand_seed(dq_test_seed_for("[type]/[name]=[value]"))
	try
		// Native initialization is identical to the made/reused instance; the
		// BYOND mutation seed above still belongs to this individual probe.
		rolls_fix_seed(dq_test_seed_for("[type]"))
		var/atom/target = dq_snapshot_allocate(type, T)
		if(QDELETED(target))
			return
		dq_look_settle()
		if(target.vars[name] == value)
			qdel(target)
			dq_look_drain_turf(T)
			return
		dq_look_write(target, name, value)
		var/list/now = dq_look_pin_lines(target)
		for(var/row in now - base)
			. += "[type] [name]=[value] +[row]"
		for(var/row in base - now)
			. += "[type] [name]=[value] -[row]"
		qdel(target)
	catch(var/exception/e)
		. += "[type] [name]=[value] runtime: [dq_look_state_error(e)]"
	// A probe leaves nothing behind: what its thing spilled when it was deleted (a core's chunk, a cabinet's guns, a worm's dead
	// heads) would otherwise be there for every later probe, and a closet takes all of it in each time it is made.
	dq_look_drain_turf(T)

/proc/dq_look_state_error(exception/e)
	var/static/regex/where = regex(@"^\S+\.dm:\d+:")
	return where.Replace(e.name, "")

// ---- comparing ----

/**
 * Compares one pin directory with the sweep's rows: null when they match (or when this run blesses, after writing them), else the
 * failure text (also in dq_look_report). Only the types this world probed are compared: a shard's slice, or the
 * incremental run's list. `tree` picks the row set.
 */
/datum/unit_test/proc/dq_look_sweep_compare(dir, name, list/expected_by_root, list/bad, tree)
	dq_look_report = null
	var/partial = dq_look_sweep_partial()
	if(partial)
		if(dq_snapshot_blessing())
			dq_look_report = "a sharded or incremental look sweep cannot bless: run it unsharded and full (tools/dq_focused_test.sh --bless does)"
			return dq_look_report
	var/list/actual_by_root = list()
	var/list/expected_kept = list()
	for(var/root in expected_by_root)
		var/list/rows = list()
		var/list/covered = list()
		for(var/type in typesof(root))
			var/datum/dq_look_result/res = GLOB.dq_look_results["[type]"]
			if(!res)
				continue
			if(tree)
				if(!res.tree_done)
					continue
				covered["[type]"] = TRUE
				for(var/line in res.made)
					rows += "[type] [line]"
			else
				if(!res.state_done)
					continue
				covered["[type]"] = TRUE
				rows += res.probe_rows
		actual_by_root[root] = rows
		// A recorded row of a type that exists but was not probed here is another shard's (or an unchanged type's): not this run's to judge.
		var/list/keep = list()
		for(var/row in expected_by_root[root])
			var/row_type = copytext(row, 1, findtext(row, " "))
			if(covered[row_type])
				keep += row
				continue
			var/type_path = text2path(row_type)
			if(partial && type_path && (tree ? dq_look_tree_eligible(type_path) : dq_look_state_eligible(type_path)))
				continue
			if(partial && GLOB.dq_test_shard_index != 0)
				continue // a row of a type that is gone: shard one reports it, the others stay quiet
			keep += row
		expected_kept[root] = keep
	dq_look_sweep_dump(name, actual_by_root)
	var/list/unrecorded = list()
	if(partial)
		// An empty file is a root with no rows, or a new pin that is not recorded yet; a partial run cannot tell which, nor write the file.
		for(var/root in expected_by_root)
			if(!length(expected_by_root[root]) && length(actual_by_root[root]))
				unrecorded += "[dir][root] has no rows recorded but the sweep produced [length(actual_by_root[root])] (a new pin? record it with an unsharded full run: tools/dq_pin.sh)"
				actual_by_root -= root
				expected_kept -= root
	var/report_name = GLOB.dq_test_shard_count > 1 ? "[name]/shard[GLOB.dq_test_shard_index]" : name
	dq_look_report = dq_snapshot_compare(dir, report_name, actual_by_root, expected_kept, bad)
	if(length(unrecorded))
		dq_look_report = "[dq_look_report ? "[dq_look_report]\n" : ""][jointext(unrecorded, "\n")]"
	return dq_look_report

/// look-dump=<dir>: the rows this world produced, sorted, one file per root, plus the md5 of each in the log.
/datum/unit_test/proc/dq_look_sweep_dump(name, list/actual_by_root)
	var/dir = world.params?["look-dump"]
	if(!dir)
		return
	for(var/root in actual_by_root)
		var/list/rows = actual_by_root[root]
		var/list/sorted = rows.Copy()
		sortTim(sorted, GLOBAL_PROC_REF(cmp_text_asc))
		var/text = length(sorted) ? "[jointext(sorted, "\n")]\n" : ""
		var/file_name = "[dir]/shard[GLOB.dq_test_shard_index]/[name]/[replacetext(copytext("[root]", 2), "/", ".")].txt"
		fdel(file_name)
		text2file(text, file_name)
		log_test("look dump: [name] [root] [length(sorted)] rows md5 [md5(text)]")
	var/list/impure = list()
	for(var/type in GLOB.dq_look_results)
		var/datum/dq_look_result/res = GLOB.dq_look_results[type]
		impure += res.impure
	if(length(impure))
		sortTim(impure, GLOBAL_PROC_REF(cmp_text_asc))
		var/impure_file = "[dir]/impure.[GLOB.dq_test_shard_index].txt"
		fdel(impure_file)
		text2file("[jointext(impure, "\n")]\n", impure_file)

// ---- leak tracing ----

/// The scalar GLOB vars and the length of the list ones: what look-trace compares around a unit.
/proc/dq_look_globals_snapshot()
	. = list()
	var/list/ignored = unit_test_globals_ignored()
	for(var/name in GLOB.vars)
		if(ignored[name])
			continue
		var/value = GLOB.vars[name]
		if(islist(value))
			.[name] = length(value)
		else if(isnull(value) || isnum(value) || istext(value) || ispath(value))
			.[name] = value

/// Logs each global a unit changed ("LOOK LEAK"): a registry that grew, a flag that flipped, a counter that moved.
/proc/dq_look_globals_report(type, list/before)
	var/list/after = dq_look_globals_snapshot()
	for(var/name in after)
		if(!(name in before))
			continue
		if(before[name] != after[name])
			log_test("LOOK LEAK: [type] changed GLOB.[name]: [before[name]] -> [after[name]]")


// An actual subtype with more early unread numeric fields than the fallback limit.
/obj/dq_look_late_dependency
	abstract_type = /obj/dq_look_late_dependency
	var/unread_01 = 0
	var/unread_02 = 0
	var/unread_03 = 0
	var/unread_04 = 0
	var/unread_05 = 0
	var/unread_06 = 0
	var/unread_07 = 0
	var/unread_08 = 0
	var/unread_09 = 0
	var/unread_10 = 0
	var/unread_11 = 0
	var/unread_12 = 0
	var/unread_13 = 0
	var/unread_14 = 0
	var/unread_15 = 0
	var/unread_16 = 0
	var/unread_17 = 0
	var/unread_18 = 0
	var/unread_19 = 0
	var/unread_20 = 0
	var/unread_21 = 0
	var/unread_22 = 0
	var/unread_23 = 0
	var/unread_24 = 0
	var/unread_25 = 0
	var/late_read = 0

TRACKED(/obj/dq_look_late_dependency, late_read)
/obj/dq_look_late_dependency/draw(datum/look/look)
	..()
	look.state("late-[late_read]")


/datum/unit_test/dq_look_sweep_plan_before_limit/Run()
	dq_look_scope_globals()
	var/turf/T = test_floor()
	var/list/base_vars = dq_look_state_base_vars(/obj, T)
	var/obj/dq_look_late_dependency/probe = allocate(/obj/dq_look_late_dependency, T)
	var/list/fallback = dq_look_probe_names(probe, base_vars, "*")
	TEST_ASSERT_EQUAL(length(fallback), DQ_LOOK_STATE_MAX_VARS, "Unknown read plans retain the original fallback limit")
	TEST_ASSERT(!(nameof(probe.late_read) in fallback), "The actual late field lies beyond the unfiltered limit")
	var/list/recorded = dq_look_recorded_probe_names(list("fixture" = list("/obj/dq_look_late_dependency late_read=1 +state: late-1", "/obj/dq_look_late_dependency late_read=2 +state: late-2")))
	var/list/stable_unknown = dq_look_probe_names(probe, base_vars, "*", recorded["/obj/dq_look_late_dependency"])
	TEST_ASSERT_EQUAL(length(stable_unknown), DQ_LOOK_STATE_MAX_VARS, "Unknown plans retain the existing budget while prioritizing historical coverage")
	TEST_ASSERT_EQUAL(stable_unknown[1], nameof(probe.late_read), "Actual late recorded dependency survives 25 earlier unrelated fields")
	var/unknown_base = refresh_look(probe)
	probe.set_late_read(1)
	refresh_flush()
	TEST_ASSERT_EQUAL(probe.icon_state, "late-1", "Required historical field uses its real tracked setter to change the native look")
	probe.set_late_read(0)
	refresh_flush()
	TEST_ASSERT_EQUAL(probe.rx.look_key, unknown_base, "Real tracked setter roundtrip restores the original native look")
	TEST_ASSERT_NOTNULL(dq_look_recorded_probe_problem(probe, "removed_field"), "A removed historical input reports a coverage problem, never silent retirement")
	TEST_ASSERT_NOTNULL(dq_look_recorded_probe_problem(probe, nameof(probe.name)), "A nonnumeric historical input reports explicit coverage error")

	var/list/planned = dq_look_probe_names(probe, base_vars, list(nameof(probe.late_read)))
	TEST_ASSERT_EQUAL(length(planned), 1, "Concrete plan excludes all early unread fields before applying the limit")
	TEST_ASSERT_EQUAL(planned[1], nameof(probe.late_read), "The real analyzed late dependency remains eligible")
	for(var/type in list(/obj/item/gun/projectile/automatic/l6_saw, /obj/item/gun/projectile/automatic/mg42))
		var/obj/item/gun/projectile/automatic/G = allocate(type, T)
		var/list/names = dq_look_probe_names(G, base_vars, list("cover_open"))
		TEST_ASSERT("cover_open" in names, "The real machine-gun cover remains a planned numeric field [type]")
		var/cover_setter = (type == /obj/item/gun/projectile/automatic/l6_saw) ? TYPE_PROC_REF(/obj/item/gun/projectile/automatic/l6_saw, set_cover_open) : TYPE_PROC_REF(/obj/item/gun/projectile/automatic/mg42, set_cover_open)
		var/original = G.vars["cover_open"]
		dq_look_settle()
		var/list/before = dq_look_pin_lines(G)
		call(G, cover_setter)(!original)
		dq_look_settle()
		var/list/changed_rows = dq_look_pin_lines(G)
		TEST_ASSERT_NOTEQUAL(jointext(before, "\n"), jointext(changed_rows, "\n"), "Actual cover setter changes the gun's native look [type]")
		call(G, cover_setter)(original)
		dq_look_settle()
		var/list/restored = dq_look_pin_lines(G)
		TEST_ASSERT_EQUAL(jointext(restored, "\n"), jointext(before, "\n"), "Actual cover setter restores the native look [type]")


// Instance-only real native rolls and a tracked look input exercise fresh/reuse parity.
/obj/item/dq_roll_probe/dq_look_native
	abstract_type = /obj/item/dq_roll_probe/dq_look_native
	var/probe_on = FALSE
TRACKED(/obj/item/dq_roll_probe/dq_look_native, probe_on)
/obj/item/dq_roll_probe/dq_look_native/draw(datum/look/look)
	..()
	look.state("[shade]-[size]-[probe_on]")

/datum/unit_test/dq_look_sweep_native_roll_parity/Run()
	dq_look_scope_globals()
	var/type = /obj/item/dq_roll_probe/dq_look_native
	var/turf/T = test_floor()
	var/list/base_vars = dq_look_state_base_vars(/obj, T)
	var/list/plan = list("[type]" = list("probe_on"))
	var/datum/dq_look_result/reused = new
	var/datum/dq_look_result/fresh = new
	var/datum/dq_look_result/reordered = new
	dq_look_unit(type, T, base_vars, plan, reused, TRUE, TRUE)
	TEST_ASSERT_EQUAL(GLOB.round_seed, dq_test_seed_for("[type]"), "Actual sweep fixes the native seed to the type's base")
	TEST_ASSERT(length(reused.probe_rows), "Real tracked state changes actually produce look-difference rows")
	// Intervening native allocations consume a different seed and serial; they
	// cannot change this type's later base or any of its fresh probe realizations.
	rolls_fix_seed(dq_test_seed_for("intervening native object"))
	var/obj/e3_source/container = allocate(/obj/e3_source, T)
	var/obj/item/dq_roll_probe/intervening = allocate(/obj/item/dq_roll_probe, container)
	TEST_ASSERT(GLOB.roll_serial > 0, "Actual non-map native roll allocation consumes its stream serial")
	lifeform_end(intervening, END_SCOPE)
	dq_look_unit(type, T, base_vars, plan, fresh, TRUE, TRUE, TRUE)
	TEST_ASSERT_EQUAL(jointext(fresh.made, "\n"), jointext(reused.made, "\n"), "Intervening native rolls leave the made look identical")
	TEST_ASSERT_EQUAL(jointext(fresh.probe_rows, "\n"), jointext(reused.probe_rows, "\n"), "Fresh probe instances use the same native realization as the reused base")
	rolls_fix_seed(dq_test_seed_for("another intervening order"))
	GLOB.roll_serial = 12345
	dq_look_unit(type, T, base_vars, plan, reordered, TRUE, TRUE)
	TEST_ASSERT_EQUAL(jointext(reordered.made, "\n"), jointext(reused.made, "\n"), "Different prior seed and serial do not affect the repeated native look")
	TEST_ASSERT_EQUAL(jointext(reordered.probe_rows, "\n"), jointext(reused.probe_rows, "\n"), "Repeated reuse preserves actual native state-probe rows")
	TEST_ASSERT(!length(reused.impure) && !length(fresh.impure) && !length(reordered.impure), "Every actual setter roundtrip returns its native look to the base")

#undef DQ_LOOK_TREE_DIR
#undef DQ_LOOK_STATE_DIR

/// A state-pin unit of a type that spills things when it dies (a blob core drops a chunk, a gun cabinet its guns) leaves the floor
/// clear, so a closet made after it takes nothing in: the cost of a probe stays the same however many came before it.
/datum/unit_test/dq_look_state_probe_leaves_floor_clear

/datum/unit_test/dq_look_state_probe_leaves_floor_clear/Run()
	var/turf/T = test_floor()
	var/list/base_vars = dq_look_state_base_vars(/obj, T)
	for(var/type in list(/obj/structure/blob/core, /obj/structure/closet/secure_closet/guncabinet/sidearm))
		dq_look_unit(type, T, base_vars, null, new /datum/dq_look_result, FALSE, TRUE)
		var/list/left = list()
		for(var/atom/movable/AM as anything in contents_of(T))
			if(!QDELETED(AM) && !istype(AM, /obj/effect/landmark))
				left += AM
		var/atom/movable/first = length(left) ? left[1] : null
		TEST_ASSERT(!length(left), "[type]'s probes left [length(left)] things on the floor ([first?.type])")
	var/obj/structure/closet/C = allocate(/obj/structure/closet/coffin, T)
	TEST_ASSERT(!length(C.contents), "a closet made after the probes took in [length(C.contents)] things")

/// Writing the original value back after a probe returns the look to the made one, so the rows of a type probed on one instance
/// are the rows a fresh instance per probe gives.
/datum/unit_test/dq_look_sweep_reuse_matches_fresh

/datum/unit_test/dq_look_sweep_reuse_matches_fresh/Run()
	var/turf/T = test_floor()
	var/list/base_vars = dq_look_state_base_vars(/obj, T)
	for(var/type in list(/obj/structure/bed/chair/shuttle, /obj/structure/closet/coffin, /obj/structure/table))
		var/datum/dq_look_result/reused = new
		var/datum/dq_look_result/fresh = new
		dq_look_unit(type, T, base_vars, null, reused, TRUE, TRUE)
		dq_look_unit(type, T, base_vars, null, fresh, TRUE, TRUE, TRUE)
		TEST_ASSERT_EQUAL(jointext(reused.probe_rows, "\n"), jointext(fresh.probe_rows, "\n"), "[type]: one instance for every probe gave other rows than a fresh one per probe")
		TEST_ASSERT(!length(reused.impure), "[type]: a write-back did not return the look: [jointext(reused.impure, "; ")]")
