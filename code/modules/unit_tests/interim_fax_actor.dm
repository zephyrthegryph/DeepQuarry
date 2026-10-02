/// Observe actor forwarding and run the real request helper through a cancelled confirmation.
/obj/machinery/photocopier/faxmachine/interim_request_actor
	var/request_actor_ref
	var/request_count = 0
	var/confirmation_count = 0

/obj/machinery/photocopier/faxmachine/interim_request_actor/request_roles(mob/living/L)
	request_actor_ref = L ? REF(L) : null
	request_count++
	return ..()

/obj/machinery/photocopier/faxmachine/interim_request_actor/om_rerun_ask(mob/user, key, proc_name, list/proc_args, prompt, list/fields)
	if(key == "k109")
		confirmation_count++
	return ..()

/datum/unit_test/interim_fax_request_actor_cancel/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/photocopier/faxmachine/interim_request_actor/fax = allocate(/obj/machinery/photocopier/faxmachine/interim_request_actor, T)
	var/cache_key = "[REF(fax)]:[/obj/machinery/photocopier/faxmachine/proc/request_roles]"
	set_global("om_rerun_answers", GLOB.om_rerun_answers.Copy())
	set_global("last_fax_role_request", null)
	// Inject the real re-run helper's first confirmation answer. No is final and cannot transmit.
	GLOB.om_rerun_answers[cache_key] = list("k109" = "No")
	fax.interaction_request_roles(actor, null, null)
	TEST_ASSERT_EQUAL(fax.request_count, 1, "the real interaction reaches the request helper")
	TEST_ASSERT_EQUAL(fax.request_actor_ref, REF(actor), "the helper receives the actual actor without ambient usr")
	TEST_ASSERT_EQUAL(fax.confirmation_count, 1, "the real parent helper reaches its first confirmation")
	TEST_ASSERT_NULL(GLOB.last_fax_role_request, "cancelled confirmation cannot update the transmission cooldown")
	TEST_ASSERT(!fax.sendcooldown, "cancelled staffing request does not begin a fax send cooldown")
