/// Hacking destroys the scanner and leaves exactly the selected successor on the floor.
/datum/unit_test/interim_sleevemate_hack_replacement/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/list/options = list("Body Snatcher" = /obj/item/bodysnatcher, "Mind Binder" = /obj/item/mindbinder)
	for(var/choice in options)
		var/obj/item/sleevemate/scanner = allocate(/obj/item/sleevemate, T)
		TEST_ASSERT(user.put_in_active_hand(scanner), "the original scanner can be held")
		var/datum/om/prompt/choice/ask = allocate(/datum/om/prompt/choice)
		set_var(ask, "answerer", user)
		ask.choice = choice
		TEST_ASSERT_EQUAL(scanner.hack_chosen(ask), 1, "a supported hack completes")
		TEST_ASSERT(QDELETED(scanner), "hacking consumes the original scanner")
		var/path = options[choice]
		var/obj/item/successor = locate(path) in T
		if(successor)
			rel_add(src, nameof(allocated), successor)
		TEST_ASSERT_NOTNULL(successor, "hacking produces the selected successor on the floor")
		TEST_ASSERT_EQUAL(successor.loc, T, "the hacked successor preserves the old floor placement")
		TEST_ASSERT(!user.is_in_hands(successor), "hacking does not silently equip the replacement")
		qdel(successor)
	var/obj/item/sleevemate/unchanged = allocate(/obj/item/sleevemate, T)
	var/datum/om/prompt/choice/invalid = allocate(/datum/om/prompt/choice)
	set_var(invalid, "answerer", user)
	invalid.choice = "Invalid hack"
	unchanged.hack_chosen(invalid)
	TEST_ASSERT(!QDELETED(unchanged), "an unsupported choice cannot consume the scanner")
	TEST_ASSERT_EQUAL(unchanged.loc, T, "an unsupported choice preserves its location")
