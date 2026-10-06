/datum/playingcard
	var/name = "playing card"
	var/card_icon = "card_back"
	var/back_icon = "card_back"

/obj/item/deck
	w_class = ITEMSIZE_SMALL
	icon = 'icons/obj/playing_cards.dmi'
	var/list/cards = list() // ALLOW(instance_list): d: a deck always holds cards
	COOLDOWN_DECLARE(shuffle_cooldown) // to prevent spam shuffle

CAPABILITIES(/obj/item/deck)
	owns_many(nameof(cards))
	drag_onto(PROC_REF(mousedrop_input))

/obj/item/deck/holder
	name = "card box"
	desc = "A small leather case to show how classy you are compared to everyone else."
	icon_state = "card_holder"

/obj/item/deck/cards
	name = "deck of cards"
	desc = "A simple deck of playing cards."
	icon_state = "deck"
	drop_sound = SFX_ITEMS_DROP_PAPER
	pickup_sound = SFX_ITEMS_PICKUP_PAPER
	var/card_icon_prefix = ""
	var/deck_size = 1 // # of times we will generate cards within this deck

/obj/item/deck/cards/proc/init_cards()
	PROTECTED_PROC(TRUE)
	var/datum/playingcard/pcard
	for(var/i = 0, i < deck_size, i++)
		for(var/suit in list("spades","clubs","diamonds","hearts"))
			var/colour
			switch(suit)
				if("clubs", "spades")
					colour = "black_"
				else
					colour = "red_"

			for(var/number in list("ace","two","three","four","five","six","seven","eight","nine","ten"))
				pcard = new()
				pcard.name = "[number] of [suit]"
				pcard.card_icon = "[card_icon_prefix][colour]num"
				pcard.back_icon = "[card_icon_prefix]card_back"
				rel_add(src, nameof(cards), pcard)

			for(var/number in list("jack","queen","king"))
				pcard = new()
				pcard.name = "[number] of [suit]"
				pcard.card_icon = "[card_icon_prefix][colour]col"
				pcard.back_icon = "[card_icon_prefix]card_back"
				rel_add(src, nameof(cards), pcard) // Make it so.

		init_jokers()

/obj/item/deck/cards/proc/init_jokers()
	var/datum/playingcard/pcard
	for(var/i = 0, i<2, i++)
		pcard = new()
		pcard.name = "joker"
		pcard.card_icon = "joker"
		rel_add(src, nameof(cards), pcard)

/obj/item/deck/cards/Initialize(mapload)
	. = ..()
	init_cards()

/// Old attackby.
/obj/item/deck/proc/interaction_item(mob/user, obj/O, datum/interaction/interaction)
	if(istype(O,/obj/item/hand))
		var/obj/item/hand/H = O
		if(H.parentdeck == src)
			for(var/datum/playingcard/P in H.cards?.Copy())
				rel_move(H, nameof(H.cards), src, nameof(cards), P)
			consume(H, user)
			to_chat(user,span_notice("You place your cards on the bottom of \the [src]."))
			return INTERACTION_HANDLED_PASS
		else
			to_chat(user,span_warning("You can't mix cards from other decks!"))
			return INTERACTION_HANDLED_PASS
	return FALSE

DECLARE_INTERACTIONS(/obj/item/deck, \
	INTERACT_HAND(null, PROC_REF(interaction_hand)), \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_ALT(null, PROC_REF(interaction_alt)), \
	INTERACT_VERB("Draw", PROC_REF(deck_verb_draw), REQ_TARGET_STATE(/obj/item/deck/proc/can_draw)), \
	INTERACT_VERB("Deal", PROC_REF(deck_verb_deal), REQ_TARGET_STATE(/obj/item/deck/proc/can_deal)), \
	INTERACT_VERB("Deal Multiple Cards", PROC_REF(deck_verb_deal_multi), REQ_TARGET_STATE(/obj/item/deck/proc/can_deal)), \
	INTERACT_VERB("Search for Cards", PROC_REF(deck_verb_search), REQ_TARGET_STATE(/obj/item/deck/proc/can_draw)), \
	INTERACT_VERB("Shuffle", PROC_REF(deck_verb_shuffle)), \
)

/// Requirement: TRUE, or why no card can be drawn into the user's hand. The effect's silent guards
/// (stat, reach, non-carbon) pass here. Also checked by the direct callers (attack_hand).
/obj/item/deck/proc/can_draw(mob/living/carbon/user, atom/target, obj/item/held)
	if(user.stat || !Adjacent(user))
		return TRUE
	if(user.hands_are_full()) // Safety check lest the card disappear into oblivion
		return "your hands are full"
	if(!iscarbon(user))
		return TRUE
	if(!length(cards))
		return "there are no cards in the deck"
	var/obj/item/hand/H = user.get_type_in_hands(/obj/item/hand)
	if(H && !(H.parentdeck == src))
		return "you can't mix cards from different decks"
	return TRUE

