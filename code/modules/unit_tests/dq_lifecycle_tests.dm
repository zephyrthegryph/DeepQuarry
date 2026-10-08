// Lifecycle tests (roadmap L2, doc/rewrite/state.md section 6).
//
// The sandbox test: for every latent-safe type, Initialize() must not touch
// the world, and on_materialize()/on_dematerialize() must round-trip cleanly.

/// Subsystem vars that are bookkeeping, not registration: deletion queues,
/// appearance work and init batches change whenever anything is created or
/// deleted, and the test itself creates and deletes.
GLOBAL_LIST_INIT(dq_lifecycle_snapshot_ignored, list(
	/datum/system/garbage,
	/datum/system/overlays,
	/datum/system/atoms,
))

/// GLOB lists that are first-use caches, not registrations. The warm-up instance fills a
/// type's cache entries, but a type that picks at random (exotic_feedstock/random picks a
/// material) warms a different key on every instance.
GLOBAL_LIST_INIT(dq_lifecycle_snapshot_ignored_globs, list(
	"material_recipe_cache",
	// Type -> the registries it joins, filled lazily the first time a type joins (registries.dm):
	// a per-type cache, not a registration (those are the "registry <id>" counts). The warm-up
	// instance can't pre-fill it for randomised contents (an MRE's meal picks), so a content type
	// first seen on materialize() would read as a round-trip change.
	"registries_by_type",
	// The per-frame refresh drain queue (refresh.dm): a setter in Initialize() queues the atom's
	// derived outputs, and the next drain empties it (skipping deleted entries). Scratch, not a
	// registration, like the native system's per-frame lists below.
	"refresh_queue",
	// "[type]|[proc]" -> first instance, filled the first time a type's lists are checked (type_list.dm).
	// Type-keyed caches are recognised by their keys (dq_lifecycle_grew_by_type_keys()); this one is
	// keyed by text. A type whose contents pick at random (gum's flavour) meets a new type each time.
	"type_list_purity",
	// /datum/type_table -> its hooks, built on first use (engine/actions/hooks.dm). Keyed by the type table of
	// whatever the atom creates in Initialize(), so a randomised content type (an MRE's meal) is first seen after the warm-up.
	"hook_tables",
	// Capability signature -> the one shared capability with those settings (cap_intern()): definitions interned the first
	// time a type declares them, keyed by text. An atom that makes random contents (an MRE's meal) meets new types after the warm-up.
	"caps_interned",
	// Holder uid -> its capability runtime record (capability_tables.dm): an instance's own state (materials a scrap rolled,
	// what a belt's tools hold), made when it first has some and removed in that holder's final cleanup
	// (dq_time_foundation_compatibility_tests proves the removal), so it grows with live instances and is no registration.
	"capability_runtime_records",
))

/// Cached (container, varname) pairs for every list-valued var on GLOB and on
/// every non-ignored subsystem, keyed by the same string dq_lifecycle_snapshot()
/// used to use as a snapshot key. Building this means walking GLOB.vars and
/// every subsystem's vars table (hundreds of entries each) with dynamic
/// per-name dereferences to find which vars are lists in the first place --
/// the set of *which* vars are list-valued never changes for the lifetime of
/// a test world, so dq_lifecycle_sandbox (which snapshots three times per
/// latent-safe type, ~800+ types) only pays that walk once instead of ~2400
/// times. Null until dq_lifecycle_snapshot_var_keys() first builds it.
GLOBAL_VAR(dq_lifecycle_snapshot_var_keys)

/// Builds (and caches) the list-valued-var key set described above.
/// Each value is a 2-element list: [container, varname], so the snapshot proc
/// can re-read the current length without re-walking any vars table.
/proc/dq_lifecycle_snapshot_var_keys()
	if(GLOB.dq_lifecycle_snapshot_var_keys)
		return GLOB.dq_lifecycle_snapshot_var_keys
	var/list/keys = list()
	for(var/name in GLOB.vars)
		if(name == "vars")
			continue
		// The OM handle table (om_handle()) is an id allocator, not a registration.
		if(findtext(name, "om_handle_") == 1)
			continue
		// type -> registries, a per-type cache filled on a type's first
		// materialize (a box's first-seen contents type), not a registration:
		// membership itself is the "registry [id]" counts below. Counting it made
		// the round trip fail depending on which tests ran first.
		if(name == "registries_by_type")
			continue
		if(name in GLOB.dq_lifecycle_snapshot_ignored_globs)
			continue
		// Test-build audit indexes (own_audit_index, om_rec_audit_index) mirror every owned
		// entity and OM record so the orphan audit can find leaks; a child adopted in
		// Initialize() is ownership, not a world registration.
		if(findtext(name, "_audit_index") && findtext(name, "_audit_index") == length(name) - length("_audit_index") + 1)
			continue
		if(islist(GLOB.vars[name]))
			keys["GLOB.[name]"] = list(GLOB, name)
	// Every system's registries and queues are walked the same way.
	// The native system's per-frame scratch lists churn by design, so only its entity tables count.
	for(var/datum/system/system as anything in kernel_pure_systems())
		var/native = istype(system, /datum/system/native)
		for(var/name in system.vars)
			if(name == "vars")
				continue
			if(native && !(name in list("bound", "entities_by_index")))
				continue
			if(islist(system.vars[name]))
				keys["[system.type].[name]"] = list(system, name)
	GLOB.dq_lifecycle_snapshot_var_keys = keys
	return keys

