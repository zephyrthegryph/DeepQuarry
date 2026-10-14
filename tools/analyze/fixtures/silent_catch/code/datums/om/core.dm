/datum/om/core
	catch(e)
		log_runtime("only a log")
	catch(e)
		Fail("only a fail")
	catch(e)
		TEST_FAIL("only a test fail")
	catch(e)
		dq_report_caught(e, "ctx")
	catch(e)
		throw e
	catch(e)
		stack_trace("x")
	catch(e)
		pass()
	catch(e) // ALLOW(silent_catch): the strict dirs take the annotation as well
		pass()
