// The compiled init plan (code/engine/declare/init_plan.dm) against the per-instance discovery it replaced.

/// Every compiled plan says what the discovery path finds for its type, step by step.
/datum/unit_test/dq_init_plan_matches_discovery

/datum/unit_test/dq_init_plan_matches_discovery/Run()
	var/list/cache = init_plan_cache()
	TEST_ASSERT(length(cache) > 50, "the map load compiled plans ([length(cache)])")
	var/checked = 0
	for(var/type in cache)
		var/datum/init_plan/P = cache[type]
		var/datum/type_table/T = type_table_cache()[type]
		TEST_ASSERT_NOTNULL(T, "[type] has a plan but no table")
		TEST_ASSERT_EQUAL(P.hook_flags, T.hook_flags, "[type] hook flags")
		var/list/pre = list()
		var/list/ini = list()
		for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_CAPABILITY))
			var/datum/capability/def = C.item
			if(def.holder_hooks & HOLDER_HOOK_PREINIT)
				pre += def
			if(def.holder_hooks & HOLDER_HOOK_INIT)
				ini += def
		TEST_ASSERT(init_plan_same_list(pre, P.preinit_caps), "[type] preinit hooks")
		TEST_ASSERT(init_plan_same_list(ini, P.init_caps), "[type] init hooks")
		var/list/grants = list()
		for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_REL_GRANTS))
			var/datum/entry/E = C.item
			grants += E.args["var"]
		TEST_ASSERT(init_plan_same_list(grants, P.rel_grant_vars), "[type] relation grants")
		TEST_ASSERT_EQUAL(P.change_baseline, !!GLOB.change_index_by_type[type], "[type] on_change baseline")
		var/every = FALSE
		for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_EVERY))
			if(isnull(C.owner))
				every = TRUE
		TEST_ASSERT_EQUAL(P.every_arm, every, "[type] every() arming")
		if(ispath(type, /atom))
			TEST_ASSERT_EQUAL(P.verb_entries, !!GLOB.verb_entry_sets[type], "[type] verb entries")
		checked++
	log_world("dq_init_plan_matches_discovery: [checked] plans checked")

/proc/init_plan_same_list(list/a, list/b)
	if(LAZYLEN(a) != LAZYLEN(b))
		return FALSE
	for(var/i in 1 to LAZYLEN(a))
		if(a[i] != b[i])
			return FALSE
	return TRUE

/// An instance initialised through the plan ends in the state the discovery path left (recorded in dq_init_plan_golden.dm before that path was
/// deleted): representative map types.
/datum/unit_test/dq_init_plan_parity

/datum/unit_test/dq_init_plan_parity/Run()
	var/list/types = dq_init_plan_types()
	var/turf/at = run_loc_floor_bottom_left
	var/list/failures = list()
	for(var/type in types)
		if(!ispath(type))
			continue
		var/list/with_plan = init_plan_snapshot(type, at)
		var/list/recorded = dq_init_plan_golden()[type]
		TEST_ASSERT_NOTNULL(recorded, "[type] has a recorded state (dq_init_plan_golden.dm)")
		var/list/diffs = list()
		// The recording went through JSON: a path came back as its text and a name's text macros as their characters, so values compare as text, and
		// a name compares without its leading text-macro character (\proper, \improper).
		for(var/key in with_plan | recorded)
			if(dq_golden_text(with_plan[key]) != dq_golden_text(recorded[key]))
				diffs += "[key]: plan [with_plan[key]] / recorded [recorded[key]]"
		if(length(diffs))
			failures += "[type] differs from the state the discovery path left (recorded): [jointext(diffs, "; ")]"
	// Every type's differences in one report, so a re-recording sees them all at once.
	TEST_ASSERT(!length(failures), jointext(failures, "\n"))

/// The engine-visible state of a fresh `type` made with the plan on or off: primitive vars, and the engine records it was given.
/proc/init_plan_snapshot(type, turf/at)
	var/list/had = at.contents.Copy()
	rand_seed(4242) // the same rolls as the recording (a light fixture's broken_chance)
	var/atom/A = new type(at)
	. = list()
	var/static/list/skip = list("x", "y", "z", "loc", "vars", "type", "parent_type", "tag", "contents", "gc_destroyed", "serial", "weak_reference", "datum_id", "rx", "refresh_queued", "refresh_bits", "handle_slot", "own_holder_ref")
	for(var/V in A.vars)
		if(V in skip)
			continue
		var/value = A.vars[V]
		if(istext(value) && findtext(value, "\[0x"))
			.[V] = "(instance ref)" // another instance's identity, not state
		else if(isnull(value) || isnum(value) || istext(value) || ispath(value))
			.[V] = value
		else if(islist(value))
			var/list/L = value
			.["[V].len"] = length(L)
	.["refresh_queued"] = !!A.refresh_queued
	.["setup_pending"] = !!setup_pending?[A]
	var/datum/rx_state/rx = A.rx
	.["change_last"] = rx ? LAZYLEN(rx.change_last) : 0
	// The on_change baselines themselves, not only how many. A baseline is keyed by its hook's serial, which moves whenever a hook is declared
	// anywhere, so the snapshot names each by the key it watches and its place among that key's hooks.
	var/list/baselines
	var/list/index = change_index_of(A)
	if(rx?.change_last && islist(index))
		for(var/key in index)
			var/key_id = isnum(key) ? key : text2num("[key]")
			var/key_name = (key_id && change_key_name(key_id)) || "[key]"
			var/n = 0
			for(var/datum/hook/H as anything in index[key])
				n++
				var/serial = "[H.serial]"
				if(serial in rx.change_last)
					LAZYSET(baselines, "[key_name]#[n]", rx.change_last[serial])
	.["change_values"] = baselines ? json_encode(baselines) : ""
	.["every_parked"] = rx ? LAZYLEN(rx.every_parked) : 0
	.["activations"] = rx ? LAZYLEN(rx.activations) : 0
	.["verbs"] = length(A.verbs)
	qdel(A)
	// What its teardown dropped on the tile (a fixture's bulb) goes too: the next instance starts on the tile this one found.
	for(var/atom/movable/left in at.contents - had)
		log_world("dq_init_plan_parity: [type] left [left.type] on its tile; removed")
		qdel(left)

/// The representative map types the init parity covers.
/proc/dq_init_plan_types()
	return list(
		/obj/machinery/door/firedoor,
		/obj/machinery/light,
		/obj/machinery/atmospherics/pipe/simple/hidden,
		/obj/structure/grille,
		/obj/structure/table/standard,
		/obj/item/tool/wrench,
		/obj/machinery/vending/coffee,
		/obj/structure/extinguisher_cabinet,
	)

/// A snapshot value as comparable text: what JSON keeps of it (a path's text; a text without the text-macro characters BYOND writes in names).
/proc/dq_golden_text(value)
	if(isnull(value))
		return ""
	var/text = "[value]"
	var/list/kept = list()
	for(var/i in 1 to length(text))
		var/code = text2ascii(text, i)
		if(code >= 32 && code < 127)
			kept += ascii2text(code)
	return jointext(kept, "")
