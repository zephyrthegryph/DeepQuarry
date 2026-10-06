// Reactions on the kernel (code/datums/reactions/work.dm): every() as scheduled work with `when`, members= and
// per-instance enrolment, urgent crossings through kernel_urgent(), notice cost accounting, the pooled notice,
// typed relations and the event coalescing defaults.

// ---------------------------------------------------------------- fixtures

/// A holder with a per-instance every() gated by a var, and a second one ordered after the first.
/datum/rxw_pump
	var/on = FALSE
	var/list/steps = list()
	var/list/late = list()

/datum/rxw_pump/reactions()
	. = ..()
	. += every(1 SECONDS, PROC_REF(pump_step), when = nameof(on))
	. += every(2 SECONDS, PROC_REF(pump_late), after = /datum/rxw_pump, budget = 3)

/datum/rxw_pump/proc/pump_step(dt)
	steps += dt

/datum/rxw_pump/proc/pump_late(dt)
	late += dt

/// The proc form of `when`.
/datum/rxw_gate
	var/open = FALSE
	var/list/steps = list()

/datum/rxw_gate/reactions()
	. = ..()
	. += every(1 SECONDS, PROC_REF(gate_step), when = PROC_REF(gate_open))

/datum/rxw_gate/proc/gate_open()
	return open

/datum/rxw_gate/proc/gate_step(dt)
	steps += dt

/// A capability whose holders an every(members = ...) runs for.
/datum/capability/dx_test/rxw

/// An atom holding that capability, and declaring the every() that runs per holder of it.
/obj/cap_fixture/rxw_holder
	var/ticks = 0

/obj/cap_fixture/rxw_holder/capabilities()
	. = ..()
	. += dx_test_cap(/datum/capability/dx_test/rxw, "rxw")

/obj/cap_fixture/rxw_holder/reactions()
	. = ..()
	. += every(1 SECONDS, PROC_REF(holder_tick), members = /datum/capability/dx_test/rxw)

/obj/cap_fixture/rxw_holder/proc/holder_tick(dt)
	ticks += dt

/// Typed relations.
/datum/rxw_typed
	var/datum/partner
	var/list/others
	var/datum/kept

/datum/rxw_typed/relations()
	. = ..()
	. += rel_one(nameof(partner), /datum/rxw_typed)
	. += rel_many(nameof(others), /datum/rxw_typed)
	. += rel_one(nameof(kept), /datum/rxw_typed, kind = RELK_OWNED)

/datum/rxw_stranger

/// A fresh injected time for run_item(): each call is far past the last, so an item shared between tests (one per
/// reaction signature) is always due.
/proc/rxw_now()
	var/static/base = 0
	base = max(base, world.time) + 1000
	return base

/// The work item of the `index`-th reaction of `kind` in D's type table.
/proc/rxw_item(datum/D, kind, index = 1)
	var/datum/rx_table/T = rx_table_of(D)
	var/list/reactions
	switch(kind)
		if(RXN_EVERY)
			reactions = T.everys
		if(RXN_NOTICE)
			reactions = T.notices
		if(RXN_CROSS)
			reactions = list()
			for(var/read in T.crosses)
				reactions += T.crosses[read]
	var/datum/reaction/R = reactions[index]
	return R.work

// ---------------------------------------------------------------- every() on the kernel

/// every() is a kernel work item: interval, phase, ordering, budget and `when` are the item's, and a holder runs only
/// while its `when` var is truthy.
/datum/unit_test/dx_work_every_when

