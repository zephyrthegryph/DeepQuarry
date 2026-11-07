// An idle world settles: the on_change marks a boot leaves are worked off and nothing re-marks them, and a stable APC hears nothing
// (doc: perf/idle-drain-storm; the 11-07 idle server held 35k marked turfs and logged a spent budget thousands of times).

/// The marked (holder, hook) pairs now, as "type handler" -> count.
/proc/idle_mark_census()
	. = list()
	var/alist/marks = GLOB.hook_change_pending
	if(!marks)
		return
	for(var/handle in marks)
		var/datum/E = handle_get(handle)
		if(QDELETED(E))
			continue
		for(var/datum/hook/H as anything in marks[handle])
			var/kind = "[E.type] [H.entry ? copytext(H.entry.sig, 1, 80) : H.type]"
			.[kind] = (.[kind] || 0) + 1

/proc/idle_census_text(list/census, limit = 8)
	var/list/rows = list()
	for(var/kind in census)
		rows += "[kind] x[census[kind]]"
		if(length(rows) >= limit)
			break
	return jointext(rows, "; ")

/// What the boot left marked is worked off by the drain and an idle world marks nothing again (meaningful with --full-map).
/datum/unit_test/dq_idle_marks_settle

/datum/unit_test/dq_idle_marks_settle/Run()
	test_driver_begin()
	var/list/boot = idle_mark_census()
	var/boot_total = 0
	for(var/kind in boot)
		boot_total += boot[kind]
	log_world("IDLE_SETTLE: [boot_total] on_change mark(s) after the boot: [idle_census_text(boot, 12)]")
	var/ticks = 0
	while(GLOB.hook_change_pending && ticks++ < 400)
		test_time(1 SECONDS)
	var/list/left = idle_mark_census()
	TEST_ASSERT(!GLOB.hook_change_pending, "marks still pending after [ticks] seconds: [idle_census_text(left)]")
	test_time(30 SECONDS)
	var/list/idle = idle_mark_census()
	test_driver_end()
	TEST_ASSERT(!length(idle), "an idle world re-marked on_change hooks: [idle_census_text(idle)]")

/// A raised alarm does not sort and rewrite the handler's whole list (a brownout raises one per APC); the order is made when a reader asks for it.
/datum/unit_test/dq_alarm_raise_defers_order

/datum/unit_test/dq_alarm_raise_defers_order/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/datum/alarm_handler/handler = allocate(/datum/alarm_handler)
	var/list/sources = list()
	for(var/i in 1 to 6)
		var/obj/item/source = allocate(/obj/item, locate(T.x + i, T.y, T.z))
		sources += source
		TEST_ASSERT(handler.triggerAlarm(source, source), "alarm [i] is new")
	TEST_ASSERT_EQUAL(length(handler.alarms), 6, "every raised alarm is held")
	TEST_ASSERT(!handler.alarms_in_order, "raising did not sort the list")
	TEST_ASSERT_EQUAL(length(handler.visible_alarms()), 6, "a reader sees all six")
	TEST_ASSERT(handler.alarms_in_order, "the reader put the list in order")
	var/obj/item/again = sources[1]
	TEST_ASSERT(!handler.triggerAlarm(again, again), "raising the same origin again is not a new alarm")
	TEST_ASSERT(handler.alarms_in_order, "and leaves the order alone")
	for(var/obj/item/source as anything in sources)
		handler.clearAlarm(source, source)
	TEST_ASSERT_EQUAL(length(handler.alarms), 0, "every alarm cleared")
