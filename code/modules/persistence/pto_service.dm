////////////////////////////////
//// Paid Leave Subsystem
//// For tracking how much department PTO time players have accured
////////////////////////////////

// Paid leave system (was SSpersist): PTO accrues every 15 minutes on the background lane.
SYSTEM_DEF(persist)
	name = "Persist"
	periodic_runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	/// Accrual period; must match the every() interval below.
	var/accrual_interval = 15 MINUTES
	var/list/currentrun = list()
	var/list/query_stack = list()
	/// TRUE while an accrual pass that ran out of budget waits to resume.
	VAR_PRIVATE/accrual_resuming = FALSE

/datum/system/persist/reactions()
	. = ..()
	. += every(15 MINUTES, PROC_REF(accrue_pto), when = PROC_REF(work_ready), lane = LANE_BACKGROUND)

/datum/system/persist/proc/accrue_pto(dt)
	var/done = update_department_hours(accrual_resuming)
	accrual_resuming = !done
	return done ? STEP_DONE : STEP_YIELD

// Do PTO Accruals. Returns FALSE when the pass ran out of budget and must resume.
/datum/system/persist/proc/update_department_hours(resumed = FALSE)
	if(!CONFIG_GET(flag/time_off))
		return TRUE

	if(!SSdbcore.IsConnected())
		src.currentrun.Cut()
		return TRUE
	if(!resumed)
		src.currentrun = REGISTRY_COPY(REGISTRY_HUMANS)
		src.currentrun += REGISTRY_COPY(REGISTRY_SILICONS)

	//cache for sanic speed (lists are references anyways)
	var/list/currentrun = src.currentrun
	var/list/query_stack = src.query_stack
	while (length(currentrun))
		var/mob/M = currentrun[length(currentrun)]
		currentrun.len--
		if (QDELETED(M) || !istype(M) || !M.mind || !M.client || TICKS2DS(M.client.inactivity) > accrual_interval)
			continue

		// Try and detect job and department of mob
		var/datum/job/J = detect_job(M)
		if(!istype(J) || !J.pto_type || !J.timeoff_factor)
			if (KERNEL_OVER_BUDGET)
				return FALSE
			continue

		var/department_earning = J.pto_type

		// Determine special PTO types and convert properly
		if(department_earning == PTO_CYBORG)
			if(isrobot(M))
				var/mob/living/silicon/robot/C = M
				if(C?.module?.pto_type)
					department_earning = C.module.pto_type
			if(department_earning == PTO_CYBORG)
				if (KERNEL_OVER_BUDGET)
					return FALSE
				continue

		// Update client whatever
		var/client/C = M.client
		var/wait_in_hours = accrual_interval / (1 HOUR)
		var/pto_factored = wait_in_hours * J.timeoff_factor
		if(J.playtime_only)
			pto_factored = 0
		LAZYINITLIST(C.department_hours)
		LAZYINITLIST(C.play_hours)
		var/dept_hours = C.department_hours
		var/play_hours = C.play_hours
		if(isnum(dept_hours[department_earning]))
			dept_hours[department_earning] += pto_factored
		else
			dept_hours[department_earning] = pto_factored

		// If they're earning PTO they must be in a useful job so are earning playtime in that department
		if(J.timeoff_factor > 0)
			if(isnum(play_hours[department_earning]))
				play_hours[department_earning] += wait_in_hours
			else
				play_hours[department_earning] = wait_in_hours

		// Cap it
		dept_hours[department_earning] = min(CONFIG_GET(number/pto_cap), dept_hours[department_earning])

		// Okay we figured it out, lets update database!
		var/sql_ckey = sql_sanitize_text(C.ckey)
		var/sql_dpt = sql_sanitize_text(department_earning)
		var/sql_bal = text2num("[C.department_hours[department_earning]]")
		var/sql_total = text2num("[C.play_hours[department_earning]]")
		var/list/entry = list(
			"ckey" = sql_ckey,
			"department" = sql_dpt,
			"hours" = sql_bal,
			"total_hours" = sql_total
		)
		query_stack += list(entry)

		if (KERNEL_OVER_BUDGET)
			return FALSE

	if(length(query_stack))
		SSdbcore.mass_insert_io(null, format_table_name("vr_player_hours"), query_stack.Copy(), "ON DUPLICATE KEY UPDATE hours = VALUES(hours), total_hours = VALUES(total_hours)") // io_job: returns at once
		query_stack.Cut()
	return TRUE


// This proc tries to find the job datum of an arbitrary mob.
/datum/system/persist/proc/detect_job(mob/M)
	// Records are usually the most reliable way to get what job someone is.
	var/datum/data/record/R = find_general_record("name", M.real_name)
	if(R) // We found someone with a record.
		var/recorded_rank = R.fields["real_rank"]
		if(recorded_rank)
			. = SSjob.get_job(recorded_rank)
			if(.) return

	// They have a custom title, aren't crew, or someone deleted their record, so we need a fallback method.
	// Let's check the mind.
	if(M.mind && M.mind.assigned_role)
		. = SSjob.get_job(M.mind.assigned_role)
