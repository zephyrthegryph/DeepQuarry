#define JOIN_TEST_INPUT "input"
#define JOIN_TEST_OUTPUT "output"

/// Actual IC char/list pin contracts and computed circuit output; no fake pins.
/datum/unit_test/round2_circuit_jointext_empty_delimiter/Run()
	var/obj/item/integrated_circuit/circuit = allocate(/obj/item/integrated_circuit/list/jointext, test_floor())
	TEST_ASSERT_EQUAL(circuit.get_pin_data(JOIN_TEST_INPUT, 2), ",", "Actual join circuit retains its comma default")
	TEST_ASSERT_EQUAL(circuit.get_pin_data(JOIN_TEST_INPUT, 3), 1, "Actual start index default is one")
	TEST_ASSERT_EQUAL(circuit.get_pin_data(JOIN_TEST_INPUT, 4), 0, "Actual end default selects the entire list")
	circuit.set_pin_data(JOIN_TEST_INPUT, 1, list("A", "B"))
	circuit.do_work()
	TEST_ASSERT_EQUAL(circuit.get_pin_data(JOIN_TEST_OUTPUT, 1), "A,B", "Actual default computation joins both real list entries with comma")
	circuit.set_pin_data(JOIN_TEST_INPUT, 2, null)
	TEST_ASSERT_NULL(circuit.get_pin_data(JOIN_TEST_INPUT, 2), "Actual char pin accepts a null delimiter")
	circuit.do_work()
	TEST_ASSERT_NULL(circuit.get_pin_data(JOIN_TEST_OUTPUT, 1), "Explicit null delimiter preserves original no-result behavior")
	circuit.set_pin_data(JOIN_TEST_INPUT, 2, "")
	TEST_ASSERT_EQUAL(circuit.get_pin_data(JOIN_TEST_INPUT, 2), "", "Actual char pin preserves an explicitly empty string")
	circuit.do_work()
	TEST_ASSERT_EQUAL(circuit.get_pin_data(JOIN_TEST_OUTPUT, 1), "AB", "Actual empty delimiter concatenates real list entries instead of incorrectly returning null")
	circuit.set_pin_data(JOIN_TEST_INPUT, 2, ",")
	circuit.do_work()
	TEST_ASSERT_EQUAL(circuit.get_pin_data(JOIN_TEST_OUTPUT, 1), "A,B", "Actual nonempty delimiter still produces comma-separated output after empty input")

#undef JOIN_TEST_INPUT
#undef JOIN_TEST_OUTPUT
