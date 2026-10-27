// after_init(delay, parts...) (code/engine/actions/after_init.dm): an after() armed when the instance's init is complete.

/// ("init" | "after" | "gated", probe, extra) entries, in the order they happened.
GLOBAL_LIST_EMPTY(dq_after_init_log)

/// Logs its own code after ..() and its after_init(0).
/obj/effect/dq_after_init_probe
	name = "after_init probe"
	/// How many probes had initialized when this one's after_init() ran.
	var/saw_initialized = 0
	var/saw_mapload = null
	var/armed = TRUE

CAPABILITIES(/obj/effect/dq_after_init_probe)
	after_init(0, then(PROC_REF(after_init_ran)))
	when(nameof(armed), after_init(0, then(PROC_REF(gated_ran))))

/obj/effect/dq_after_init_probe/Initialize(mapload)
	. = ..()
	GLOB.dq_after_init_log.Add(list(list("init", src)))

/obj/effect/dq_after_init_probe/proc/after_init_ran(datum/act/timer/A)
	saw_mapload = A.mapload
	for(var/obj/effect/dq_after_init_probe/other in GLOB.dq_after_init_probes)
		if(other.flags & ATOM_INITIALIZED)
			saw_initialized++
	GLOB.dq_after_init_log.Add(list(list("after", src)))

/obj/effect/dq_after_init_probe/proc/gated_ran(datum/act/timer/A)
	GLOB.dq_after_init_log.Add(list(list("gated", src)))

/// The probes of the running test (so a handler can count its siblings).
GLOBAL_LIST_EMPTY(dq_after_init_probes)

/// A subtype that turns the gate off before its init completes.
/obj/effect/dq_after_init_probe/unarmed
	armed = FALSE

/datum/unit_test/dq_after_init
	abstract_type = /datum/unit_test/dq_after_init

/datum/unit_test/dq_after_init/on_destroy(force)
	GLOB.dq_after_init_log.Cut()
	GLOB.dq_after_init_probes.Cut()
	return ..()

/// Index of the first log entry of `kind` for `probe`, or 0.
/datum/unit_test/dq_after_init/proc/at(kind, probe)
	var/list/log = GLOB.dq_after_init_log
	for(var/i in 1 to length(log))
		var/list/entry = log[i]
		if(entry[1] == kind && entry[2] == probe)
			return i
	return 0

/// Made at runtime: the after_init(0) runs as Initialize() returns, after the type's own code after ..(), and the gate is read then.
/datum/unit_test/dq_after_init/runtime

/datum/unit_test/dq_after_init/runtime/Run()
	var/obj/effect/dq_after_init_probe/probe = allocate(/obj/effect/dq_after_init_probe, dq_containment_floor())
	TEST_ASSERT(at("after", probe), "after_init(0) ran by the time new() returned")
	TEST_ASSERT(at("init", probe) < at("after", probe), "it ran after the type's own code after ..()")
	TEST_ASSERT_EQUAL(probe.saw_mapload, FALSE, "A.mapload is FALSE for an instance made at runtime")
	TEST_ASSERT(at("gated", probe), "a when() that holds lets its after_init() run")
	var/obj/effect/dq_after_init_probe/unarmed/off = allocate(/obj/effect/dq_after_init_probe/unarmed, dq_containment_floor())
	TEST_ASSERT(at("after", off), "the ungated after_init() of the subtype ran")
	TEST_ASSERT(!at("gated", off), "a when() that is false skips its after_init()")

/// Loaded with a map: every probe's after_init(0) runs when the frame closes, after every probe of the load has initialized.
/datum/unit_test/dq_after_init/mapload

/datum/unit_test/dq_after_init/mapload/Run()
	var/list/made = list()
	SSatoms.map_loader_begin("dq_after_init_test")
	for(var/i in 1 to 5)
		made += new /obj/effect/dq_after_init_probe(dq_containment_floor())
	SSatoms.map_loader_stop("dq_after_init_test")
	for(var/obj/effect/dq_after_init_probe/probe as anything in made)
		own(probe)
		GLOB.dq_after_init_probes += probe
	SSatoms.InitializeAtoms(made.Copy())
	var/last_init = 0
	var/first_after = length(GLOB.dq_after_init_log) + 1
	for(var/obj/effect/dq_after_init_probe/probe as anything in made)
		last_init = max(last_init, at("init", probe))
		first_after = min(first_after, at("after", probe) || first_after)
		TEST_ASSERT_EQUAL(probe.saw_mapload, TRUE, "A.mapload is TRUE for a map-loaded instance")
		TEST_ASSERT_EQUAL(probe.saw_initialized, length(made), "every probe of the load had initialized when its after_init() ran")
	TEST_ASSERT(last_init < first_after, "no after_init() ran before the last probe of the frame initialized")

/// A positive delay is an after() on the holder: it waits, fires once, and is the holder's (dropped with it).
/datum/unit_test/dq_after_init/delayed

