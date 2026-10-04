// Keep unrelated default software out of the actual implanted NIF fixture.
/obj/item/nif/interim_size_actor
	starting_software = null

/datum/nifsoft/sizechange/interim_cost_probe
	a_drain = 2

/obj/interim_nif_size_click
	var/datum/nifsoft/sizechange/software

/obj/interim_nif_size_click/Click(location, control, params)
	software.activate()

/datum/unit_test/dq_eg2/interim_nif_size_actor
	abstract_type = /datum/unit_test/dq_eg2/interim_nif_size_actor

/datum/unit_test/dq_eg2/interim_nif_size_actor/proc/install_size(mob/living/carbon/human/human)
	human.mind_initialize()
	own(human.mind)
	SSticker?.minds -= human.mind
	var/obj/item/nif/implant = allocate(/obj/item/nif/interim_size_actor, run_loc_floor_bottom_left)
	var/obj/item/organ/brain = human.organ_in(O_BRAIN)
	TEST_ASSERT(brain, "the real human has a brain to determine implantation location")
	var/obj/item/organ/external/site = human.get_organ(brain.parent_organ)
	TEST_ASSERT(site, "the actual brain-parent organ exists")
	implant.forceMove(site)
	TEST_ASSERT(implant.implant(human), "the actual implant procedure succeeds inside its required organ")
	EXPIRY_SET(implant, install_done, -1 DAY, CLOCK_WORLD)
	implant.handle_install()
	TEST_ASSERT_EQUAL(implant.stat, NIF_WORKING, "actual elapsed calibration reaches the real working state")
	TEST_ASSERT_EQUAL(human.nif, implant, "implantation sets the actual reciprocal human relation")
	var/datum/nifsoft/sizechange/software = allocate(/datum/nifsoft/sizechange/interim_cost_probe, implant)
	TEST_ASSERT_EQUAL(implant.imp_check(NIF_SIZECHANGE), software, "the actual constructor installs software into its true positional slot")
	return software

/datum/unit_test/dq_eg2/interim_nif_size_actor/answer/run_gate()
	var/mob/living/carbon/human/human = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/nifsoft/sizechange/software = install_size(human)
	var/obj/item/nif/implant = software.nif()
	var/obj/interim_nif_size_click/probe = allocate(/obj/interim_nif_size_click, run_loc_floor_bottom_left)
	rel_set(probe, nameof(probe.software), software)
	var/nutrition = human.nutrition
	var/power = implant.power_usage
	var/bystander_size = bystander.size_multiplier
	TEST_ASSERT(human.size_multiplier != 1.5, "the real desired size differs from the owner's current size")
	km_synthetic_click(bystander, probe)
	TEST_ASSERT(SSrequests.open_for(human), "actual activation opens a real native number request")
	var/datum/prompt/number/ask = SSrequests.open_for(human)
	TEST_ASSERT(istype(ask), "actual activation produces a typed native number request")
	TEST_ASSERT_EQUAL(ask.answerer, human, "the real implant owner answers despite an unrelated native click actor")
	TEST_ASSERT_EQUAL(ask.subject, implant, "the prompt captures the actual original implant")
	TEST_ASSERT_EQUAL(human.nutrition, nutrition - 2, "parent activation charges the real owner exactly once before asking")
	TEST_ASSERT_EQUAL(implant.power_usage, power + 2, "actual parent activation registers its real active power cost")
	test_time(0.1 SECONDS)
	TEST_ASSERT_EQUAL(software.active, FALSE, "the real scheduled pulse deactivates without waiting for an answer")
	TEST_ASSERT_EQUAL(implant.power_usage, power, "actual deactivation balances active power exactly once")
	test_answer(human, 150)
	TEST_ASSERT_EQUAL(human.size_multiplier, 1.5, "the actual number answer reaches resize after parent activation has completed")
	TEST_ASSERT_EQUAL(bystander.size_multiplier, bystander_size, "the unrelated ambient actor never resizes")
	TEST_ASSERT_EQUAL(human.nutrition, nutrition - 2, "answering does not repeat activation or charge nutrition again")
	TEST_ASSERT_NULL(software.size_prompt, "the completed actual prompt is detached")
	software.activate()
	var/datum/prompt/number/cancelled = SSrequests.open_for(human)
	TEST_ASSERT(istype(cancelled), "second actual activation opens the real cancellation request")
	test_answer(human, null, REQ_CANCELLED)
	test_time(0.1 SECONDS)
	TEST_ASSERT_EQUAL(human.size_multiplier, 1.5, "real optional cancellation does not change the owner's size")
	TEST_ASSERT_NULL(software.size_prompt, "actual optional cancellation runs cleanup")
	TEST_ASSERT_EQUAL(software.active, FALSE, "cancelled pulse remains deactivated")
	TEST_ASSERT_EQUAL(implant.power_usage, power, "cancellation leaves active power balanced")

/datum/unit_test/dq_eg2/interim_nif_size_actor/stale/run_gate()
	var/mob/living/carbon/human/human = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/nifsoft/sizechange/software = install_size(human)
	var/obj/item/nif/implant = software.nif()
	var/original_size = human.size_multiplier
	software.activate()
	var/datum/prompt/number/old = SSrequests.open_for(human)
	TEST_ASSERT(istype(old), "first activation opens the actual stale request")
	test_time(0.1 SECONDS)
	software.activate()
	var/datum/prompt/number/current = software.size_prompt
	TEST_ASSERT(current && current != old, "second actual activation installs a distinct current native request")
	test_answer(human, 150)
	TEST_ASSERT_EQUAL(human.size_multiplier, original_size, "an actual replaced prompt cannot resize the owner")
	TEST_ASSERT_EQUAL(software.size_prompt, current, "an old answer cannot clear the current prompt")
	implant.unimplant(human)
	TEST_ASSERT_NULL(human.nif, "actual removal clears the reciprocal implant relation")
	test_answer(human, 150)
	test_time(0.1 SECONDS)
	TEST_ASSERT_EQUAL(human.size_multiplier, original_size, "actual removed-implant answer cannot resize its former owner")
	TEST_ASSERT_NULL(software.size_prompt, "removed-implant answer clears its own pending prompt")
	TEST_ASSERT_EQUAL(software.active, FALSE, "actual removal leaves no active pulse after its timer")

/datum/unit_test/dq_eg2/interim_nif_size_actor/deleted_owner/run_gate()
	var/mob/living/carbon/human/human = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/nifsoft/sizechange/software = install_size(human)
	var/obj/item/nif/implant = software.nif()
	software.activate()
	var/datum/prompt/number/ask = SSrequests.open_for(human)
	TEST_ASSERT(istype(ask), "actual activation produces a typed native number request")
	// Keep the actual implant alive while its original human is deleted.
	implant.forceMove(run_loc_floor_bottom_left)
	qdel(human)
	TEST_ASSERT(QDELETED(human) && !QDELETED(implant), "the actual original owner is gone while its implant survives")
	test_time(1 SECONDS)
	TEST_ASSERT(QDELETED(ask), "the real native request sweep retires the deleted-owner request")
	test_time(0.1 SECONDS)
	TEST_ASSERT_EQUAL(software.active, FALSE, "pulse cleanup still runs after the deleted-owner request is retired")
	TEST_ASSERT_EQUAL(implant.power_usage, 0, "the surviving actual implant has no leaked active power cost")