/// Requirement: TRUE, or why no card can be dealt. Also checked by the direct callers (ctrl-clicks).
/obj/item/deck/proc/can_deal(mob/user, atom/target, obj/item/held)
	if(user.stat || !Adjacent(user))
		return TRUE
	if(!length(cards))
		return "there are no cards in the deck"
	return TRUE

/// Direct (non-interaction) callers: tell the user why `why` refuses, and return TRUE if it did.
/obj/item/proc/card_refused(mob/user, why)
	if(why == TRUE)
		return FALSE
	to_chat(user, span_notice("[capitalize(why)]."))
	return TRUE

/// Old attack_hand.
/obj/item/deck/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	var/mob/living/carbon/human/H = user
	if(ishuman(H) && (istype(src.loc, /obj/item/storage) || src == H.get_equipped_item(SLOT_ID_POCKET_R) || src == H.get_equipped_item(SLOT_ID_POCKET_L) || src.loc == user)) // so objects can be removed from storage containers or pockets. also added a catch-all, so if it's in the mob you'll pick it up. Human only, however!
		return FALSE
	else // but if they're not, or are in your hands, you can still draw cards.
		if(card_refused(user, can_draw(user, src, null)))
			return TRUE
		deck_verb_draw(user)
	return TRUE

/// Old Draw verb: Draw a card from a deck.
/obj/item/deck/proc/deck_verb_draw(mob/living/carbon/user, obj/item/held, datum/interaction/interaction)
	if(user.stat || !Adjacent(user)) return

	if(user.hands_are_full()) // Safety check lest the card disappear into oblivion (the requirement told them)
		return

	if(!iscarbon(user))
		return

	if(!length(cards)) // re-checked: the requirement told them, and reruns after a prompt re-enter here
		return

	var/obj/item/hand/H = user.get_type_in_hands(/obj/item/hand)
	if(H && !(H.parentdeck == src))
		return

	if(!H)
		H = new(get_turf(src))
		user.put_in_hands(H)

	if(!H || !user) return

	var/datum/playingcard/P = cards[1]
	rel_move(src, nameof(cards), H, nameof(H.cards), P)
	H.parentdeck = src
	H.update_icon()
	act_message(user, null, others = span_infoplain(span_bold("%U%") + " draws a card."))
	to_chat(user,span_notice("It's the [P]."))

/// Old Deal verb: Deal a card from a deck.
/obj/item/deck/proc/deck_verb_deal(mob/user, obj/item/held, datum/interaction/interaction)
	return deck_verb_deal_stage(user, held, interaction, list())

/obj/item/deck/proc/deck_verb_deal_stage(mob/user, obj/item/held, datum/interaction/interaction, list/card_answers)
	if(user.stat || !Adjacent(user)) return

	if(!length(cards)) // re-checked: the requirement told them, and reruns after a prompt re-enter here
		return

	var/list/players = list()
	for(var/mob/living/player in viewers(3, user))
		if(!player.stat)
			players += player

	if(!("k148" in card_answers))
		open_request(src, /datum/prompt/choice/card_game_review, PROC_REF(deck_verb_deal_answered), answerer = user, card_operator = user, card_input = held, card_interaction = interaction, card_answers = card_answers, card_key = "k148", question = "Who do you wish to deal a card?", title = "Deal to whom?", choices = players , buttons = FALSE)
		return null
	var/mob/living/M = card_answers["k148"]
	if(isnull(M))
		return
	if(!user || !src || !M) return

	deal_at(user, M, 1)

/// Old Deal Multiple Cards verb: Deal multiple cards from a deck.
/obj/item/deck/proc/deck_verb_deal_multi(mob/user, obj/item/held, datum/interaction/interaction)
	return deck_verb_deal_multi_stage(user, held, interaction, list())

