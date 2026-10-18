// NTSL statements after the dead object-statement path was removed (relations wave 4): an assignment and a call of a script-defined function
// run, and the interpreter never writes a datum's vars by name from a script.

/datum/unit_test/dq_ntsl_assignment_and_call

/datum/unit_test/dq_ntsl_assignment_and_call/Run()
	var/code = {"$x = 2; $x += 3;"}
	var/datum/n_scriptOptions/nS_Options/options = new()
	var/datum/n_Scanner/nS_Scanner/scanner = new(code, options)
	var/list/tokens = scanner.Scan()
	var/datum/n_Parser/nS_Parser/parser = new(tokens, options)
	var/datum/node/BlockDefinition/GlobalBlock/program = parser.Parse()
	TEST_ASSERT(!length(scanner.errors) && !length(parser.errors), "the script parses: [json_encode(scanner.errors + parser.errors)]")
	var/datum/n_Interpreter/I = new(program)
	I.persist = 1 // keep the global scope after the run, as the telecomms compiler does
	I.Run()
	TEST_ASSERT_EQUAL(I.GetVar("$x"), 5, "an assignment and a compound assignment run")
	qdel(I)