/datum/unit_test/dx_work_every_when/Run()
	var/datum/controller/kernel/K = kernel()
	rx_boot_register(/datum/rxw_pump)
	var/datum/rxw_pump/P = new // enrolled by being made: its type declares every()
	var/datum/work_item/reaction/W = rxw_item(P, RXN_EVERY, 1)
	var/datum/work_item/reaction/late = rxw_item(P, RXN_EVERY, 2)
	TEST_ASSERT(W && late, "both every() reactions registered work items")
	TEST_ASSERT_EQUAL(K.work_by_key[W.key], W, "the item is on the kernel under its key")
	TEST_ASSERT_EQUAL(W.interval, 1 SECONDS, "the interval is the item's")
	TEST_ASSERT_EQUAL(W.run_when, "on", "`when` is the item's run_when")
	TEST_ASSERT_EQUAL(late.budget, 3, "the budget is the item's")
	TEST_ASSERT(late.after && (/datum/rxw_pump in late.after), "the after edge is the item's")
	var/list/phase_items = K.items_of_phase(KERNEL_PHASE_P)
	TEST_ASSERT(phase_items.Find(W) && phase_items.Find(W) < phase_items.Find(late), "the after edge orders it behind the first item")

	var/now = rxw_now()
	K.run_item(W, WORK_TEST_LIMIT, now)
	TEST_ASSERT_EQUAL(length(P.steps), 0, "`when` false: the handler does not run")
	P.on = TRUE
	K.run_item(W, WORK_TEST_LIMIT, now + 10)
	TEST_ASSERT_EQUAL(length(P.steps), 1, "`when` true: it runs on the holder")
	TEST_ASSERT_EQUAL(P.steps[1], 10, "with dt since the last run")
	K.run_item(W, WORK_TEST_LIMIT, now + 15)
	TEST_ASSERT_EQUAL(length(P.steps), 1, "and not before the interval")
	K.run_item(W, WORK_TEST_LIMIT, now + 20)
	TEST_ASSERT_EQUAL(length(P.steps), 2, "again when due")
	qdel(P)

/// The proc form of `when`.
/datum/unit_test/dx_work_every_when_proc

/datum/unit_test/dx_work_every_when_proc/Run()
	var/datum/controller/kernel/K = kernel()
	rx_boot_register(/datum/rxw_gate)
	var/datum/rxw_gate/G = new
	var/datum/work_item/reaction/W = rxw_item(G, RXN_EVERY)
	var/now = rxw_now()
	K.run_item(W, WORK_TEST_LIMIT, now)
	TEST_ASSERT_EQUAL(length(G.steps), 0, "the gate proc answers FALSE: no run")
	G.open = TRUE
	K.run_item(W, WORK_TEST_LIMIT, now + 10)
	TEST_ASSERT_EQUAL(length(G.steps), 1, "and TRUE: it runs")
	qdel(G)

/// A subtype that re-declares an every() handler replaces the inherited declaration: one item per (owner type,
/// handler), and an instance is enrolled in its own type's item only, so the handler never runs twice.
/datum/rxw_pump/quick

/datum/rxw_pump/quick/reactions()
	. = ..()
	. += every(0.5 SECONDS, PROC_REF(pump_step), when = nameof(on))

/datum/unit_test/dx_work_every_redeclared

/datum/unit_test/dx_work_every_redeclared/Run()
	rx_boot_register(/datum/rxw_pump)
	var/datum/rxw_pump/base = new
	var/datum/rxw_pump/quick/fast = new
	var/datum/rx_table/base_table = rx_table_of(base)
	var/datum/rx_table/fast_table = rx_table_of(fast)
	var/steps_in_base = 0
	for(var/datum/reaction/R as anything in base_table.everys)
		if(R.handler == TYPE_PROC_REF(/datum/rxw_pump, pump_step))
			steps_in_base++
	var/steps_in_fast = 0
	var/datum/work_item/reaction/fast_item
	for(var/datum/reaction/R as anything in fast_table.everys)
		if(R.handler == TYPE_PROC_REF(/datum/rxw_pump, pump_step))
			steps_in_fast++
			fast_item = R.work
	TEST_ASSERT_EQUAL(steps_in_base, 1, "the base type declares the handler once")
	TEST_ASSERT_EQUAL(steps_in_fast, 1, "the subtype's re-declaration replaced the inherited one, not added to it")
	var/datum/work_item/reaction/base_item
	for(var/datum/reaction/R as anything in base_table.everys)
		if(R.handler == TYPE_PROC_REF(/datum/rxw_pump, pump_step))
			base_item = R.work
	TEST_ASSERT(fast_item != base_item, "the subtype owns its own work item")
	TEST_ASSERT_EQUAL(fast_item.interval, 0.5 SECONDS, "with the subtype's interval")
	TEST_ASSERT(member_is(base_item.enrol_key, base) && !member_is(base_item.enrol_key, fast), "the base instance is in the base item only")
	TEST_ASSERT(member_is(fast_item.enrol_key, fast) && !member_is(fast_item.enrol_key, base), "the subtype instance is in its own item only")
	qdel(base)
	qdel(fast)