/obj/item/deck/proc/deck_verb_deal_multi_stage(mob/user, obj/item/held, datum/interaction/interaction, list/card_answers)
	if(user.stat || !Adjacent(user)) return

	if(!length(cards)) // re-checked: the requirement told them, and reruns after a prompt re-enter here
		return

	var/list/players = list()
	for(var/mob/living/player in viewers(3, user))
		if(!player.stat)
			players += player
	var/maxcards = max(min(length(cards),10),1)
	if(!("k172" in card_answers))
		open_request(src, /datum/prompt/number/card_game_review, PROC_REF(deck_verb_deal_multi_answered), answerer = user, card_operator = user, card_input = held, card_interaction = interaction, card_answers = card_answers, card_key = "k172", question = "How many card(s) do you wish to deal? You may deal up to [maxcards] cards.", card_max = maxcards)
		return null
	var/dcard = card_answers["k172"]
	if(isnull(dcard))
		return
	if(dcard > maxcards)
		return
	if(!("k175" in card_answers))
		open_request(src, /datum/prompt/choice/card_game_review, PROC_REF(deck_verb_deal_multi_answered), answerer = user, card_operator = user, card_input = held, card_interaction = interaction, card_answers = card_answers, card_key = "k175", question = "Who do you wish to deal [dcard] card(s)?", title = "Deal to whom?", choices = players , buttons = FALSE)
		return null
	var/mob/living/M = card_answers["k175"]
	if(isnull(M))
		return
	if(!user || !src || !M) return

	deal_at(user, M, dcard)

/// Old Search for Cards verb: Search for and draw a specific card (or cards) in the deck. This will be an obvious action to all observers.
/obj/item/deck/proc/deck_verb_search(mob/living/carbon/user, obj/item/held, datum/interaction/interaction)
	return deck_verb_search_stage(user, held, interaction, list())

/obj/item/deck/proc/deck_verb_search_stage(mob/living/carbon/user, obj/item/held, datum/interaction/interaction, list/card_answers)
	if(user.stat || !Adjacent(user)) return

	if(user.hands_are_full()) // Safety check lest the card disappear into oblivion (the requirement told them)
		return

	if(!iscarbon(user))
		return

	if(!length(cards)) // re-checked: the requirement told them, and reruns after a prompt re-enter here
		return

	var/obj/item/hand/H = user.get_type_in_hands(/obj/item/hand)
	if(H && !(H.parentdeck == src))
		return


	act_message(user, src, others = span_notice("%U% looks into %T% and searches within it...")) // Emote before doing anything so you can't cheat!

	// We store the card names as a dictionary with the card name as the key and the number of duplicates of that card
	// 		because otherwise the TGUI checkbox checks all duplicate names if you tick just one
	var/list/card_names = list()
	for(var/datum/playingcard/P in cards)
		var/name = P.name
		// If we haven't yet found any cards with this name...
		if(!card_names[name])
			// ... Add them to a new list, where we'll store any duplicates!
			card_names[name] = list()
		card_names[name] += name


	var/list/cards_to_choose = list()
	for(var/key, value in card_names)
		var/list/L = value
		for(var/i = 0, i < length(L), i++)
			cards_to_choose += "[key] ([i+1])"

	if(!("k228" in card_answers))
		open_request(src, /datum/prompt/checklist/card_game_review, PROC_REF(deck_verb_search_answered), answerer = user, card_operator = user, card_input = held, card_interaction = interaction, card_answers = card_answers, card_key = "k228", question = "Which cards do you want to retrieve?", title = "Choose your cards", choices = cards_to_choose, min_picks = 1)
		return null
	var/list/cards_to_draw = card_answers["k228"]
	if(isnull(cards_to_draw))
		return

	if(!LAZYLEN(cards_to_draw))
		act_message(user, src, others = span_notice("%U% searches for specific cards in %T%, but draws none."))
		return

	if(!H)
		H = new(get_turf(src))
		user.put_in_hands(H)

	if(!H || !user)
		return // Sanity check

	// Search through our cards for every card the user chose, and remove them from the deck if the name matches!
	for(var/to_draw in cards_to_draw)
		for(var/i = length(cards), i > 0, i--)
			// Ignore the duplicate number at the end, we just want the card name itself!
			var/TDN = copytext(to_draw, 1, length(to_draw) - 3)
			var/datum/playingcard/P = cards[i]
			if(TDN == P.name)
				rel_move(src, nameof(cards), H, nameof(H.cards), P)
				H.parentdeck = src
				break
	H.update_icon()

	act_message(user, src, others = span_notice("%U% searches for specific cards in %T%, and draws [cards_to_draw.len]."))

/obj/item/deck/item_ctrl_click(mob/user)
	if(card_refused(user, can_deal(user, src, null)))
		return
	deck_verb_deal(user)

/obj/item/deck/click_ctrl_shift(mob/user)
	if(card_refused(user, can_deal(user, src, null)))
		return
	deck_verb_deal_multi(user)

/obj/item/deck/proc/deal_at(mob/user, mob/target, dcard) // Take in the no. of card to be dealt
	var/obj/item/hand/H = new(get_step(user, user.dir))
	var/i
	for(i = 0, i < dcard, i++)
		if(!length(cards))
			break
		rel_move(src, nameof(cards), H, nameof(H.cards), cards[1])
		H.parentdeck = src
		H.concealed = 1
		H.update_icon()
	if(user==target)
		act_message(user, null, others = span_notice("%U% deals [dcard] card(s) to %THEMSELVES%."))
	else
		act_message(user, target, others = span_notice("%U% deals [dcard] card(s) to %T%."))
	H.throw_at(get_step(target,target.dir),10,1,H)


