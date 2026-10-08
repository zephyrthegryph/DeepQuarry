/// The record edit modal's checked argument list reaches a real typed request, not a computed op handler.
/datum/unit_test/dq_e2/machinery_record_arg_fields
	abstract_type = /datum/unit_test/dq_e2/machinery_record_arg_fields
	var/console_type
	var/record_slot = "active2"

/datum/unit_test/dq_e2/machinery_record_arg_fields/run_gate()
	var/mob/living/simple_mob/e0_fixture/user = actor()
	var/obj/machinery/computer/console = allocate(console_type, get_turf(user))
	console.set_grid_power(TRUE)
	console.set_broken_condition(FALSE)
	var/datum/data/record/record = allocate(/datum/data/record)
	record.fields["sex"] = "Original sex"
	record.fields["species"] = "Original species"
	set_var(GLOB.data_core, "general", list(record))
	set_var(GLOB.data_core, "medical", list(record))
	set_var(GLOB.data_core, "security", list(record))
	set_var(console, "authenticated", TRUE)
	rel_set(console, record_slot, record)
	var/list/passed = list("field" = "sex", "value" = "Window sex")
	test_ui(user, console, "modal:edit", list("arguments" = passed))
	var/datum/prompt/choice/pick = SSrequests.open_for(user)
	TEST_ASSERT(istype(pick), "The real modal action opens a choice request for sex")
	TEST_ASSERT_EQUAL(pick.question, "Please select new sex:", "The supplied field selects the exact original question")
	TEST_ASSERT_EQUAL(pick.default, "Window sex", "The choice default is the passed window value, not the current record")
	TEST_ASSERT_EQUAL(length(pick.choices), length(all_genders_text_list), "The field retains the complete original choice list")
	for(var/gender in all_genders_text_list)
		TEST_ASSERT(gender in pick.choices, "The request retains the actual supported sex choice [gender]")
	TEST_ASSERT_EQUAL(record.fields["sex"], "Original sex", "Opening the choice changes no record")
	test_answer(user, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(record.fields["sex"], "Original sex", "Cancelling the real request preserves the record")
	test_ui(user, console, "modal:edit", list("arguments" = list("field" = "species", "value" = "Window species")))
	var/datum/prompt/text/text = SSrequests.open_for(user)
	TEST_ASSERT(istype(text), "The actual modal selects a text request for species")
	TEST_ASSERT_EQUAL(text.question, "Please input new species:", "The text field retains its original mapped question")
	TEST_ASSERT_EQUAL(text.default, "Window species", "The nested argument supplies the actual text default")
	TEST_ASSERT_EQUAL(record.fields["species"], "Original species", "Opening text does not change the record")
	test_answer(user, "Replacement species")
	TEST_ASSERT_EQUAL(record.fields["species"], "Replacement species", "A real request answer reaches the original modal effect")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Answering closes the actual request chain")

/datum/unit_test/dq_e2/machinery_record_arg_fields/medical
	console_type = /obj/machinery/computer/med_data

/datum/unit_test/dq_e2/machinery_record_arg_fields/security
	console_type = /obj/machinery/computer/secure_data

/datum/unit_test/dq_e2/machinery_record_arg_fields/skills
	console_type = /obj/machinery/computer/skills
	record_slot = "active1"