/// A memberless every() runs once per live instance of the declaring type, and an instance that is destroyed
/// leaves the membership store and the item's execution tokens.
/datum/unit_test/dx_work_every_per_instance

/datum/unit_test/dx_work_every_per_instance/Run()
	var/datum/controller/kernel/K = kernel()
	rx_boot_register(/datum/rxw_pump)
	var/datum/rxw_pump/A = new
	var/datum/rxw_pump/B = new
	A.on = TRUE
	B.on = TRUE
	var/datum/work_item/reaction/W = rxw_item(A, RXN_EVERY)
	TEST_ASSERT(W.enrol_key, "a memberless every() on a holder has an enrolment key")
	TEST_ASSERT(member_is(W.enrol_key, A) && member_is(W.enrol_key, B), "each instance joined the key")
	var/now = rxw_now()
	K.run_item(W, WORK_TEST_LIMIT, now + 10)
	TEST_ASSERT(length(A.steps) == 1 && length(B.steps) == 1, "it ran once per instance")
	TEST_ASSERT_NULL(A.rx, "enrolment needs no reaction state")
	qdel(A)
	TEST_ASSERT(!member_is(W.enrol_key, A), "a destroyed instance left the store, even without reaction state")
	TEST_ASSERT(!length(member_keys(A)), "it holds no key")
	TEST_ASSERT(!W.last_at || !(A in W.last_at), "and no execution token")
	K.run_item(W, WORK_TEST_LIMIT, now + 20)
	TEST_ASSERT_EQUAL(length(B.steps), 2, "the survivor keeps running")
	TEST_ASSERT_EQUAL(members_total(W.enrol_key), 1, "one member is left")
	qdel(B)
	TEST_ASSERT_EQUAL(members_total(W.enrol_key), 0, "none once both are gone")

/// members = <capability>: holders that existed before the item registered are backfilled, later ones join at init,
/// and the handler runs on each holder.
/datum/unit_test/dx_work_every_members_backfill

/datum/unit_test/dx_work_every_members_backfill/Run()
	var/datum/controller/kernel/K = kernel()
	var/cap = /datum/capability/dx_test/rxw
	var/obj/cap_fixture/rxw_holder/H = allocate(/obj/cap_fixture/rxw_holder)
	var/datum/work_item/reaction/W = rxw_item(H, RXN_EVERY)
	TEST_ASSERT_EQUAL(W.members, cap, "the item sweeps the capability's holders")
	TEST_ASSERT(K.cap_wanted[cap], "the capability is wanted")
	TEST_ASSERT(member_is(cap, H), "the holder is a member")
	// Force the backfill path: drop the membership, then backfill.
	member_purge(H)
	TEST_ASSERT(!member_is(cap, H), "no longer a member")
	TEST_ASSERT(kernel_backfill_members(cap) >= 1, "the backfill joined an existing holder")
	TEST_ASSERT(member_is(cap, H), "it is a member again")
	TEST_ASSERT_EQUAL(kernel_backfill_members(cap), 0, "a second backfill finds nothing new")
	var/obj/cap_fixture/rxw_holder/H2 = allocate(/obj/cap_fixture/rxw_holder)
	TEST_ASSERT(member_is(cap, H2), "a holder created later joins at init")
	var/now = rxw_now()
	K.run_item(W, WORK_TEST_LIMIT, now + 10)
	TEST_ASSERT(H.ticks > 0 && H2.ticks > 0, "the handler ran on each holder")
	qdel(H2)
	TEST_ASSERT(!member_is(cap, H2), "a destroyed holder left")