/// Old attackby.
/obj/item/hand/proc/interaction_item(mob/user, obj/O, datum/interaction/interaction)
	return interaction_item_stage(user, O, interaction, list())

/obj/item/hand/proc/interaction_item_stage(mob/user, obj/O, datum/interaction/interaction, list/card_answers)
	if(length(cards) == 1 && istype(O, /obj/item/pen))
		var/datum/playingcard/P = cards[1]
		if(P.name != "Blank Card")
			to_chat(user,span_notice("You cannot write on that card."))
			return INTERACTION_HANDLED_PASS
		if(!("k284" in card_answers))
			open_request(src, /datum/prompt/text/card_game_review, PROC_REF(interaction_item_answered), answerer = user, card_operator = user, card_input = O, card_interaction = interaction, card_answers = card_answers, card_key = "k284", question = "What do you wish to write on the card?", title = "Card Editing", max_len = MAX_PAPER_MESSAGE_LEN)
			return TRUE
		var/cardtext = card_answers["k284"]
		if(isnull(cardtext))
			return TRUE
		if(!cardtext)
			return INTERACTION_HANDLED_PASS
		P.name = cardtext
		// SNOWFLAKE FOR CAG, REMOVE IF OTHER CARDS ARE ADDED THAT USE THIS.
		P.card_icon = "cag_white_card"
		update_icon()
	else if(istype(O,/obj/item/hand))
		var/obj/item/hand/H = O
		if(H.parentdeck == src.parentdeck) // Prevent cardmixing
			for(var/datum/playingcard/P in cards?.Copy())
				rel_move(src, nameof(cards), H, nameof(H.cards), P)
			H.concealed = src.concealed
			consume(src, user)
			H.update_icon()
			return INTERACTION_HANDLED_PASS
		else
			to_chat(user,span_notice("You cannot mix cards from other decks!"))
			return INTERACTION_HANDLED_PASS

	return FALSE

/// Old attack_self.
/obj/item/deck/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	shuffle(user)
	return TRUE


/// Old Shuffle verb: Shuffle the cards in the deck.
/obj/item/deck/proc/deck_verb_shuffle(mob/user, obj/item/held, datum/interaction/interaction)
	shuffle(user)

/obj/item/deck/proc/shuffle(mob/user)
	if (COOLDOWN_FINISHED(src, shuffle_cooldown))
		var/list/unshuffled = own_take_all(src, nameof(cards))
		while(length(unshuffled))
			var/datum/playingcard/P = pick(unshuffled)
			unshuffled -= P
			rel_add(src, nameof(cards), P)
		act_message(user, src, others = span_notice("%U% shuffles %T%."))
		play_sfx(src, SFX_ITEMS_CARDSHUFFLE)
		COOLDOWN_START(src, shuffle_cooldown, 1 SECOND)
	else
		return

/// Old click_alt.
/obj/item/deck/proc/interaction_alt(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.stat || !Adjacent(user))
		return TRUE
	shuffle(user)
	return TRUE

/// The native MouseDrop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/item/deck/proc/mousedrop_input(datum/act/input/A)
	return pickup_with_actor(A.actor, A.over)

/obj/item/deck/proc/pickup_with_actor(mob/user, mob/destination)
	if((user && user == destination && (!( user.restrained() ) && (!( user.stat ) && (user.contents.Find(src) || in_range(src, user))))))
		if(ishuman(user))
			if( !user.get_active_hand() )		//if active hand is empty
				var/mob/living/carbon/human/H = user
				var/obj/item/organ/external/temp = H.organs_by_name[BP_R_HAND]

				if (H.hand)
					temp = H.organs_by_name[BP_L_HAND]
				if(temp && !temp.is_usable())
					to_chat(user,span_notice("You try to move your [temp.name], but cannot!"))
					return

				to_chat(user,span_notice("You pick up [src]."))
				user.put_in_hands(src)

	return

/obj/item/deck/cards/triple
	name = "big deck of cards"
	desc = "A simple deck of playing cards with triple the number of cards."
	deck_size = 3

/obj/item/pack
	name = "Card Pack"
	desc = "For those with disposible income."

	icon_state = "card_pack"
	icon = 'icons/obj/playing_cards.dmi'
	w_class = ITEMSIZE_TINY
	var/list/cards = list() // ALLOW(instance_list): d: a card pack always holds cards
	var/parentdeck = null // This variable is added here so that card pack dependent card can be mixed together by defining a "parentdeck" for them
	drop_sound = SFX_ITEMS_DROP_PAPER
	pickup_sound = SFX_ITEMS_PICKUP_PAPER