/// Global state an object could register itself with, as sizes.
/// Covers every list var on GLOB and on every subsystem (processing lists,
/// machine lists, lighting queues, registries), each radio frequency's device
/// lists, and the listeners of every global signal.
///
/// Returns list(sizes, dynamic): `sizes` is a flat list of lengths, one per
/// entry of the cached var key set (dq_lifecycle_snapshot_var_keys(), same
/// order every call); `dynamic` is key -> size for the sets whose keys can
/// change (radio filters, registries, world hooks). The flat half was an assoc
/// list keyed by strings, and building it and diffing it through a key union
/// was most of dq_lifecycle_sandbox's time (~2 ms per snapshot and per diff).
/proc/dq_lifecycle_snapshot()
	var/list/var_keys = dq_lifecycle_snapshot_var_keys()
	var/list/sizes = new /list(length(var_keys))
	var/i = 0
	for(var/key in var_keys)
		i++
		var/list/container_and_name = var_keys[key]
		var/datum/container = container_and_name[1]
		var/value = container.vars[container_and_name[2]]
		// Defensive: the cached key set only records which vars were
		// list-valued at cache-build time. If a var was ever reassigned to a
		// non-list (shouldn't happen for these bookkeeping lists, but a
		// runtime here would be worse than a missed diff), treat it as absent
		// rather than erroring length() on a non-list value.
		sizes[i] = islist(value) ? length(value) : 0
	var/list/dynamic = list()
	for(var/frequency_text in SSradio.frequencies)
		var/datum/radio_frequency/frequency = SSradio.frequencies[frequency_text]
		for(var/radio_filter in frequency.devices)
			var/list/devices = frequency.devices[radio_filter]
			dynamic["radio [frequency_text] [radio_filter]"] = length(devices)
	for(var/id in GLOB.registries)
		dynamic["registry [id]"] = REGISTRY_COUNT(id)
	var/list/world_observers = observer_counts(OM_WORLD)
	for(var/trigger in world_observers)
		dynamic["world observer [trigger]"] = world_observers[trigger]
	return list(sizes, dynamic)

/// The keys whose sizes differ between two snapshots, as readable lines.
/proc/dq_lifecycle_snapshot_diff(list/before, list/after)
	. = list()
	var/list/before_sizes = before[1]
	var/list/after_sizes = after[1]
	var/list/var_keys = dq_lifecycle_snapshot_var_keys()
	for(var/i in 1 to min(length(before_sizes), length(after_sizes)))
		if(before_sizes[i] != after_sizes[i])
			var/list/container_and_name = var_keys[var_keys[i]]
			var/datum/container = container_and_name[1]
			if(dq_lifecycle_grew_by_type_keys(container.vars[container_and_name[2]], before_sizes[i], after_sizes[i]))
				continue
			. += "[var_keys[i]] [before_sizes[i]] -> [after_sizes[i]]"
	// Missing keys count as size 0, as before.
	var/list/before_dynamic = before[2]
	var/list/after_dynamic = after[2]
	for(var/key in before_dynamic)
		var/old_size = before_dynamic[key] || 0
		var/new_size = after_dynamic[key] || 0
		if(old_size != new_size)
			. += "[key] [old_size] -> [new_size]"
	for(var/key in after_dynamic)
		if(!isnull(before_dynamic[key]))
			continue
		var/new_size = after_dynamic[key] || 0
		if(new_size)
			. += "[key] 0 -> [new_size]"

