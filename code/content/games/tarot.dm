/*
 * This is a playing card deck based off of the Rider-Waite Tarot Deck.
 */
/obj/item/deck/tarot
	name = "deck of tarot cards"
	desc = "For all your occult needs!"
	icon_state = "deck_tarot"

CAPABILITIES(/obj/item/deck/tarot)
	owns_many(nameof(cards), starts = PROC_REF(starting_cards))

/// The cards it starts with (owns_many(starts =)).
/obj/item/deck/tarot/proc/starting_cards()

	var/datum/playingcard/P
	. = list()
	for(var/name in list("Fool","Magician","High Priestess","Empress","Emperor","Hierophant","Lovers","Chariot","Strength","Hermit","Wheel of Fortune","Justice","Hanged Man","Death","Temperance","Devil","Tower","Star","Moon","Sun","Judgement","World"))
		P = new()
		P.name = "[name]"
		P.set_card_icon("tarot_major")
		P.set_back_icon("card_back_tarot")
		. += P
	for(var/suit in list("wands","pentacles","cups","swords"))
		for(var/number in list("ace","two","three","four","five","six","seven","eight","nine","ten","page","knight","queen","king"))
			P = new()
			P.name = "[number] of [suit]"
			P.set_card_icon("tarot_[suit]")
			P.set_back_icon("card_back_tarot")
			. += P

/obj/item/deck/tarot/shuffle(mob/user)
	if (COOLDOWN_FINISHED(src, shuffle_cooldown))
		var/list/unshuffled = rel_take_all(src, nameof(cards))
		while(length(unshuffled))
			var/datum/playingcard/P = pick(unshuffled)
			unshuffled -= P
			P.name = replacetext(P.name," reversed","")
			if(prob(50))
				P.name += " reversed"
			rel_add(src, nameof(cards), P)
		play_sfx(src, SFX_ITEMS_CARDSHUFFLE)
		act_message(user, src, others = "%U% shuffles %T%.")
		COOLDOWN_START(src, shuffle_cooldown, 1 SECOND)
	else
		return