CAPABILITIES(/obj/item/pack)
	owns_many(nameof(cards))
	op("self", in_hand(), then(PROC_REF(interaction_self)))


/// Old attack_self.
/obj/item/pack/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, others = span_danger("%U% rips open %T%!"))
	var/obj/item/hand/H = new()

	for(var/datum/playingcard/P as anything in cards?.Copy())
		rel_move(src, nameof(cards), H, nameof(H.cards), P)
	H.parentdeck = src.parentdeck
	user.drop_item()
	consume(src, user)

	H.update_icon()
	user.put_in_active_hand(H)
	return TRUE

/obj/item/hand
	name = "hand of cards"
	desc = "Some playing cards."
	icon = 'icons/obj/playing_cards.dmi'
	icon_state = "empty"
	drop_sound = SFX_ITEMS_DROP_PAPER
	pickup_sound = SFX_ITEMS_PICKUP_PAPER
	w_class = ITEMSIZE_TINY

	var/concealed = 0
	var/list/cards = list() // ALLOW(instance_list): d: a hand of cards always holds cards
	var/parentdeck = null

/// Old Discard verb: Place (a) card(s) from your hand in front of you.
/obj/item/hand/proc/hand_verb_discard(mob/user, obj/item/held, datum/interaction/interaction)
	return hand_verb_discard_stage(user, held, interaction, list())

/obj/item/hand/proc/hand_verb_discard_stage(mob/user, obj/item/held, datum/interaction/interaction, list/card_answers)
	var/i
	var/maxcards = min(length(cards),5) // Maximum of 5 cards at once
	if(!("k432" in card_answers))
		open_request(src, /datum/prompt/number/card_game_review, PROC_REF(hand_verb_discard_answered), answerer = user, card_operator = user, card_input = held, card_interaction = interaction, card_answers = card_answers, card_key = "k432", question = "How many cards do you want to discard? You may discard up to [maxcards] card(s)", card_max = maxcards)
		return null
	var/discards = card_answers["k432"]
	if(isnull(discards))
		return
	if(discards > maxcards)
		return
	// Every card is picked before any is played: each answer re-runs this verb.
	var/list/picked = list()
	for(i = 1, i <= discards, i++)
		var/list/to_discard = list()
		for(var/datum/playingcard/P in cards)
			if(!(P in picked))
				to_discard[P.name] = P
		if(!("card[i]" in card_answers))
			open_request(src, /datum/prompt/choice/card_game_review, PROC_REF(hand_verb_discard_answered), answerer = user, card_operator = user, card_input = held, card_interaction = interaction, card_answers = card_answers, card_key = "card[i]", question = "Which card do you wish to put down?", title = "Card Selection", choices = to_discard , buttons = FALSE)
			return null
		var/discarding = card_answers["card[i]"]
		if(!discarding || !to_discard[discarding] || !user || !src) return
		picked += to_discard[discarding]

	for(var/datum/playingcard/card as anything in picked)
		var/discarding = card.name

		var/obj/item/hand/H = new(src.loc)
		rel_move(src, nameof(cards), H, nameof(H.cards), card)
		H.concealed = 0
		H.parentdeck = src.parentdeck
		H.update_icon()
		src.update_icon()
		act_message(user, null, others = span_notice("%U% plays \the [discarding]."))
		H.forceMove(get_turf(user))
		H.Move(get_step(user,user.dir))

	if(!length(cards))
		spent(src, user)

DECLARE_INTERACTIONS(/obj/item/hand, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_ALT(null, PROC_REF(interaction_alt)), \
	INTERACT_VERB("Discard", PROC_REF(hand_verb_discard), REQ_IN_INVENTORY), \
	INTERACT_VERB("Remove card", PROC_REF(hand_verb_remove_card), REQ_TARGET_STATE(/obj/item/hand/proc/can_remove_card)), \
)

/// Requirement: a free hand for the removed card (the effect's silent stat/reach guard passes here).
/obj/item/hand/proc/can_remove_card(mob/living/carbon/user, atom/target, obj/item/held)
	if(user.stat || !Adjacent(user))
		return TRUE
	if(user.hands_are_full()) // Safety check lest the card disappear into oblivion
		return "your hands are full"
	return TRUE

/// Old attack_self.
/obj/item/hand/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	concealed = !concealed
	update_icon()
	act_message(user, null, others = span_notice("%U% [concealed ? "conceals" : "reveals"] their hand."))
	return TRUE

/obj/item/hand/examine(mob/user)
	. = ..()
	if((!concealed) && length(cards))
		. += "It contains: "
		for(var/datum/playingcard/P in cards)
			. += "\The [P.name]."