// ---------------------------------------------------------------- on_cross(urgent = TRUE)

/// An urgent crossing is requested with kernel_urgent(): deduped per holder, the latest band carried, delivered
/// by the kernel's U phase as handler(band, previous_band).
/datum/unit_test/dx_work_cross_urgent

/datum/unit_test/dx_work_cross_urgent/Run()
	var/datum/controller/kernel/K = kernel()
	var/datum/rx_fx/F = allocate(/datum/rx_fx)
	K.run_urgent(WORK_TEST_LIMIT) // nothing left over from another test
	var/datum/work_item/reaction/W = rxw_item(F, RXN_CROSS)
	TEST_ASSERT(W.urgent && !W.event, "an urgent on_cross is an urgent work item")
	F.set_level(5)
	F.set_level(15)
	TEST_ASSERT_EQUAL(length(F.crossings), 0, "the crossing waits for the kernel: nothing delivered synchronously")
	TEST_ASSERT_EQUAL(length(K.urgent_queue), 1, "one request is pending")
	var/deduped = K.urgent_deduped
	F.set_level(25)
	TEST_ASSERT_EQUAL(K.urgent_deduped, deduped + 1, "a second crossing of the same holder is deduped")
	TEST_ASSERT_EQUAL(length(K.urgent_queue), 1, "still one request")
	K.run_urgent(WORK_TEST_LIMIT)
	TEST_ASSERT_EQUAL(length(F.crossings), 1, "one delivery")
	TEST_ASSERT_EQUAL(F.crossings[1][1], 2, "carrying the latest band")
	TEST_ASSERT_EQUAL(F.crossings[1][2], 0, "and the band it left")
	TEST_ASSERT(!F.rx.cross_pending, "the carried band is cleared")
	// Back where it started before the kernel ran: nothing to deliver.
	F.set_level(3)
	F.set_level(25)
	K.run_urgent(WORK_TEST_LIMIT)
	TEST_ASSERT_EQUAL(length(F.crossings), 1, "a round trip inside one request delivers nothing")

/// A holder destroyed with a request pending does not run it.
/datum/unit_test/dx_work_cross_urgent_destroyed

/datum/unit_test/dx_work_cross_urgent_destroyed/Run()
	var/datum/controller/kernel/K = kernel()
	K.run_urgent(WORK_TEST_LIMIT) // nothing left over from another test
	var/datum/rx_fx/F = new
	F.set_level(5)
	F.set_level(15)
	TEST_ASSERT_EQUAL(length(K.urgent_queue), 1, "pending")
	var/dropped = K.urgent_dropped
	qdel(F)
	K.run_urgent(WORK_TEST_LIMIT)
	TEST_ASSERT_EQUAL(K.urgent_dropped, dropped + 1, "the request for a destroyed holder is dropped")
	TEST_ASSERT_EQUAL(length(K.urgent_queue), 0, "and nothing is left")

// ---------------------------------------------------------------- on_notice cost accounting

/// A notice reaction is an event item: delivery stays synchronous and in order, its cost is the item's.
/datum/unit_test/dx_work_notice_cost

