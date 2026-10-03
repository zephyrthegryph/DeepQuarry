// Keep unrelated default software out of the actual implanted NIF fixture.
/obj/item/nif/interim_size_actor
	starting_software = null

/datum/nifsoft/sizechange/interim_cost_probe
	a_drain = 2

/obj/interim_nif_size_click
	var/datum/nifsoft/sizechange/software

/obj/interim_nif_size_click/Click(location, control, params)
	software.activate()

/datum/unit_test/om/interim_nif_size_actor
	abstract_type = /datum/unit_test/om/interim_nif_size_actor

/datum/unit_test/om/interim_nif_size_actor/proc/install_size(mob/living/carbon/human/human)
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

/datum/unit_test/om/interim_nif_size_actor/answer/run_om(list/made)
	sched.test_prompts = list()
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
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 1, "actual activation opens one real number prompt")
	var/datum/om/prompt/number/ask = sched.test_prompts[1]
	made += ask
	TEST_ASSERT_EQUAL(ask.peek("answerer"), human, "the real implant owner answers despite an unrelated native click actor")
	TEST_ASSERT_EQUAL(ask.peek("subject"), implant, "the prompt captures the actual original implant")
	TEST_ASSERT_EQUAL(human.nutrition, nutrition - 2, "parent activation charges the real owner exactly once before asking")
	TEST_ASSERT_EQUAL(implant.power_usage, power + 2, "actual parent activation registers its real active power cost")
	scheduler_advance(0.01 SECONDS)
	TEST_ASSERT_EQUAL(software.active, FALSE, "the real scheduled pulse deactivates without waiting for an answer")
	TEST_ASSERT_EQUAL(implant.power_usage, power, "actual deactivation balances active power exactly once")
	om_prompt_answer(ask, 150)
	TEST_ASSERT_EQUAL(human.size_multiplier, 1.5, "the actual number answer reaches resize after parent activation has completed")
	TEST_ASSERT_EQUAL(bystander.size_multiplier, bystander_size, "the unrelated ambient actor never resizes")
	TEST_ASSERT_EQUAL(human.nutrition, nutrition - 2, "answering does not repeat activation or charge nutrition again")
	TEST_ASSERT_NULL(software.size_prompt, "the completed actual prompt is detached")
	software.activate()
	var/datum/om/prompt/number/cancelled = sched.test_prompts[2]
	made += cancelled
	om_prompt_answer(cancelled, null, TRUE)
	scheduler_advance(0.01 SECONDS)
	TEST_ASSERT_EQUAL(human.size_multiplier, 1.5, "real optional cancellation does not change the owner's size")
	TEST_ASSERT_NULL(software.size_prompt, "actual optional cancellation runs cleanup")
	TEST_ASSERT_EQUAL(software.active, FALSE, "cancelled pulse remains deactivated")
	TEST_ASSERT_EQUAL(implant.power_usage, power, "cancellation leaves active power balanced")

/datum/unit_test/om/interim_nif_size_actor/stale/run_om(list/made)
	sched.test_prompts = list()
	var/mob/living/carbon/human/human = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/nifsoft/sizechange/software = install_size(human)
	var/obj/item/nif/implant = software.nif()
	var/original_size = human.size_multiplier
	software.activate()
	var/datum/om/prompt/number/old = sched.test_prompts[1]
	made += old
	scheduler_advance(0.01 SECONDS)
	software.activate()
	var/datum/om/prompt/number/current = sched.test_prompts[2]
	made += current
	om_prompt_answer(old, 150)
	TEST_ASSERT_EQUAL(human.size_multiplier, original_size, "an actual replaced prompt cannot resize the owner")
	TEST_ASSERT_EQUAL(software.size_prompt, current, "an old answer cannot clear the current prompt")
	implant.unimplant(human)
	TEST_ASSERT_NULL(human.nif, "actual removal clears the reciprocal implant relation")
	om_prompt_answer(current, 150)
	scheduler_advance(0.01 SECONDS)
	TEST_ASSERT_EQUAL(human.size_multiplier, original_size, "actual removed-implant answer cannot resize its former owner")
	TEST_ASSERT_NULL(software.size_prompt, "removed-implant answer clears its own pending prompt")
	TEST_ASSERT_EQUAL(software.active, FALSE, "actual removal leaves no active pulse after its timer")

/datum/unit_test/om/interim_nif_size_actor/deleted_owner/run_om(list/made)
	sched.test_prompts = list()
	var/mob/living/carbon/human/human = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/nifsoft/sizechange/software = install_size(human)
	var/obj/item/nif/implant = software.nif()
	software.activate()
	var/datum/om/prompt/number/ask = sched.test_prompts[1]
	made += ask
	// Keep the actual implant alive while its original human is deleted.
	implant.forceMove(run_loc_floor_bottom_left)
	qdel(human)
	TEST_ASSERT(QDELETED(human) && !QDELETED(implant), "the actual original owner is gone while its implant survives")
	TEST_ASSERT_EQUAL(om_prompt_answer(ask, 150), "gone", "the real prompt framework drops the deleted-owner answer")
	scheduler_advance(0.01 SECONDS)
	TEST_ASSERT_EQUAL(software.active, FALSE, "pulse cleanup still runs although the framework invokes no answer callback")
	TEST_ASSERT_EQUAL(implant.power_usage, 0, "the surviving actual implant has no leaked active power cost")
