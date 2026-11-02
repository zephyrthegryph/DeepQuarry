/proc/fx()
	try
		stack_trace("in the try is fine")
	catch(var/exception/e)
		stack_trace("bad [e]")
		try
			fx()
		catch(var/exception/f)
			CRASH("bad [f]")
	stack_trace("after the block is fine")
	try
		fx()
	catch(var/exception/g)
		dq_report_caught(g, "fine")
		throw g
