/proc/a()
	try
		foo()
	catch(var/exception/e)
		dq_report_caught(e, "ctx")
	catch
		throw e
	catch(e)
		stack_trace("x")
	catch(e)
		CRASH("x")
	catch(e) world.Error(e)
	catch(e)
		world.Error(e)
	catch(e)
		report_caught(e, "x")
	catch(e)
		log_runtime("x")
	catch(e)
		Fail("x")
	catch(e)
		TEST_FAIL("x")
	catch(e)
		pass()
	catch
		return
	catch(e) return
	catch(e)
	foo()
	catch(e)  // trailing comment
		pass()
	catch(e)
		// throw e (a comment only)
		pass()
	catch(e)
		log_x ("space before the paren")
	catch(e)
		var/s = "throw e in a string still counts"
	catch (e)
		throw e
	catch (e)
		pass()
	catch(e) {
		pass()
	}
	catch(e) { throw e }
	catchy()
	catch_all(x)
	var/catch = 1
	/catch_this()
	x = "catch(e)"
	// catch(e)
	catch(e) // a comment
		report_caught(
			e, "multi line")
	catch(e)

		throw e
	catch(e)
		x = 1

		throw e
	catch(e)
        spaces()
	catch(e)
	    four_spaces_are_deeper_than_a_tab()
	catch(e)
	   three_spaces_are_not()
	catch(e)
		if(x)
			throw e
	catch(e)
		pass()
		pass()
	return
	catch(e) log_x("inline log")
	catch(e) report_caught(e, "inline report")
	catch(e) throw e
	catch(e) pass() // throw e
	catch(e) x = "a // throw e"
	catch(e) x = 'a // throw e'
	catch(e) x = "a \" // throw e"
	catch(e) x = 'it\'s // throw e'
	throw
	catch(e)
		rethrow()
	catch(e)
		dq_report_caughtx(e)
	catch(e)
		xreport_caught(e)
	catch(e)
		xlog_runtime("not a word boundary")
	catch(e)
		log_(e)
	catch(e)
		Failure(e)
	catch(e)
		TEST_FAILED(e)
	catch(e)
		stack_trace (e)
	catch(e)
		CRASH (e)
	catch(e)
		world.Error (e)
	catch(e)
		world . Error(e)
	catch(e)
		world.Errors(e)
