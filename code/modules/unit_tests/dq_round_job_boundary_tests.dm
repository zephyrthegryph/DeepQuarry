/datum/unit_test/dq_ticker_boundary/Run()
	var/datum/system/ticker/original_owner = SSticker
	var/datum/system/ticker/original_registered = system_table()[/datum/system/ticker]
	defer_cleanup(src, PROC_REF(restore_boundary_owner), original_owner, original_registered)
	set_global("coalesce_runs", GLOB.coalesce_runs)
	var/datum/system/ticker/ticker = allocate(/datum/system/ticker)
	restore_boundary_owner(original_owner, original_registered)
	TEST_ASSERT_EQUAL(SSticker, original_owner, "The local fixture must preserve the running system owner")
	TEST_ASSERT_EQUAL(system_table()[/datum/system/ticker], original_registered, "The local fixture must preserve the registered system owner")
	ticker.request_immediate_start(TRUE)
	TEST_ASSERT(ticker.start_immediately, "Immediate start must set the ticker's real lobby flag")
	ticker.request_immediate_start(FALSE)
	TEST_ASSERT(!ticker.start_immediately, "Cancelling immediate start must clear that flag")
	ticker.request_round_ending(ADMIN_FORCE_END_ROUND)
	TEST_ASSERT_EQUAL(ticker.force_ending, ADMIN_FORCE_END_ROUND, "Forced round ending must preserve its reason")
	ticker.set_round_end_delay(TRUE)
	TEST_ASSERT(ticker.delay_end, "The benchmark/admin delay must affect the actual ticker")
	ticker.toggle_round_end_delay()
	TEST_ASSERT(!ticker.delay_end, "The admin toggle must clear an existing delay")
	ticker.toggle_round_end_delay()
	TEST_ASSERT(ticker.delay_end, "A second toggle must restore the delay")
	var/datum/mind/mind = allocate(/datum/mind)
	ticker.remember_mind(mind)
	TEST_ASSERT(mind in ticker.minds, "A spawned character's actual mind must join the ticker roster")
	qdel(mind)
	TEST_ASSERT(!(mind in ticker.minds), "A deleted mind must leave the declared roster relation")

/datum/unit_test/dq_job_boundary/Run()
	var/datum/system/job/original_owner = SSjob
	var/datum/system/job/original_registered = system_table()[/datum/system/job]
	defer_cleanup(src, PROC_REF(restore_boundary_owner), original_owner, original_registered)
	var/datum/system/job/jobs = allocate(/datum/system/job)
	restore_boundary_owner(original_owner, original_registered)
	TEST_ASSERT_EQUAL(SSjob, original_owner, "The local fixture must preserve the running system owner")
	TEST_ASSERT_EQUAL(system_table()[/datum/system/job], original_registered, "The local fixture must preserve the registered system owner")
	var/datum/job/job = allocate(/datum/job)
	set_var(jobs, "occupations", list(job))
	set_var(jobs, "occupations_by_name", list("boundary-job" = job))
	var/list/ordered = jobs.occupation_snapshot()
	var/list/choices = jobs.job_choices()
	TEST_ASSERT_EQUAL(ordered[1], job, "The timeclock must receive the original job in catalog order")
	TEST_ASSERT_EQUAL(choices["boundary-job"], job, "Respawn choices must retain the title-to-datum mapping")
	ordered.Cut()
	choices.Cut()
	TEST_ASSERT(jobs.has_job_title("boundary-job"), "Editing chooser snapshots must not remove a registered title")
	TEST_ASSERT_EQUAL(jobs.occupation_snapshot()[1], job, "Editing the timeclock snapshot must not remove its job")
	TEST_ASSERT(!jobs.has_job_title("unknown"), "Unknown security-record ranks must remain invalid")
	set_var(jobs, "restricted_keys", list("boundary-job" = list("restricted-player")))
	TEST_ASSERT(jobs.has_restricted_keys(), "The camp-protection table must report its actual membership")
	TEST_ASSERT(jobs.is_restricted_key("boundary-job", "restricted-player"), "A restricted player must be refused for the recorded job")
	TEST_ASSERT(!jobs.is_restricted_key("boundary-job", "different-player"), "Other players must retain access to that job")
	TEST_ASSERT(!jobs.is_restricted_key("other-job", "restricted-player"), "The restriction must remain job-specific")
	jobs.record_shift_keys("boundary-job", list("first-player"))
	jobs.record_shift_keys("boundary-job", list("second-player"))
	TEST_ASSERT_EQUAL(length(jobs.shift_keys["boundary-job"]), 2, "Repeated shift recording must append, rather than replace, the played keys")
	TEST_ASSERT_EQUAL(jobs.shift_keys["boundary-job"][1], "first-player", "The first shift key must retain its original order")
	TEST_ASSERT_EQUAL(jobs.shift_keys["boundary-job"][2], "second-player", "The next shift key must append in order")
	var/datum/department/department = allocate(/datum/department)
	set_var(jobs, "department_datums", list("boundary-department" = department))
	TEST_ASSERT_EQUAL(jobs.department_count(), 1, "Department iteration must use the real registry size")
	TEST_ASSERT_EQUAL(jobs.department_name_at(1), "boundary-department", "Funding events must retain the registry's ordered name keys")
	TEST_ASSERT_EQUAL(jobs.department_by_name("boundary-department"), department, "Access defaults must use the registered department datum")