/// Old Remove card verb: Remove a card from the hand.
/obj/item/hand/proc/hand_verb_remove_card(mob/living/carbon/user, obj/item/held, datum/interaction/interaction)
	return hand_verb_remove_card_stage(user, held, interaction, list())

/obj/item/hand/proc/hand_verb_remove_card_stage(mob/living/carbon/user, obj/item/held, datum/interaction/interaction, list/card_answers)
	if(user.stat || !Adjacent(user)) return

	if(user.hands_are_full()) // Safety check lest the card disappear into oblivion (the requirement told them)
		return

	var/pickablecards = list()
	for(var/datum/playingcard/P in cards)
		pickablecards[P.name] = P
	if(!("k493" in card_answers))
		open_request(src, /datum/prompt/choice/card_game_review, PROC_REF(hand_verb_remove_card_answered), answerer = user, card_operator = user, card_input = held, card_interaction = interaction, card_answers = card_answers, card_key = "k493", question = "Which card do you want to remove from the hand?", title = "Card Selection", choices = pickablecards , buttons = FALSE)
		return null
	var/pickedcard = card_answers["k493"]
	if(isnull(pickedcard))
		return

	if(!pickedcard || !pickablecards[pickedcard] || !user || !src) return

	var/datum/playingcard/card = pickablecards[pickedcard]

	var/obj/item/hand/H = new(get_turf(src))
	user.put_in_hands(H)
	rel_move(src, nameof(cards), H, nameof(H.cards), card)
	H.parentdeck = src.parentdeck
	H.concealed = src.concealed
	H.update_icon()
	src.update_icon()

	if(!length(cards))
		spent(src, user)
	return

/obj/item/hand
	/// The direction of whoever laid it on a table (the fan follows it), or null.
	var/tmp/direction