/datum/unit_test/dx_work_notice_cost/Run()
	var/datum/controller/kernel/K = kernel()
	var/datum/rx_fx/F = allocate(/datum/rx_fx)
	var/datum/work_item/reaction/W = rxw_item(F, RXN_NOTICE)
	TEST_ASSERT(W.event, "a notice reaction registers an event item")
	TEST_ASSERT(!(W in K.items_of_phase(KERNEL_PHASE_P)), "which the kernel never schedules")
	var/runs = W.runs
	PUBLISH_LEGACY(F, /datum/notice/rx_fx, 1)
	PUBLISH_LEGACY(F, /datum/notice/rx_fx, 2)
	TEST_ASSERT_EQUAL(jointext(F.notes, ","), "1,2", "delivered in publish order")
	TEST_ASSERT_EQUAL(W.runs, runs + 2, "each delivery is counted on the item")
	TEST_ASSERT(W.total_ms >= 0 && !isnull(W.cost), "with its cost")
	var/list/metrics = K.metrics()
	TEST_ASSERT_EQUAL(metrics["work"][W.key]["runs"], W.runs, "metrics() reports the item")
	TEST_ASSERT(K.work_cost_of(W.owner_type)["runs"] >= 2, "and the owner's summed cost")

/// The notice is a pooled datum: taken, filled, released after delivery, its fields reset.
/datum/unit_test/dx_work_notice_pooled

/datum/unit_test/dx_work_notice_pooled/Run()
	var/datum/notice/rx_fx/N = take_notice(/datum/notice/rx_fx, 9)
	TEST_ASSERT(N.is_pooled(), "a notice is a /datum/pooled")
	TEST_ASSERT_EQUAL(N.pool_state, POOL_STATE_TAKEN, "taken")
	TEST_ASSERT_EQUAL(N.mark, 9, "filled by take_notice")
	N.source = N
	N.release()
	TEST_ASSERT_NULL(N.mark, "the base reset the field")
	TEST_ASSERT_NULL(N.source, "and the base fields")

// ---------------------------------------------------------------- typed relations

/// rel_one / rel_many store their type; a write of anything else is refused and reported.
/datum/unit_test/dx_rel_typed_writes

/datum/unit_test/dx_rel_typed_writes/Run()
	var/datum/rxw_typed/A = allocate(/datum/rxw_typed)
	var/datum/rxw_typed/B = allocate(/datum/rxw_typed)
	var/datum/rxw_stranger/S = allocate(/datum/rxw_stranger)
	var/list/entry = own_table_of(A).entries[nameof(A.partner)]
	TEST_ASSERT_EQUAL(entry[OWNE_TYPE], /datum/rxw_typed, "the declaration recorded its type")
	var/list/capture = list()
	set_global("dq_lifecycle_report_capture", capture)
	TEST_ASSERT_NULL(rel_link(A, nameof(A.partner), S), "a rel_one write of another type is refused")
	TEST_ASSERT_NULL(A.partner, "and nothing was written")
	TEST_ASSERT_NULL(rel_link(A, nameof(A.others), S), "a rel_many write of another type is refused")
	TEST_ASSERT(!length(A.others), "and nothing was added")
	TEST_ASSERT_NULL(rel_set(A, nameof(A.kept), S), "an owned write of another type is refused")
	TEST_ASSERT_NULL(A.kept, "and nothing was owned")
	set_global("dq_lifecycle_report_capture", null)
	TEST_ASSERT_EQUAL(length(capture), 3, "each refusal was reported: [json_encode(capture)]")
	TEST_ASSERT(findtext(capture[1], "declared"), "naming the declaration")
	TEST_ASSERT_EQUAL(rel_link(A, nameof(A.partner), B), B, "the declared type is written")
	TEST_ASSERT_EQUAL(A.partner, B, "as the value")
	TEST_ASSERT_EQUAL(rel_link(A, nameof(A.others), B), B, "and added to a list view")
	TEST_ASSERT(B in A.others, "as a member")
	rel_link(A, nameof(A.partner), null)
	TEST_ASSERT_NULL(A.partner, "null clears a typed view")