/// TRUE when `L` only grew, and every entry it gained (appended, so past `old_size`) is keyed by a
/// type path: a per-type cache filled the first time a type is seen (a reaction table, a derived-value
/// table). A type whose contents pick at random (a meal box, a flavoured gum) meets a new type on each
/// instance. A registration holds instances, never types.
/proc/dq_lifecycle_grew_by_type_keys(list/L, old_size, new_size)
	if(!islist(L) || new_size <= old_size || length(L) != new_size)
		return FALSE
	for(var/i in old_size + 1 to new_size)
		if(!ispath(L[i]))
			return FALSE
	return TRUE

/// Running behaviour the object started on itself: timers and processing.
/proc/dq_lifecycle_running(datum/D)
	. = list()
	// An armed expire() is the object's own declared lifetime, not running behaviour.
	var/timers = om_timer_count(D)
	if(ismovable(D))
		var/atom/movable/AM = D
		if(after_pending(AM, "lifecycle_lifetime_timer"))
			timers--
	if(timers > 0)
		. += "[timers] timer(s)"
	if(D.datum_flags & DF_ISPROCESSING)
		. += "processing"

/datum/unit_test/dq_lifecycle_sandbox
	is_sweep_test = TRUE
	tier = TEST_TIER_EXHAUSTIVE

/// One latent-safe type from each latent-safe family (latent_safe_types.dm):
/// the fixed subset the normal-tier representatives of the latent sweeps check.
/proc/dq_latent_representative_types()
	return list(
		/obj/item/stock_parts/capacitor,
		/obj/item/circuitboard/autolathe,
		/obj/item/smes_coil,
		/obj/item/bluespace_crystal,
		/obj/item/paper,
		/obj/item/pen,
		/obj/item/reagent_containers/pill/paracetamol,
		/obj/item/light/tube,
		/obj/item/ammo_casing/a9mm,
		/obj/item/ammo_magazine/m9mm,
		/obj/item/clothing/under/color/grey,
		/obj/item/clothing/suit/armor/vest,
		/obj/item/clothing/shoes/black,
		/obj/item/clothing/head/helmet,
		/obj/item/tool/wrench,
		/obj/item/trash/candy,
		/obj/item/stack/rods,
		/obj/item/stack/material/steel,
		/obj/item/storage/box,
		/obj/item/storage/toolbox,
		/obj/item/storage/backpack,
		/obj/item/storage/firstaid/regular,
		/obj/item/radio,
		/obj/item/card/id,
	)

/// Normal tier: the sandbox on a fixed subset (every latent-safe family, plus a
/// listed clean type). The whole-tree sweep runs in CI and nightly.
/datum/unit_test/dq_lifecycle_sandbox/representative
	is_sweep_test = FALSE
	tier = TEST_TIER_NORMAL

/datum/unit_test/dq_lifecycle_sandbox/representative/curated_types()
	return dq_latent_representative_types() + /obj/item/pda

/// Types that are not latent-safe yet but register with the world only in
/// on_materialize() (L3). The sandbox test holds them to the same rule. Only
/// the listed type itself is checked, not its subtypes. Cameras register in
/// on_materialize() too, but /obj/machinery still starts processing in
/// Initialize(), so no machine can be listed yet.
GLOBAL_LIST_INIT(dq_lifecycle_clean_types, list(
	/obj/item/pda,
	/obj/item/radio,
	/obj/item/gps,
	/obj/item/implant/tracking,
	/obj/item/card/id,
	/obj/item/card/id/guest,
))

/datum/unit_test/dq_lifecycle_sandbox/Run()
	set_global("dq_lifecycle_snapshot_var_keys", GLOB.dq_lifecycle_snapshot_var_keys)
	var/list/failures = list()
	var/tested = 0
	var/list/tested_paths
	for(var/atom/movable/path as anything in sweep_types(subtypesof(/atom/movable)))
		if(!(latent_type_safe(path) || (path in GLOB.dq_lifecycle_clean_types)) || is_abstract(path))
			continue
		tested++
		LAZYSET(tested_paths, path, TRUE)
		// Warm up: the first instance of a type builds per-type caches
		// (element singletons, schemas, static lists) that are not registrations.
		qdel(new path)

		var/list/before = dq_lifecycle_snapshot()
		var/atom/movable/sandboxed = new_unmaterialized(path, null)
		var/list/initialized = dq_lifecycle_snapshot()
		var/list/problems = dq_lifecycle_snapshot_diff(before, initialized)
		problems += dq_lifecycle_running(sandboxed)
		if(sandboxed.flags & ATOM_MATERIALIZED)
			problems += "materialized inside the sandbox"
		if(length(problems))
			failures += "[path]: Initialize() changed the world: [jointext(problems, ", ")]"

		sandboxed.materialize()
		if(!(sandboxed.flags & ATOM_MATERIALIZED))
			failures += "[path]: materialize() did not set ATOM_MATERIALIZED"
		sandboxed.dematerialize()
		var/list/round_trip = dq_lifecycle_snapshot_diff(initialized, dq_lifecycle_snapshot())
		if(length(round_trip))
			failures += "[path]: on_materialize()/on_dematerialize() did not round-trip: [jointext(round_trip, ", ")]"
		qdel(sandboxed)
	TEST_ASSERT(tested > 0, "no latent-safe types found")
	var/list/curated = curated_types()
	if(curated)
		var/list/untested = list()
		for(var/path in curated)
			if(!LAZYACCESS(tested_paths, path))
				untested += "[path]"
		TEST_ASSERT(!length(untested), "curated types that are not latent-safe (or a listed clean type): [jointext(untested, ", ")]")
	if(length(failures))
		TEST_FAIL("[length(failures)] problem(s) across [tested] latent-safe types:\n[jointext(failures, "\n")]")

