// soft_assert(condition, message) — CHOMP-era helper.
//
// Like ASSERT() but doesn't crash. Logs a stack_trace + world log when the
// condition is false. Use when an invariant violation is recoverable but worth
// flagging for postmortem.
/proc/soft_assert(condition, message = "soft_assert failed")
	if(condition)
		return
	stack_trace(message)
	log_world("soft_assert: [message]")
