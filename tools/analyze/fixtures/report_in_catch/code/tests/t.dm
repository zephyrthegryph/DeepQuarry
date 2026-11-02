/proc/test_fx()
	try
		test_fx()
	catch(var/exception/e)
		stack_trace("tests are exempt [e]")