/// The init path materializes normal atoms, Destroy() dematerializes them, and
/// the sandbox helper leaves them unmaterialized until asked.
/datum/unit_test/dq_lifecycle_hooks_wired

/datum/unit_test/dq_lifecycle_hooks_wired/Run()
	var/obj/item/paper/live = allocate(/obj/item/paper)
	TEST_ASSERT(live.flags & ATOM_MATERIALIZED, "a normally created atom should be materialized")
	var/obj/item/paper/sandboxed = new_unmaterialized(/obj/item/paper, null)
	TEST_ASSERT(sandboxed.flags & ATOM_INITIALIZED, "the sandboxed atom should be initialized")
	TEST_ASSERT(!(sandboxed.flags & ATOM_MATERIALIZED), "the sandboxed atom should not be materialized")
	TEST_ASSERT(sandboxed.materialize(), "materialize() should report the transition")
	TEST_ASSERT(!sandboxed.materialize(), "a second materialize() should do nothing")
	qdel(sandboxed)
	TEST_ASSERT(!(sandboxed.flags & ATOM_MATERIALIZED), "Destroy() should dematerialize")
	var/obj/item/paper/after = allocate(/obj/item/paper)
	TEST_ASSERT(after.flags & ATOM_MATERIALIZED, "the suppression must not leak past new_unmaterialized()")

/// Registries (L3): membership follows materialize/dematerialize, and a
/// sandboxed object is not a member.
/datum/unit_test/dq_registry_membership

/datum/unit_test/dq_registry_membership/Run()
	var/obj/item/pda/live = allocate(/obj/item/pda)
	TEST_ASSERT(live in REGISTRY_MEMBERS(REGISTRY_PDAS), "a live PDA should be in the PDA registry")
	var/obj/item/pda/sandboxed = new_unmaterialized(/obj/item/pda, null)
	TEST_ASSERT(!(sandboxed in REGISTRY_MEMBERS(REGISTRY_PDAS)), "a sandboxed PDA should not be registered")
	sandboxed.materialize()
	TEST_ASSERT(sandboxed in REGISTRY_MEMBERS(REGISTRY_PDAS), "materialize() should join the registry")
	var/count = REGISTRY_COUNT(REGISTRY_PDAS)
	qdel(sandboxed)
	TEST_ASSERT(!(sandboxed in REGISTRY_MEMBERS(REGISTRY_PDAS)), "Destroy() should leave the registry")
	TEST_ASSERT_EQUAL(REGISTRY_COUNT(REGISTRY_PDAS), count - 1, "exactly one member should leave")
	// Subtypes inherit membership; a type can be in several registries.
	var/obj/machinery/power/smes/smes = allocate(/obj/machinery/power/smes)
	TEST_ASSERT(smes in REGISTRY_MEMBERS(REGISTRY_SMES), "an SMES should be in the SMES registry")
	TEST_ASSERT(smes in REGISTRY_MEMBERS(REGISTRY_MACHINES), "an SMES should be in the machine registry")

/// No registry may hold a deleted object: that is the hard-delete source
/// registries exist to remove.
/datum/unit_test/dq_registry_no_deleted_members

/datum/unit_test/dq_registry_no_deleted_members/Run()
	var/list/failures = list()
	for(var/id in GLOB.registries)
		for(var/atom/member as anything in REGISTRY_MEMBERS(id))
			if(QDELETED(member))
				failures += "[id]: [member.type]"
	if(length(failures))
		TEST_FAIL("deleted objects left in registries:\n[jointext(failures, "\n")]")
