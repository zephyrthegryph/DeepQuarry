// Legacy carrier identities and global forwards share the actual time-engine state.
/datum/unit_test/dq_time_foundation_compatibility/Run()
	var/datum/time_scheduler/sched = time_scheduler()
	TEST_ASSERT(istype(sched, /datum/om/scheduler), "The real compatibility factory preserves downstream scheduler extensions")
	TEST_ASSERT_EQUAL(om_scheduler(), sched, "Both scheduler entry points return the same active instance")
	var/datum/owner = timer_global_owner()
	TEST_ASSERT(istype(owner, /datum/om/global_owner), "The timer owner factory preserves downstream owned relation declarations")
	TEST_ASSERT_EQUAL(om_global_owner(), owner, "Both timer-owner entry points return the same actual owner")
	var/datum/probe = allocate(/datum)
	var/datum/scheduler_record/record = scheduler_record_of(probe)
	TEST_ASSERT(istype(record), "The real engine allocates a scheduler record")
	TEST_ASSERT_EQUAL(om_rec_of(probe), record, "The legacy record entry point returns the actual engine record")
	var/handle = entity_handle(probe)
	TEST_ASSERT_EQUAL(om_handle(probe), handle, "Legacy handle capture shares the same generation-qualified identity")
	TEST_ASSERT_EQUAL(resolve_handle(handle), probe, "The canonical resolver returns the original live datum")
	TEST_ASSERT_EQUAL(om_resolve(handle), probe, "The legacy resolver returns the original live datum")
	qdel(probe)
	TEST_ASSERT_NULL(resolve_handle(handle), "Deleting the original datum invalidates the canonical handle")
	TEST_ASSERT_NULL(om_resolve(handle), "Deleting the original datum invalidates the legacy handle too")
	var/datum/relation_definition/relation = allocate(/datum/om/relation)
	var/datum/relation_edge/edge = relation.make_edge()
	TEST_ASSERT(istype(edge, /datum/om/edge), "A real link carrier still passes existing legacy edge identity checks")
	qdel(edge)
	var/datum/scheduled_behaviour/inline/inline_callback = definition_registry().make_inline_behaviour()
	TEST_ASSERT(istype(inline_callback, /datum/om/behaviour/inline), "A synthesized callback still passes existing profiler inline identity checks")
	qdel(inline_callback)
	var/datum/definition_registry/registry = definition_registry()
	TEST_ASSERT(registry.ui_behaviour, "The presentation adapter supplies an actual registered delivery behaviour")
	TEST_ASSERT_EQUAL(registry.ui_behaviour, registry.behaviour_by_type[/datum/om/behaviour/internal/ui_push], "The engine retains the concrete presentation behaviour identity used by existing sessions")

// Legacy child branches retain their inherited engine behaviour, even though their old
// path parents are compatibility aliases rather than their actual runtime parents.
/datum/unit_test/dq_time_foundation_definition_families/Run()
	var/list/families = list(
		/datum/om/behaviour/inline = /datum/scheduled_behaviour,
		/datum/om/behaviour/sleeper/timed = /datum/scheduled_behaviour,
		/datum/om/event/before = /datum/definition_event,
		/datum/om/check/fact = /datum/requirement_definition,
		/datum/om/check/combinator = /datum/requirement_definition,
		/datum/om/decl = /datum/definition_bundle,
		/datum/om/relation/slot = /datum/relation_definition)
	for(var/path in families)
		var/datum/core_definition/definition = allocate(path)
		TEST_ASSERT(istype(definition, families[path]), "[path] remains in its actual engine definition family")
		TEST_ASSERT(istype(definition, /datum/core_definition), "[path] retains the common definition fields and methods")
	var/datum/om_test_entity/actor = allocate(/datum/om_test_entity)
	var/datum/requirement_definition/condition = allocate(/datum/om/check/test_enabled)
	var/datum/requirement_definition/combinator/combination = allocate(/datum/om/check/combinator)
	combination.op = "all"
	combination.parts = list(condition)
	TEST_ASSERT_EQUAL(definition_check_get(combination), combination, "Canonical check lookup accepts the actual legacy child instance")
	TEST_ASSERT_NULL(combination.why_not(actor, null), "An enabled actor satisfies the inherited all-of check")
	actor.enabled = FALSE
	TEST_ASSERT(combination.why_not(actor, null), "Disabling the actor makes the same inherited check refuse")

/datum/unit_test/om/dq_time_foundation_clock_callback

