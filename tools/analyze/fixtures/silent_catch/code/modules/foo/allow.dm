/proc/b()
	catch(e) // ALLOW(silent_catch): a missing file is an expected failure here
		pass()
	// ALLOW(silent_catch): a missing file is an expected failure here
	catch(e)
		pass()
	catch(e)
		// ALLOW(silent_catch): the first line of the body counts as the same system
		pass()
	catch(e)
		pass()
		// ALLOW(silent_catch): the second line of the body does not count at all
	catch(e)
		pass() // ALLOW(silent_catch): the same line as the first body line counts
	catch(e) // ALLOW(silent_catch)
		pass()
	catch(e) // ALLOW(other): a reason for some other lint entirely
		pass()
	catch(e) // ALLOW(other, silent_catch): a reason that names two lints at once
		pass()
	x = 1 // ALLOW(silent_catch): not a comment-only line so it keeps nothing below
	catch(e)
		pass()
	catch(e)
		report_caught(e, "x") // ALLOW(silent_catch): reports so this annotation keeps nothing
	catch(e) // ALLOW(silent_catch): reports so this annotation keeps nothing either
		throw e
	// ALLOW(silent_catch): reports so this annotation keeps nothing as well
	catch(e)
		throw e
	catch(e)
		/* ALLOW(silent_catch): the block form on the first line of the body */ pass()
	/* ALLOW(silent_catch): the block form is not a comment-only // line above */
	catch(e)
		pass()
	catch(e) /* ALLOW(silent_catch): the block form on the catch line itself */
		pass()
	catch(e)
		pass()
	// ALLOW(silent_catch): two lines above does not count for the catch below

	catch(e)
		pass()
	catch(e)
		// ALLOW(silent_catch): the first body line is also the line above for the second
		// ALLOW(silent_catch): so one annotation can be asked about twice over
		pass()