/datum/unit_test/dq_after_init/delayed/Run()
	scheduler_test_begin()
	var/obj/item/dq_forms_timer/timer = new(dq_containment_floor())
	TEST_ASSERT(after_pending(timer, "after_init:1"), "the timer is armed on the holder")
	TEST_ASSERT_EQUAL(timer.fired, 0, "it waits")
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(timer.fired, 1, "it fired once")
	var/obj/item/dq_forms_timer/dropped = new(dq_containment_floor())
	qdel(dropped)
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(dropped.fired, 0, "deleting the holder dropped its after_init() timer")
	qdel(timer)
	scheduler_test_end()

// ---- plain datums: armed by make() once the whole New() chain has returned ----

/// A plain datum with a param and an after_init(0); its subtype's New() writes after ..().
/datum/dq_after_init_datum
	var/dq_ai_level = 1
	/// What the handler saw.
	var/seen_level = null
	var/seen_tail = null
	var/seen_mapload = null
	var/ran = 0
	/// Written by the subtype's New() after ..(): the handler must see it.
	var/tail = FALSE

CAPABILITIES(/datum/dq_after_init_datum)
	param(nameof(dq_ai_level), num(0, 100))
	after_init(0, then(PROC_REF(after_init_ran)))

/datum/dq_after_init_datum/proc/after_init_ran(datum/act/timer/A)
	ran++
	seen_level = dq_ai_level
	seen_tail = tail
	seen_mapload = A.mapload

/datum/dq_after_init_datum/tailed/New()
	..()
	tail = TRUE

/// A positive delay on a plain datum: an after() on it from make().
/datum/dq_after_init_datum_delayed
	var/fired = 0

CAPABILITIES(/datum/dq_after_init_datum_delayed)
	after_init(2 SECONDS, then(PROC_REF(fire)))

/datum/dq_after_init_datum_delayed/proc/fire(datum/act/timer/A)
	fired++

/// make() arms a plain datum's after_init(0) once, before it returns: after the params and after every New() body.
/datum/unit_test/dq_after_init/plain_datum

/datum/unit_test/dq_after_init/plain_datum/Run()
	var/datum/dq_after_init_datum/tailed/D = make(/datum/dq_after_init_datum/tailed, dq_ai_level = 7)
	TEST_ASSERT_EQUAL(D.ran, 1, "make() ran the after_init(0) exactly once")
	TEST_ASSERT_EQUAL(D.seen_level, 7, "the handler saw the make() param")
	TEST_ASSERT_EQUAL(D.seen_tail, TRUE, "the handler ran after the subtype's New() code after ..()")
	TEST_ASSERT_EQUAL(D.seen_mapload, FALSE, "A.mapload is FALSE for a plain datum")
	var/datum/dq_after_init_datum/plain = make(/datum/dq_after_init_datum)
	TEST_ASSERT_EQUAL(plain.ran, 1, "without params it runs once too")
	TEST_ASSERT_EQUAL(plain.seen_level, 1, "the default stands when make() gave none")
	qdel(D)
	qdel(plain)

/// A positive delay waits on the datum's own clock, fires once and is dropped with it.
/datum/unit_test/dq_after_init/plain_datum_delayed

/datum/unit_test/dq_after_init/plain_datum_delayed/Run()
	scheduler_test_begin()
	var/datum/dq_after_init_datum_delayed/D = make(/datum/dq_after_init_datum_delayed)
	TEST_ASSERT(after_pending(D, "after_init:1"), "the timer is armed on the datum")
	TEST_ASSERT_EQUAL(D.fired, 0, "it waits")
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(D.fired, 1, "it fired once")
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(D.fired, 1, "and only once")
	var/datum/dq_after_init_datum_delayed/dropped = make(/datum/dq_after_init_datum_delayed)
	qdel(dropped)
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(dropped.fired, 0, "deleting the datum dropped its timer")
	qdel(D)
	scheduler_test_end()

/// A bare new of a plain datum that declares after_init() never runs it and is reported (the lint catches a literal one at compile time).
/datum/unit_test/dq_after_init/plain_datum_bare_new

/datum/unit_test/dq_after_init/plain_datum_bare_new/Run()
	var/list/old_capture = GLOB.declare_report_capture
	GLOB.declare_report_capture = list()
	var/path = /datum/dq_after_init_datum
	var/datum/dq_after_init_datum/D = new path
	var/list/reports = GLOB.declare_report_capture
	GLOB.declare_report_capture = old_capture
	TEST_ASSERT_EQUAL(D.ran, 0, "a bare new does not arm it")
	var/found = FALSE
	for(var/message in reports)
		if(findtext(message, "make(/datum/dq_after_init_datum)"))
			found = TRUE
	TEST_ASSERT(found, "the bare new was reported: [jointext(reports, "; ")]")
	qdel(D)
