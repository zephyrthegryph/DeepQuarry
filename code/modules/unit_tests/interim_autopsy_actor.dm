/// The delayed report callback gives its actual paper to the captured scanner user.
/datum/unit_test/interim_autopsy_report_actor/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/autopsy_scanner/scanner = allocate(/obj/item/autopsy_scanner, T)
	scanner.target_name = "Report fixture"
	scanner.print_report(actor, "Observed wound data")
	var/obj/item/paper/report = actor.get_active_hand()
	TEST_ASSERT(istype(report), "The report callback gives a real paper to its explicit user")
	own(report)
	TEST_ASSERT_EQUAL(report.loc, actor, "The actual paper is held by the captured user")
	TEST_ASSERT_EQUAL(report.name, "Autopsy Data (Report fixture)", "The printed report identifies the scanned target")
	TEST_ASSERT_EQUAL(report.info, "<tt>Observed wound data</tt>", "The printed report preserves its supplied findings")

/// Full hands leave the report on the user's turf without replacing either held item.
/datum/unit_test/interim_autopsy_report_full_hands/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/autopsy_scanner/scanner = allocate(/obj/item/autopsy_scanner, T)
	var/obj/item/pen/left = allocate(/obj/item/pen, T)
	var/obj/item/pen/right = allocate(/obj/item/pen, T)
	TEST_ASSERT(actor.put_in_l_hand(left), "The fixture occupies the left hand")
	TEST_ASSERT(actor.put_in_r_hand(right), "The fixture occupies the right hand")
	var/list/before = turf_contents_of_type(T, /obj/item/paper)
	scanner.print_report(actor, "Full hands findings")
	var/list/after = turf_contents_of_type(T, /obj/item/paper)
	var/list/created = after - before
	TEST_ASSERT_EQUAL(length(created), 1, "The full-hands callback leaves exactly one report on the turf")
	var/obj/item/paper/report = created[1]
	own(report)
	TEST_ASSERT_EQUAL(report.info, "<tt>Full hands findings</tt>", "The dropped report preserves its findings")
	TEST_ASSERT_EQUAL(actor.get_equipped_item(SLOT_ID_HAND_L), left, "Printing preserves the held left item")
	TEST_ASSERT_EQUAL(actor.get_equipped_item(SLOT_ID_HAND_R), right, "Printing preserves the held right item")