DECLARE_APPEARANCE_PROC(/obj/item/hand, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/hand/appearance_overlays()
	. = list()

	var/cardNumber = length(cards)

	if(!cardNumber)
		spent(src)
		return .
	else if(cardNumber > 1)
		name = "hand of cards ([cardNumber])"
		desc = "Some playing cards."
	else
		name = "a playing card"
		desc = "A playing card."



	if(cardNumber == 1)
		var/datum/playingcard/P = cards[1]
		var/image/I = new(src.icon, (concealed ? "[P.back_icon]" : "[P.card_icon]") )
		I.pixel_x += (-5+rand(10))
		I.pixel_y += (-5+rand(10))
		. += I
		return .

	var/offset = FLOOR(20/cardNumber, 1)

	var/matrix/M = matrix()
	if(direction)
		switch(direction)
			if(NORTH)
				M.Translate( 0,  0)
			if(SOUTH)
				M.Translate( 0,  4)
			if(WEST)
				M.Turn(90)
				M.Translate( 3,  0)
			if(EAST)
				M.Turn(90)
				M.Translate(-2,  0)
	var/i = 0
	for(var/datum/playingcard/P in cards)
		var/image/I = new(src.icon, (concealed ? "[P.back_icon]" : "[P.card_icon]") )
		switch(direction)
			if(SOUTH)
				I.pixel_x = 8-(offset*i)
			if(WEST)
				I.pixel_y = -6+(offset*i)
			if(EAST)
				I.pixel_y = 8-(offset*i)
			else
				I.pixel_x = -7+(offset*i)
		I.transform = M
		. += I
		i++


/obj/item/hand/dropped(mob/user, equipping, slot)
	..()
	direction = locate(/obj/structure/table, loc) ? user.dir : null
	update_icon()

/obj/item/hand/pickup(mob/user)
	..()
	src.update_icon()

/obj/item/hand/item_ctrl_click(mob/user)
	if(user.stat || !Adjacent(user))
		return
	hand_verb_discard(user)

/// Old click_alt.
/obj/item/hand/proc/interaction_alt(mob/user, obj/item/held, datum/interaction/interaction)
	if(card_refused(user, can_remove_card(user, src, null)))
		return TRUE
	hand_verb_remove_card(user)
	return TRUE

// A deck, pack or hand owns the card datums it holds.

/obj/item/deck/proc/deck_verb_deal_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = deck_verb_deal_answered_apply(A)
	SStgui.update_uis(src)

/obj/item/deck/proc/deck_verb_deal_answered_apply(datum/act/request/A)
	var/datum/prompt/choice/card_game_review/ask = A.answer
	ask.card_answers[ask.card_key] = ask.value
	return deck_verb_deal_stage(ask.card_operator, ask.card_input, ask.card_interaction, ask.card_answers)

/obj/item/deck/proc/deck_verb_deal_multi_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = deck_verb_deal_multi_answered_apply(A)
	SStgui.update_uis(src)

/obj/item/deck/proc/deck_verb_deal_multi_answered_apply(datum/act/request/A)
	if(istype(A.answer, /datum/prompt/number/card_game_review))
		var/datum/prompt/number/card_game_review/ask = A.answer
		ask.card_answers[ask.card_key] = ask.value
		return deck_verb_deal_multi_stage(ask.card_operator, ask.card_input, ask.card_interaction, ask.card_answers)
	var/datum/prompt/choice/card_game_review/ask = A.answer
	ask.card_answers[ask.card_key] = ask.value
	return deck_verb_deal_multi_stage(ask.card_operator, ask.card_input, ask.card_interaction, ask.card_answers)

/obj/item/deck/proc/deck_verb_search_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = deck_verb_search_answered_apply(A)
	SStgui.update_uis(src)

/obj/item/deck/proc/deck_verb_search_answered_apply(datum/act/request/A)
	var/datum/prompt/checklist/card_game_review/ask = A.answer
	ask.card_answers[ask.card_key] = ask.value
	return deck_verb_search_stage(ask.card_operator, ask.card_input, ask.card_interaction, ask.card_answers)

/obj/item/hand/proc/interaction_item_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = interaction_item_answered_apply(A)
	SStgui.update_uis(src)

/obj/item/hand/proc/interaction_item_answered_apply(datum/act/request/A)
	var/datum/prompt/text/card_game_review/ask = A.answer
	ask.card_answers[ask.card_key] = ask.value
	return interaction_item_stage(ask.card_operator, ask.card_input, ask.card_interaction, ask.card_answers)

/obj/item/hand/proc/hand_verb_discard_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = hand_verb_discard_answered_apply(A)
	SStgui.update_uis(src)

/obj/item/hand/proc/hand_verb_discard_answered_apply(datum/act/request/A)
	if(istype(A.answer, /datum/prompt/number/card_game_review))
		var/datum/prompt/number/card_game_review/ask = A.answer
		ask.card_answers[ask.card_key] = ask.value
		return hand_verb_discard_stage(ask.card_operator, ask.card_input, ask.card_interaction, ask.card_answers)
	var/datum/prompt/choice/card_game_review/ask = A.answer
	ask.card_answers[ask.card_key] = ask.value
	return hand_verb_discard_stage(ask.card_operator, ask.card_input, ask.card_interaction, ask.card_answers)

/obj/item/hand/proc/hand_verb_remove_card_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = hand_verb_remove_card_answered_apply(A)
	SStgui.update_uis(src)

/obj/item/hand/proc/hand_verb_remove_card_answered_apply(datum/act/request/A)
	var/datum/prompt/choice/card_game_review/ask = A.answer
	ask.card_answers[ask.card_key] = ask.value
	return hand_verb_remove_card_stage(ask.card_operator, ask.card_input, ask.card_interaction, ask.card_answers)

/datum/prompt/choice/card_game_review
	timeout = 0
	var/mob/card_operator
	var/obj/card_input
	var/datum/interaction/card_interaction
	var/card_operator_expected = FALSE
	var/card_input_expected = FALSE
	var/card_interaction_expected = FALSE
	var/list/card_answers
	var/card_key

CAPABILITIES(/datum/prompt/choice/card_game_review)
	ref_one(nameof(card_operator), /mob)
	ref_one(nameof(card_input), /obj)
	ref_one(nameof(card_interaction), /datum/interaction)

/datum/prompt/choice/card_game_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_operator = card_operator
	var/obj/captured_input = card_input
	var/datum/interaction/captured_interaction = card_interaction
	card_operator_expected = !isnull(captured_operator)
	card_input_expected = !isnull(captured_input)
	card_interaction_expected = !isnull(captured_interaction)
	rel_clear(src, nameof(card_operator))
	rel_clear(src, nameof(card_input))
	rel_clear(src, nameof(card_interaction))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(card_operator), captured_operator)
	if(captured_input && !QDELETED(captured_input))
		rel_set(src, nameof(card_input), captured_input)
	if(captured_interaction && !QDELETED(captured_interaction))
		rel_set(src, nameof(card_interaction), captured_interaction)

/datum/prompt/choice/card_game_review/recheck_extra()
	if((card_operator_expected && QDELETED(card_operator)) || (card_input_expected && QDELETED(card_input)) || (card_interaction_expected && QDELETED(card_interaction)))
		return "gone"
	if((card_key == "k148" || card_key == "k175") && !isnull(value))
		var/mob/living/selected = value
		if(!istype(selected) || QDELETED(selected))
			return "gone"

