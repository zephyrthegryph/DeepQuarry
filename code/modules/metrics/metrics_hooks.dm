// The game's side of the metrics events: what a round, a ticket or an admin verb reports.
// The call sites are single points in the framework (the ticket list, the admin verb
// dispatcher, the ticker, world/Error, the MC tick record); the event shape lives here.

// ---------------------------------------------------------------- rounds

/hook/roundend/proc/metrics_round_end()
	var/datum/system/server_metrics/M = SSserver_metrics
	if(M?.wants_recording())
		METRICS_EVENT(METRICS_EVENT_ROUND, "end", "", "", "round ended", list(
			"players" = length(GLOB.clients),
			"duration_s" = round((REALTIMEOFDAY - GLOB.round_start_time) / (1 SECONDS)),
			"runtimes" = GLOB.total_runtimes,
		))
		M.flush()
	return TRUE

// ---------------------------------------------------------------- tickets

/// Whether this ticket's "opened" event has been recorded (so a later return to the active
/// list is a reopen).
/datum/ticket/var/tmp/metrics_opened = FALSE

/// Records the ticket's state change: opened/reopened/closed/resolved from the ticket list,
/// "handled" when staff take it. Age is seconds since it was opened.
/datum/ticket/proc/metrics_state_event(change)
	if(!change)
		switch(state)
			if(AHELP_ACTIVE)
				change = metrics_opened ? "reopened" : "opened"
				metrics_opened = TRUE
			if(AHELP_CLOSED)
				change = "closed"
			if(AHELP_RESOLVED)
				change = "resolved"
	METRICS_EVENT(METRICS_EVENT_TICKET, change, "[id]", initiator_ckey, name, list(
		"level" = level ? "admin" : "mentor",
		"handler" = handler_ckey,
		"age_s" = round((world.time - opened_at) / (1 SECONDS)),
	))
