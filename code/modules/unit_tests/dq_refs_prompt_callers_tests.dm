// The prompt callers whose captured objects are declared relations (doc/rewrite/proposals/reference_storage.md): each test opens the prompt the
// way the real caller does (the same argument expressions) and checks the relation took the value, which a refused rel_set would not.

/datum/refs_prompt_probe_owner

/datum/refs_prompt_probe_owner/proc/handled(datum/act/request/A)
	return OP_OK

/datum/unit_test/dq_refs_prompt_caller
	abstract_type = /datum/unit_test/dq_refs_prompt_caller

/datum/unit_test/dq_refs_prompt_caller/Run()
	test_driver_begin()
	test_prompts_reset()
	run_caller()
	GLOB.test_prompts = null
	test_driver_end()

/datum/unit_test/dq_refs_prompt_caller/proc/run_caller()
	return

/datum/unit_test/dq_refs_prompt_caller/proc/asker()
	return allocate(/mob/living/simple_mob/e0_fixture)

/datum/unit_test/dq_refs_prompt_caller/proc/probe_owner()
	return new /datum/refs_prompt_probe_owner

/datum/unit_test/dq_refs_prompt_caller/proc/last_prompt()
	return GLOB.test_prompts[length(GLOB.test_prompts)]

/// uplink_item/abstract/announcements/fake_centcom/extra_args()
/datum/unit_test/dq_refs_prompt_caller/uplink_announcement_payment

/datum/unit_test/dq_refs_prompt_caller/uplink_announcement_payment/run_caller()
	var/mob/user = asker()
	var/obj/item/uplink/uplink = allocate(/obj/item/uplink)
	var/datum/refs_prompt_probe_owner/owner = probe_owner()
	open_request(owner, /datum/prompt/text/uplink_announcement, TYPE_PROC_REF(/datum/refs_prompt_probe_owner, handled), answerer = user, payment_uplink = uplink, payment_operator = user, question = "Enter your announcement title.", title = "Announcement Title")
	var/datum/prompt/text/uplink_announcement/ask = last_prompt()
	TEST_ASSERT_EQUAL(ask.payment_uplink, uplink, "the paying uplink is held by the prompt")
	TEST_ASSERT_EQUAL(ask.payment_operator, user, "and so is its operator")

/// The viral extrapolator's disease, isolation and symptom questions (extrapolator.dm).
/datum/unit_test/dq_refs_prompt_caller/extrapolator_targets

/datum/unit_test/dq_refs_prompt_caller/extrapolator_targets/run_caller()
	var/mob/user = asker()
	var/obj/item/pen/target = allocate(/obj/item/pen)
	var/datum/affliction/contagion/anxiety/disease = new
	var/datum/refs_prompt_probe_owner/owner = probe_owner()
	var/list/diseases = list(disease)
	open_request(owner, /datum/prompt/choice/viral_extrapolator/disease, TYPE_PROC_REF(/datum/refs_prompt_probe_owner, handled), answerer = user, choices = list("anxiety"), default = "anxiety", extraction_target = target, target_expected = !isnull(target))
	var/datum/prompt/choice/viral_extrapolator/disease/chosen = last_prompt()
	TEST_ASSERT_EQUAL(chosen.extraction_target, target, "the disease question holds the target")
	open_request(owner, /datum/prompt/choice/viral_extrapolator/isolate_what, TYPE_PROC_REF(/datum/refs_prompt_probe_owner, handled), answerer = user, extraction_target = target, target_expected = !isnull(target), extraction_disease = diseases[1], disease_expected = !isnull(diseases[1]))
	var/datum/prompt/choice/viral_extrapolator/isolate_what/isolate = last_prompt()
	TEST_ASSERT_EQUAL(isolate.extraction_target, target, "the isolation question holds the target")
	TEST_ASSERT_EQUAL(isolate.extraction_disease, disease, "and the disease")
	open_request(owner, /datum/prompt/choice/viral_extrapolator/symptom, TYPE_PROC_REF(/datum/refs_prompt_probe_owner, handled), answerer = user, choices = list("none"), default = "none", extraction_target = target, target_expected = !isnull(target))
	var/datum/prompt/choice/viral_extrapolator/symptom/symptom = last_prompt()
	TEST_ASSERT_EQUAL(symptom.extraction_target, target, "the symptom question holds the target")
	qdel(disease)

/// The admin Spawn Mail recipient step (mail.dm).
/datum/unit_test/dq_refs_prompt_caller/mail_recipient

/datum/unit_test/dq_refs_prompt_caller/mail_recipient/run_caller()
	var/mob/user = asker()
	var/mob/living/carbon/human/recipient = allocate(/mob/living/carbon/human)
	var/datum/refs_prompt_probe_owner/owner = probe_owner()
	open_request(owner, /datum/prompt/choice/admin_mail, TYPE_PROC_REF(/datum/refs_prompt_probe_owner, handled), answerer = user, title = "Spawn mail", question = "Spawn mail at location or in the shuttle?", choices = list("Location", "Shuttle"), buttons = TRUE, chosen = "/obj/item/pen", recipient = recipient, recipient_expected = !isnull(recipient))
	var/datum/prompt/choice/admin_mail/ask = last_prompt()
	TEST_ASSERT_EQUAL(ask.recipient, recipient, "the mail question holds its recipient")

/// The freight certification questions of a sales lot (sales_lots.dm).
/datum/unit_test/dq_refs_prompt_caller/freight_shipment

/datum/unit_test/dq_refs_prompt_caller/freight_shipment/run_caller()
	var/mob/user = asker()
	var/obj/structure/closet/crate/crate = allocate(/obj/structure/closet/crate)
	var/datum/refs_prompt_probe_owner/owner = probe_owner()
	var/list/freight_answers = list()
	open_request(owner, /datum/prompt/choice/freight_certification, TYPE_PROC_REF(/datum/refs_prompt_probe_owner, handled), answerer = user, shipment = crate, freight_answers = freight_answers, answer_key = "value", question = "Value?", title = "Freight valuation", choices = list("Continue", "Cancel"))
	var/datum/prompt/choice/freight_certification/ask = last_prompt()
	TEST_ASSERT_EQUAL(ask.shipment, crate, "the choice question holds the crate")
	open_request(owner, /datum/prompt/text/freight_certification, TYPE_PROC_REF(/datum/refs_prompt_probe_owner, handled), answerer = user, shipment = crate, freight_answers = freight_answers, answer_key = "destination", question = "Who is this shipment consigned to?", title = "Freight ledger", default = "External buyer")
	var/datum/prompt/text/freight_certification/text_ask = last_prompt()
	TEST_ASSERT_EQUAL(text_ask.shipment, crate, "the text question holds the crate")

/// The petrification consent questions (petrification.dm).
/datum/unit_test/dq_refs_prompt_caller/petrification_operator

/datum/unit_test/dq_refs_prompt_caller/petrification_operator/run_caller()
	var/mob/operator = asker()
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human)
	var/datum/refs_prompt_probe_owner/owner = probe_owner()
	open_request(owner, /datum/prompt/choice/petrify_consent, TYPE_PROC_REF(/datum/refs_prompt_probe_owner, handled), answerer = target, operator = operator, question = "You have been selected as a petrification target.")
	var/datum/prompt/choice/petrify_consent/ask = last_prompt()
	TEST_ASSERT_EQUAL(ask.operator, operator, "the consent question holds the operator")
