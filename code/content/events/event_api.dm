// The event system's API (code/modules/events/event_service.dm declares the system).
//
//   SSevents.request_round_end_report()   the round end prints the event report
//   events_*()                            reads (code/contracts/accessors/accessors.dm)

/// The round end report of the events that ran is wanted.
/datum/system/events/proc/request_round_end_report()
	report_at_round_end = TRUE
