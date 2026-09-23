// Lifecycle tests (roadmap L2, doc/rewrite/state.md section 6).
//
// The sandbox test: for every latent-safe type, Initialize() must not touch
// the world, and on_materialize()/on_dematerialize() must round-trip cleanly.

/// Subsystem vars that are bookkeeping, not registration: deletion queues,
/// appearance work and init batches change whenever anything is created or
/// deleted, and the test itself creates and deletes.
GLOBAL_LIST_INIT(dq_lifecycle_snapshot_ignored, list(
	/datum/controller/subsystem/garbage,
	/datum/controller/subsystem/overlays,
	/datum/controller/subsystem/atoms,
))

/// Global state an object could register itself with, as key -> size.
/// Covers every list var on GLOB and on every subsystem (processing lists,
/// machine lists, lighting queues, registries), each radio frequency's device
/// lists, and the listeners of every global signal.
/proc/dq_lifecycle_snapshot()
	var/list/snapshot = list()
	for(var/name in GLOB.vars)
		if(name == "vars")
			continue
		var/value = GLOB.vars[name]
		if(islist(value))
			snapshot["GLOB.[name]"] = length(value)
	for(var/datum/controller/subsystem/subsystem as anything in Master.subsystems)
		if(subsystem.type in GLOB.dq_lifecycle_snapshot_ignored)
			continue
		for(var/name in subsystem.vars)
			if(name == "vars")
				continue
			var/value = subsystem.vars[name]
			if(islist(value))
				snapshot["[subsystem.type].[name]"] = length(value)
	for(var/frequency_text in SSradio.frequencies)
		var/datum/radio_frequency/frequency = SSradio.frequencies[frequency_text]
		for(var/radio_filter in frequency.devices)
			var/list/devices = frequency.devices[radio_filter]
			snapshot["radio [frequency_text] [radio_filter]"] = length(devices)
	for(var/id in GLOB.registries)
		snapshot["registry [id]"] = REGISTRY_COUNT(id)
	for(var/signal in SSdcs._listen_lookup)
		var/listeners = SSdcs._listen_lookup[signal]
		snapshot["global signal [signal]"] = islist(listeners) ? length(listeners) : 1
	return snapshot

/// The keys whose sizes differ between two snapshots, as readable lines.
/proc/dq_lifecycle_snapshot_diff(list/before, list/after)
	. = list()
	for(var/key in before | after)
		var/old_size = before[key] || 0
		var/new_size = after[key] || 0
		if(old_size != new_size)
			. += "[key] [old_size] -> [new_size]"

/// Running behaviour the object started on itself: timers and processing.
/proc/dq_lifecycle_running(datum/D)
	. = list()
	if(length(D._active_timers))
		. += "[length(D._active_timers)] timer(s)"
	if(D.datum_flags & DF_ISPROCESSING)
		. += "processing"

/datum/unit_test/dq_lifecycle_sandbox

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
	var/list/failures = list()
	var/tested = 0
	for(var/atom/movable/path as anything in subtypesof(/atom/movable))
		if(!(initial(path.latent_safe) || (path in GLOB.dq_lifecycle_clean_types)) || is_abstract(path))
			continue
		tested++
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