/datum/prompt/number/card_game_review
	timeout = 0
	var/card_max = INFINITY
	var/mob/card_operator
	var/obj/card_input
	var/datum/interaction/card_interaction
	var/card_operator_expected = FALSE
	var/card_input_expected = FALSE
	var/card_interaction_expected = FALSE
	var/list/card_answers
	var/card_key

CAPABILITIES(/datum/prompt/number/card_game_review)
	ref_one(nameof(card_operator), /mob)
	ref_one(nameof(card_input), /obj)
	ref_one(nameof(card_interaction), /datum/interaction)

/datum/prompt/number/card_game_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_operator = card_operator
	var/obj/captured_input = card_input
	var/datum/interaction/captured_interaction = card_interaction
	card_operator_expected = !isnull(captured_operator)
	card_input_expected = !isnull(captured_input)
	card_interaction_expected = !isnull(captured_interaction)
	rel_clear(src, nameof(card_operator))
	rel_clear(src, nameof(card_input))
	rel_clear(src, nameof(card_interaction))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(card_operator), captured_operator)
	if(captured_input && !QDELETED(captured_input))
		rel_set(src, nameof(card_input), captured_input)
	if(captured_interaction && !QDELETED(captured_interaction))
		rel_set(src, nameof(card_interaction), captured_interaction)

/datum/prompt/number/card_game_review/recheck_extra()
	if((card_operator_expected && QDELETED(card_operator)) || (card_input_expected && QDELETED(card_input)) || (card_interaction_expected && QDELETED(card_interaction)))
		return "gone"

/datum/prompt/text/card_game_review
	timeout = 0
	var/mob/card_operator
	var/obj/card_input
	var/datum/interaction/card_interaction
	var/card_operator_expected = FALSE
	var/card_input_expected = FALSE
	var/card_interaction_expected = FALSE
	var/list/card_answers
	var/card_key

CAPABILITIES(/datum/prompt/text/card_game_review)
	ref_one(nameof(card_operator), /mob)
	ref_one(nameof(card_input), /obj)
	ref_one(nameof(card_interaction), /datum/interaction)

/datum/prompt/text/card_game_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_operator = card_operator
	var/obj/captured_input = card_input
	var/datum/interaction/captured_interaction = card_interaction
	card_operator_expected = !isnull(captured_operator)
	card_input_expected = !isnull(captured_input)
	card_interaction_expected = !isnull(captured_interaction)
	rel_clear(src, nameof(card_operator))
	rel_clear(src, nameof(card_input))
	rel_clear(src, nameof(card_interaction))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(card_operator), captured_operator)
	if(captured_input && !QDELETED(captured_input))
		rel_set(src, nameof(card_input), captured_input)
	if(captured_interaction && !QDELETED(captured_interaction))
		rel_set(src, nameof(card_interaction), captured_interaction)

/datum/prompt/text/card_game_review/recheck_extra()
	if((card_operator_expected && QDELETED(card_operator)) || (card_input_expected && QDELETED(card_input)) || (card_interaction_expected && QDELETED(card_interaction)))
		return "gone"

/datum/prompt/checklist/card_game_review
	timeout = 0
	var/mob/card_operator
	var/obj/card_input
	var/datum/interaction/card_interaction
	var/card_operator_expected = FALSE
	var/card_input_expected = FALSE
	var/card_interaction_expected = FALSE
	var/list/card_answers
	var/card_key

CAPABILITIES(/datum/prompt/checklist/card_game_review)
	ref_one(nameof(card_operator), /mob)
	ref_one(nameof(card_input), /obj)
	ref_one(nameof(card_interaction), /datum/interaction)

/datum/prompt/checklist/card_game_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_operator = card_operator
	var/obj/captured_input = card_input
	var/datum/interaction/captured_interaction = card_interaction
	card_operator_expected = !isnull(captured_operator)
	card_input_expected = !isnull(captured_input)
	card_interaction_expected = !isnull(captured_interaction)
	rel_clear(src, nameof(card_operator))
	rel_clear(src, nameof(card_input))
	rel_clear(src, nameof(card_interaction))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(card_operator), captured_operator)
	if(captured_input && !QDELETED(captured_input))
		rel_set(src, nameof(card_input), captured_input)
	if(captured_interaction && !QDELETED(captured_interaction))
		rel_set(src, nameof(card_interaction), captured_interaction)

/datum/prompt/checklist/card_game_review/recheck_extra()
	if((card_operator_expected && QDELETED(card_operator)) || (card_input_expected && QDELETED(card_input)) || (card_interaction_expected && QDELETED(card_interaction)))
		return "gone"

/// Display the original UI bound without clamping an accepted raw count before the replay's live guard.
/datum/prompt/number/card_game_review/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, card_max, 0, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box
