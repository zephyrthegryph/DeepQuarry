/// Hacking destroys the scanner and leaves exactly the selected successor on the floor.
/datum/unit_test/interim_sleevemate_hack_replacement/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/list/options = list("Body Snatcher" = /obj/item/bodysnatcher, "Mind Binder" = /obj/item/mindbinder)
	for(var/choice in options)
		var/obj/item/sleevemate/scanner = allocate(/obj/item/sleevemate, T)
		TEST_ASSERT(user.put_in_active_hand(scanner), "the original scanner can be held")
		var/completed = hack_answered(scanner, user, choice)
		test_time(1 SECOND) // the scanner is replaced once the emag op has finished with it
		own_turf_contents(T)
		TEST_ASSERT_EQUAL(completed, 1, "a supported hack completes")
		TEST_ASSERT(QDELETED(scanner), "hacking consumes the original scanner")
		var/path = options[choice]
		var/obj/item/successor = locate_within(T, path)
		TEST_ASSERT_NOTNULL(successor, "hacking produces the selected successor on the floor")
		TEST_ASSERT_EQUAL(successor.loc, T, "the hacked successor preserves the old floor placement")
		TEST_ASSERT(!user.is_in_hands(successor), "hacking does not silently equip the replacement")
		qdel(successor)
	test_time(10 SECONDS) // the hacks' drifting sparks burn out
	var/obj/item/sleevemate/unchanged = allocate(/obj/item/sleevemate, T)
	hack_answered(unchanged, user, "Invalid hack")
	test_time(1 SECOND)
	TEST_ASSERT(!QDELETED(unchanged), "an unsupported choice cannot consume the scanner")
	TEST_ASSERT_EQUAL(unchanged.loc, T, "an unsupported choice preserves its location")

/// Runs the sleevemate's emag choice handler as the op engine does: an op context of `user` carrying the answered choice prompt.
/proc/hack_answered(obj/item/sleevemate/scanner, mob/user, choice)
	var/datum/prompt/choice/P = new
	P.value = choice
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = scanner
	A.target = scanner
	A.actor = user
	A.answer = P
	. = scanner.hack_chosen(A)
	A.release()
	qdel(P)
