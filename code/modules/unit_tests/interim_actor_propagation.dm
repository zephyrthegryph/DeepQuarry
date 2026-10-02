/// UI actions must use their actor even when invoked outside a player's verb.
/datum/unit_test/interim_nuclear_auth_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/nuclearbomb/bomb = allocate(/obj/machinery/nuclearbomb, T)
	var/obj/item/disk/nuclear/disk = allocate(/obj/item/disk/nuclear, T)
	TEST_ASSERT(actor.put_in_active_hand(disk), "the explicit actor holds the disk")
	TEST_ASSERT(bomb.ui_act_auth(actor, list(), null, null, "auth"), "the authentication action handles insertion")
	TEST_ASSERT_EQUAL(bomb.auth(), disk, "the action inserts the explicit actor's disk")
	TEST_ASSERT_EQUAL(disk.loc, bomb, "the disk moves into the bomb")
	TEST_ASSERT_NULL(actor.get_active_hand(), "insertion releases the actor's hand")
	bomb.yes_code = TRUE
	TEST_ASSERT(bomb.ui_act_auth(actor, list(), null, null, "auth"), "the authentication action handles ejection")
	TEST_ASSERT_NULL(bomb.auth(), "ejection clears the authentication reference")
	TEST_ASSERT_EQUAL(disk.loc, T, "ejection returns the disk to the floor")
	TEST_ASSERT(!bomb.yes_code, "ejection invalidates the entered code")

/// Tool checks read the explicit actor's held item and actually change the wire.
/datum/unit_test/interim_nuclear_wire_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/nuclearbomb/bomb = allocate(/obj/machinery/nuclearbomb, T)
	var/obj/item/tool/wirecutters/cutters = allocate(/obj/item/tool/wirecutters, T)
	TEST_ASSERT(actor.put_in_active_hand(cutters), "the explicit actor holds wirecutters")
	var/wire = bomb.light_wire
	TEST_ASSERT_EQUAL(LAZYACCESS(bomb.wires_list, wire), FALSE, "the selected wire starts intact")
	TEST_ASSERT(bomb.ui_act_wire(actor, list("wire" = wire), null, null, "wire"), "the wire action handles the cut")
	TEST_ASSERT_EQUAL(LAZYACCESS(bomb.wires_list, wire), TRUE, "the explicit actor's cutters cut the selected wire")
	TEST_ASSERT(bomb.ui_act_wire(actor, list("wire" = wire), null, null, "wire"), "the wire action handles mending")
	TEST_ASSERT_EQUAL(LAZYACCESS(bomb.wires_list, wire), FALSE, "the second action mends the selected wire")
