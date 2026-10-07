/*
 * This is a playing card deck based off of the Rider-Waite Tarot Deck.
 */
/obj/item/deck/tarot
	name = "deck of tarot cards"
	desc = "For all your occult needs!"
	icon_state = "deck_tarot"

/obj/item/deck/tarot/Initialize(mapload)
	. = ..()

	var/datum/playingcard/P
	for(var/name in list("Fool","Magician","High Priestess","Empress","Emperor","Hierophant","Lovers","Chariot","Strength","Hermit","Wheel of Fortune","Justice","Hanged Man","Death","Temperance","Devil","Tower","Star","Moon","Sun","Judgement","World"))
		P = new()
		P.name = "[name]"
		P.card_icon = "tarot_major"
		P.back_icon = "card_back_tarot"
		rel_add(src, nameof(cards), P)
	for(var/suit in list("wands","pentacles","cups","swords"))
		for(var/number in list("ace","two","three","four","five","six","seven","eight","nine","ten","page","knight","queen","king"))
			P = new()
			P.name = "[number] of [suit]"
			P.card_icon = "tarot_[suit]"
			P.back_icon = "card_back_tarot"
			rel_add(src, nameof(cards), P)

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

///Fluff item, using a separate item rather than a subitem to customise New()

/obj/item/deck/dark_tarot
	name = "dark rose tarot deck"
	desc = "A limited edition tarot deck for the scene-girl inclined!"
	icon_state = "dark_tarot"

/obj/item/deck/dark_tarot/Initialize(mapload)
	. = ..()

	var/datum/playingcard/P
	for(var/name in list("fool","magician","high priestess","empress","emperor","hierophant","lovers","chariot","strength","hermit","wheel of fortune","justice","hanged man","death","temperance","devil","tower","star","moon","sun","judgement","world","white dragon with blue eyes","charred lizard","dark lotus","bash","reverse","rules","acid","abyss","maw"))
		P = new()
		P.name = "[name]"
		if(name == "high priestess")
			P.card_icon = "dark_high_priestess"
		else if(name == "wheel of fortune")
			P.card_icon = "dark_wheel"
		else if(name == "hanged man")
			P.card_icon = "dark_hanged"
		else if(name == "white dragon with blue eyes")
			P.card_icon = "dark_dragon"
		else if(name == "charred lizard")
			P.card_icon = "dark_lizard"
		else if(name == "dark lotus")
			P.card_icon = "dark_lotus"
		else
			P.card_icon = "dark_[name]"
		P.back_icon = "dark_back_tarot"
		rel_add(src, nameof(cards), P)
	for(var/suit in list("wands","pentacles","cups","swords"))
		for(var/number in list("ace","two","three","four","five","six","seven","eight","nine","ten","page","knight","queen","king"))
			P = new()
			P.name = "[number] of [suit]"
			P.card_icon = "dark_[suit]"
			P.back_icon = "dark_back_tarot"
			rel_add(src, nameof(cards), P)

/obj/item/deck/dark_tarot/shuffle(mob/user)
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
