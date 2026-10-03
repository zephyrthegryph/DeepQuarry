/obj/interim_paper_supply_pickup_actor_click
	var/obj/item/item
	var/mob/destination

/obj/interim_paper_supply_pickup_actor_click/Click(location, control, params)
	item.MouseDrop(destination)

/datum/unit_test/interim_paper_supply_pickup_actor
	abstract_type = /datum/unit_test/interim_paper_supply_pickup_actor
	var/item_type

/datum/unit_test/interim_paper_supply_pickup_actor/bin
	item_type = /obj/item/paper_bin

/datum/unit_test/interim_paper_supply_pickup_actor/pad
	item_type = /obj/item/sticky_pad

/datum/unit_test/interim_paper_supply_pickup_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	var/mob/observer/dead/observer = allocate(/mob/observer/dead, T)
	observer.forceMove(T)
	var/obj/item/item = allocate(item_type, T)
	var/obj/item/paper/original
	var/original_info
	if(istype(item, /obj/item/paper_bin))
		var/obj/item/paper_bin/bin = item
		TEST_ASSERT_EQUAL(bin.amount, 30, "the actual paper bin starts with its thirty stock sheets")
		original = allocate(/obj/item/paper, T)
		original.set_content("Original stored record", "record")
		original_info = original.info
		TEST_ASSERT(findtext(original_info, "Original stored record"), "the real paper contains its written fixture record")
		TEST_ASSERT(actor.put_in_active_hand(original), "the real actor holds the original written sheet for insertion")
		bin.interaction_item(actor, original, null)
		TEST_ASSERT_EQUAL(original.loc, bin, "actual insertion physically contains the original written sheet")
		TEST_ASSERT_EQUAL(bin.amount, 31, "actual insertion credits exactly one custom sheet")
		TEST_ASSERT_EQUAL(LAZYLEN(bin.papers), 1, "actual insertion records one custom paper identity")
		TEST_ASSERT_NULL(actor.get_active_hand(), "actual insertion releases the original source hand")
	else
		var/obj/item/sticky_pad/pad = item
		TEST_ASSERT_EQUAL(pad.papers, 50, "the actual blank pad starts with fifty sticky sheets")
		TEST_ASSERT_NULL(pad.written_text, "the real pad begins unwritten")
		TEST_ASSERT_NULL(pad.written_by, "the real blank pad has no writer attribution")
	var/obj/interim_paper_supply_pickup_actor_click/probe = allocate(/obj/interim_paper_supply_pickup_actor_click, T)
	rel_set(probe, nameof(probe.item), item)
	rel_set(probe, nameof(probe.destination), bystander)
	km_synthetic_click(actor, probe)
	TEST_ASSERT_EQUAL(item.loc, T, "a different native drop destination cannot pick up the actual item")
	rel_set(probe, nameof(probe.destination), observer)
	km_synthetic_click(observer, probe)
	TEST_ASSERT_EQUAL(item.loc, T, "an actual unsupported observer self-drop is refused without a human-organ runtime")
	var/obj/item/blocker = allocate(/obj/item, T)
	TEST_ASSERT(actor.put_in_active_hand(blocker), "the real selected hand contains an unrelated blocker")
	rel_set(probe, nameof(probe.destination), actor)
	km_synthetic_click(actor, probe)
	TEST_ASSERT_EQUAL(item.loc, T, "an occupied active hand prevents pickup without displacing its blocker")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), blocker, "actual failed pickup preserves the exact blocker")
	TEST_ASSERT(actor.unEquip(blocker), "real inventory removal frees the selected hand")
	var/obj/item/handcuffs/cuffs = allocate(/obj/item/handcuffs, T)
	TEST_ASSERT(actor.equip_to_slot(cuffs, SLOT_ID_HANDCUFFED), "actual cuffs enable the real restraint guard")
	TEST_ASSERT(actor.restrained(), "the initiating human is actually restrained")
	km_synthetic_click(actor, probe)
	TEST_ASSERT_EQUAL(item.loc, T, "a restrained native actor cannot pick up the item")
	TEST_ASSERT(actor.unEquip(cuffs), "real cuff removal restores the valid pickup actor")
	km_synthetic_click(actor, probe)
	TEST_ASSERT_EQUAL(actor.get_active_hand(), item, "the actual native drag places the exact item in its initiating actor hand")
	TEST_ASSERT_EQUAL(item.loc, actor, "successful native pickup physically contains the same item in that actor")
	TEST_ASSERT_NULL(bystander.get_active_hand(), "the unrelated nearby human gains no held item")
	if(original)
		var/obj/item/paper_bin/bin = item
		TEST_ASSERT_EQUAL(bin.amount, 31, "actual pickup preserves all thirty stock sheets plus the original record")
		TEST_ASSERT_EQUAL(LAZYLEN(bin.papers), 1, "actual pickup preserves the exact custom-paper ledger count")
		TEST_ASSERT_EQUAL(bin.papers[1], original, "actual pickup preserves the original stored paper identity")
		TEST_ASSERT_EQUAL(original.loc, bin, "actual pickup preserves nested paper containment")
		TEST_ASSERT_EQUAL(original.info, original_info, "actual pickup preserves the original written contents")
	else
		var/obj/item/sticky_pad/pad = item
		TEST_ASSERT_EQUAL(pad.papers, 50, "actual pickup tears off no sticky sheets")
		TEST_ASSERT_NULL(pad.written_text, "actual pickup preserves the pad's blank text")
		TEST_ASSERT_NULL(pad.written_by, "actual pickup invents no writer attribution")