/datum/unit_test/om/dq_time_foundation_clock_callback/run_om(list/made)
	var/datum/om_test_entity/bio/owner = entity(made, /datum/om_test_entity/bio)
	TEST_ASSERT_EQUAL(owner.timer_clock(), CLOCK_BIO, "The migrated virtual callback selects the owner's biological clock")
	TEST_ASSERT_EQUAL(owner.om_timer_clock(), owner.timer_clock(), "The old callback entry point forwards to the actual overridden clock")
	var/id = after(owner, 2 SECONDS, TYPE_PROC_REF(/datum/om_test_entity, timer_hit), with = list("foundation-clock"))
	TEST_ASSERT(timer_pending(owner, id), "The callback timer is actually armed")
	scheduler_advance(1)
	hold(owner, STAT_SUSPENDED, TRUE, owner)
	scheduler_advance(3)
	TEST_ASSERT_NULL(owner.log, "The overridden clock prevents delivery while its owner is suspended")
	TEST_ASSERT(timer_pending(owner, id), "Suspension preserves rather than cancels the real timer")
	release(owner, STAT_SUSPENDED, owner)
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(length(owner.log), 1, "Resuming the owner delivers the callback exactly once")
	TEST_ASSERT_EQUAL(owner.log[1], "foundation-clock", "The resumed timer invokes its original callback and argument")
	TEST_ASSERT(!timer_pending(owner, id), "The delivered timer is removed from the engine timer store")

/datum/unit_test/dq_time_foundation_lists_are_private/Run()
	var/datum/definition_registry/first_registry = allocate(/datum/definition_registry)
	var/datum/definition_registry/second_registry = allocate(/datum/definition_registry)
	first_registry.errors += "first registry only"
	first_registry.behaviour_by_type[/datum/scheduled_behaviour] = "first"
	TEST_ASSERT_EQUAL(length(first_registry.errors), 1, "Registry construction supplies an immediately writable error list")
	TEST_ASSERT_EQUAL(length(second_registry.errors), 0, "Registry error mutations remain private to the instance")
	TEST_ASSERT_NULL(second_registry.behaviour_by_type[/datum/scheduled_behaviour], "Registry definition indexes are distinct mutable lists")
	var/datum/scheduler_type_table/first_table = allocate(/datum/scheduler_type_table)
	var/datum/scheduler_type_table/second_table = allocate(/datum/scheduler_type_table)
	first_table.self_grants += list("fixture", "first")
	TEST_ASSERT_EQUAL(length(first_table.self_grants), 2, "Compiled table construction supplies a writable grant table")
	TEST_ASSERT_EQUAL(length(second_table.self_grants), 0, "Compiled type tables do not share their mutable grant lists")

/datum/unit_test/dq_time_foundation_null_providers/Run()
	var/datum/time_scheduler_factory/saved_factory = GLOB.time_scheduler_factory
	var/datum/native_watch_provider/saved_native = GLOB.native_watch_provider
	var/datum/construction_stage_provider/saved_construction = GLOB.construction_stage_provider
	var/datum/transfer_feedback_provider/saved_feedback = GLOB.transfer_feedback_provider
	GLOB.time_scheduler_factory = null
	GLOB.native_watch_provider = null
	GLOB.construction_stage_provider = null
	GLOB.transfer_feedback_provider = null
	var/datum/time_scheduler_factory/factory
	var/datum/native_watch_provider/native
	var/datum/construction_stage_provider/construction
	var/datum/transfer_feedback_provider/feedback
	var/datum/time_scheduler/made_scheduler
	var/reused = FALSE
	var/legacy_scheduler = FALSE
	var/exception/problem
	try
		factory = time_scheduler_factory()
		native = native_watch_provider()
		construction = construction_stage_provider()
		feedback = transfer_feedback_provider()
		reused = factory == time_scheduler_factory() && native == native_watch_provider() && construction == construction_stage_provider() && feedback == transfer_feedback_provider()
		made_scheduler = factory.make()
		legacy_scheduler = istype(made_scheduler, /datum/om/scheduler)
	catch(var/exception/error)
		problem = error
	// Restore before assertions (TEST_ASSERT returns on failure) and before deleting probes.
	GLOB.time_scheduler_factory = saved_factory
	GLOB.native_watch_provider = saved_native
	GLOB.construction_stage_provider = saved_construction
	GLOB.transfer_feedback_provider = saved_feedback
	var/created = factory && native && construction && feedback && made_scheduler
	for(var/datum/probe in list(made_scheduler, factory, native, construction, feedback))
		if(probe)
			qdel(probe)
	TEST_ASSERT_NULL(problem, "An early provider lookup from null globals completes without a runtime")
	TEST_ASSERT(created, "Every uninitialized provider accessor creates its actual provider")
	TEST_ASSERT(reused, "Repeated lookups retain the same provider identities")
	TEST_ASSERT(legacy_scheduler, "The lazily created real factory preserves downstream scheduler subtype behaviour")
