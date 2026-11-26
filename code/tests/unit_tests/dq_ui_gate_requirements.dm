// The window buttons that used to refuse with a bare `return FALSE` inside their handler (ui_gate()) now refuse through needs() on the op,
// with a reason the presser reads.

/// The accounts terminal refuses every control but the card slot without a card.
/datum/unit_test/dq_ui_gate_requirements/accounts_need_card

/datum/unit_test/dq_ui_gate_requirements/accounts_need_card/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/machinery/account_database/D = allocate(/obj/machinery/account_database, test_floor())
	var/datum/op_result/R = op_ui_act(H, D, "create_account", list())
	TEST_ASSERT(!test_op_committed(R), "no card: Create Account is refused")
	TEST_ASSERT(findtext(reason_text(R?.reason), "ID card"), "the refusal asks for a card (got '[reason_text(R?.reason)]')")

/// The telescience console refuses its pad controls with no telepad linked.
/datum/unit_test/dq_ui_gate_requirements/telescience_needs_pad

/datum/unit_test/dq_ui_gate_requirements/telescience_needs_pad/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/machinery/computer/telescience/C = allocate(/obj/machinery/computer/telescience, test_floor())
	if(C.telepad())
		return // a pad on the test map was linked: nothing to refuse
	var/datum/op_result/R = op_ui_act(H, C, "recal", list())
	TEST_ASSERT(!test_op_committed(R), "no pad: Recalibrate is refused")
	TEST_ASSERT(findtext(reason_text(R?.reason), "telepad"), "the refusal names the missing telepad (got '[reason_text(R?.reason)]')")
