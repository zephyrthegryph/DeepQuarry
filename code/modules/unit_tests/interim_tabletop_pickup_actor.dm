/obj/interim_tabletop_pickup_actor_click
	var/obj/item/item
	var/mob/destination

/obj/interim_tabletop_pickup_actor_click/Click(location, control, params)
	item.MouseDrop(destination)

/datum/unit_test/interim_tabletop_pickup_actor
	abstract_type = /datum/unit_test/interim_tabletop_pickup_actor
	var/item_type

/datum/unit_test/interim_tabletop_pickup_actor/deck
	item_type = /obj/item/deck/cards

/datum/unit_test/interim_tabletop_pickup_actor/desk
	item_type = /obj/item/toy/desk/newtoncradle

/datum/unit_test/interim_tabletop_pickup_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	var/mob/observer/dead/observer = allocate(/mob/observer/dead, T)
	observer.forceMove(T)
	var/obj/item/item = allocate(item_type, T)
	var/list/original_cards
	if(istype(item, /obj/item/deck/cards))
		var/obj/item/deck/cards/deck = item
		TEST_ASSERT_EQUAL(length(deck.cards), 54, "the actual constructor creates all fifty-four playing cards")
		original_cards = deck.cards.Copy()
	else
		var/obj/item/toy/desk/desk = item
		TEST_ASSERT(desk.activate(actor), "the real Newton cradle activates before pickup")
		TEST_ASSERT(desk.on, "the actual cradle begins in its activated state")
	var/obj/interim_tabletop_pickup_actor_click/probe = allocate(/obj/interim_tabletop_pickup_actor_click, T)
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
	if(original_cards)
		var/obj/item/deck/cards/deck = item
		TEST_ASSERT_EQUAL(length(deck.cards), length(original_cards), "pickup preserves the full actual deck")
		for(var/i in 1 to length(original_cards))
			TEST_ASSERT_EQUAL(deck.cards[i], original_cards[i], "pickup preserves each exact playing-card identity and order")
	else
		var/obj/item/toy/desk/desk = item
		TEST_ASSERT(desk.on, "actual pickup preserves the real activated Newton cradle state")