/datum/unit_test/dq_emergency_boundary/Run()
	var/datum/system/emergency_shuttle/original_owner = SSemergency_shuttle
	var/datum/system/emergency_shuttle/original_registered = system_table()[/datum/system/emergency_shuttle]
	defer_cleanup(src, PROC_REF(restore_boundary_owner), original_owner, original_registered)
	var/datum/system/emergency_shuttle/emergency = allocate(/datum/system/emergency_shuttle)
	restore_boundary_owner(original_owner, original_registered)
	TEST_ASSERT_EQUAL(SSemergency_shuttle, original_owner, "The local fixture must preserve the running system owner")
	TEST_ASSERT_EQUAL(system_table()[/datum/system/emergency_shuttle], original_registered, "The local fixture must preserve the registered system owner")
	TEST_ASSERT(!emergency.is_evacuation(), "An untouched emergency controller must still represent transfer, not evacuation")
	emergency.set_auto_recall(TRUE)
	TEST_ASSERT(emergency.auto_recall, "Automatic recall requests must reach the owner's actual policy")
	emergency.set_auto_recall(FALSE)
	TEST_ASSERT(!emergency.auto_recall, "Disabling automatic recall must clear the same policy")
	emergency.toggle_calls_denied()
	TEST_ASSERT(emergency.deny_shuttle, "The admin toggle must block calls")
	emergency.toggle_calls_denied()
	TEST_ASSERT(!emergency.deny_shuttle, "The next admin toggle must allow calls again")
	emergency.edit_launch_countdown(3)
	TEST_ASSERT_EQUAL(emergency.launch_time, world.time + 3 SECONDS, "Editing must retain the deadline's seconds-to-world-clock conversion")
	TEST_ASSERT(!emergency.wait_for_launch, "Editing a countdown must not arm an unarmed launch")
	emergency.make_launch_irrevocable()
	TEST_ASSERT_EQUAL(emergency.launch_time, 0, "The end-round path must preserve its zero launch deadline")
	TEST_ASSERT(!emergency.has_arrival_countdown(), "A controller without a ferry must not advertise an arrival countdown")
	TEST_ASSERT(!emergency.is_moving_or_warming_up(), "A controller without a ferry must not block late antagonist spawning")


/// A local SYSTEM_DEF clone must not replace the running world owner, even if construction fails.
/datum/unit_test/dq_ticker_boundary/proc/restore_boundary_owner(datum/system/ticker/owner, datum/system/ticker/registered)
	SSticker = owner
	var/list/table = system_table()
	if(registered)
		table[/datum/system/ticker] = registered
	else
		table -= /datum/system/ticker

/// A local SYSTEM_DEF clone must not replace the running world owner, even if construction fails.
/datum/unit_test/dq_job_boundary/proc/restore_boundary_owner(datum/system/job/owner, datum/system/job/registered)
	SSjob = owner
	var/list/table = system_table()
	if(registered)
		table[/datum/system/job] = registered
	else
		table -= /datum/system/job

/// A local SYSTEM_DEF clone must not replace the running world owner, even if construction fails.
/datum/unit_test/dq_emergency_boundary/proc/restore_boundary_owner(datum/system/emergency_shuttle/owner, datum/system/emergency_shuttle/registered)
	SSemergency_shuttle = owner
	var/list/table = system_table()
	if(registered)
		table[/datum/system/emergency_shuttle] = registered
	else
		table -= /datum/system/emergency_shuttle
