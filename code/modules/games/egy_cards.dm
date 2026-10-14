//Sprites ported from Eris

/obj/item/deck/egy
	name = "deck of EGY playing cards"
	desc = "A simple deck of EGY playing cards. Be the first to lose all cards, but forget not to declare: EGY on your second to last trick."
	icon_state = "deck3"

CAPABILITIES(/obj/item/deck/egy)
	owns_many(nameof(cards), starts = PROC_REF(starting_cards))




/// The cards it starts with (owns_many(starts =)).
/obj/item/deck/egy/proc/starting_cards()
	var/datum/playingcard/P
	//Universal cards
	. = list()
	for(var/i=0; i<=3; i++)
		P = new()
		P.name = "\improper Wild +4"
		P.card_icon = "+4"
		P.back_icon = "deck1"
		. += P
	for(var/i=0; i<=3; i++)
		P = new()
		P.name = "\improper Wildcard"
		P.card_icon = "colorswap"
		P.back_icon = "deck1"
		. += P
	//Colour cards
	for(var/colour in list("red", "yellow", "blue", "green"))
		//Specials
		for(var/special in list("reverse","+2","skip"))
			//2 of each
			for(var/i=0; i<=1; i++)
				P = new()
				P.name = "\improper [colour] [special]"
				P.card_icon = "[colour]_[special]"
				P.back_icon = "deck1"
				. += P
		//Number cards
		for(var/number in list("0","1","2","3","4","5","6","7","8","9"))
			//2 of each for 0-9, using 2 of "0" per Crow's request
			for(var/i=0; i<=1; i++)
				P = new()
				P.name = "\improper [colour] [number]"
				P.card_icon = "[colour]_[number]"
				P.back_icon = "deck1"
				. += P
