/// Tarot shuffling receives the explicit actor through each real public entry point while preserving cards and cooldown refusal.
/datum/unit_test/interim_tarot_shuffle_actor
	var/entry = "self"

/datum/unit_test/interim_tarot_shuffle_actor/verb_entry
	entry = "verb"

/datum/unit_test/interim_tarot_shuffle_actor/alt_entry
	entry = "alt"

/datum/unit_test/interim_tarot_shuffle_actor/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/deck/tarot/deck = allocate(/obj/item/deck/tarot, T)
	TEST_ASSERT_EQUAL(length(deck.cards), 78, "The actual tarot constructor creates exactly 22 major and 56 minor cards")
	var/datum/playingcard/first = deck.cards[1]
	TEST_ASSERT_EQUAL(first.name, "Fool", "The actual tarot constructor starts with its canonical first major card")
	var/datum/playingcard/last = deck.cards[78]
	TEST_ASSERT_EQUAL(last.name, "king of swords", "The actual tarot constructor ends with its canonical final minor card")
	var/list/original = deck.cards.Copy()
	var/list/names = list()
	for(var/datum/playingcard/card in original)
		names[card] = card.name
	TEST_ASSERT(COOLDOWN_FINISHED(deck, shuffle_cooldown), "The actual newly constructed deck allows its first shuffle")
	// A fixed local seed makes the actual shuffle and reversal outcome repeatable.
	rand_seed(22156)
	switch(entry)
		if("self")
			perform_op(actor, deck, "self", deck)
		if("verb")
			test_menu(actor, deck, "deck_verb_shuffle")
		if("alt")
			perform_op(actor, deck, "alt")
	TEST_ASSERT(!COOLDOWN_FINISHED(deck, shuffle_cooldown), "The actual public shuffle starts its original one-second cooldown")
	TEST_ASSERT_EQUAL(length(deck.cards), 78, "The real shuffle retains the exact canonical card count")
	var/list/order = deck.cards.Copy()
	var/list/shuffled_names = list()
	var/reversed_count = 0
	for(var/datum/playingcard/card in original)
		TEST_ASSERT(!QDELETED(card) && (card in deck.cards), "The actual shuffle preserves each original owned card identity")
		TEST_ASSERT_EQUAL(replacetext(card.name, " reversed", ""), names[card], "The actual shuffle preserves each canonical card name while allowing its original reversal")
		if(card.name != names[card])
			reversed_count++
		shuffled_names[card] = card.name
	TEST_ASSERT(reversed_count > 0 && reversed_count < 78, "The fixed-seed actual tarot shuffle produces both upright and reversed cards")
	deck.shuffle(actor)
	for(var/index = 1, index <= length(order), index++)
		var/datum/playingcard/card = order[index]
		TEST_ASSERT_EQUAL(deck.cards[index], card, "Actual cooldown refusal preserves the exact already shuffled card order")
		TEST_ASSERT_EQUAL(card.name, shuffled_names[card], "Actual cooldown refusal preserves the exact already shuffled reversal state")
	TEST_ASSERT(!QDELETED(deck) && deck.loc == T && actor.loc == T, "Actual actor-driven shuffling preserves the original deck and actor floor")
