/*
CONTAINS:
BEDSHEETS
LINEN BINS
*/

/obj/item/bedsheet
	name = "bedsheet"
	desc = "A surprisingly soft linen bedsheet."
	icon = 'icons/obj/items.dmi'
	icon_state = "sheet"
	slot_flags = SLOT_BACK
	plane = MOB_PLANE
	layer = BELOW_MOB_LAYER
	throwforce = 1
	throw_speed = 1
	throw_range = 2
	w_class = ITEMSIZE_SMALL
	drop_sound = SFX_ITEMS_DROP_CLOTHING
	pickup_sound = SFX_ITEMS_PICKUP_CLOTHING
	resistance_flags = FLAMMABLE

/// Custom nouns to act as the subject of dreams.
TYPE_TABLE_DECLARE(/obj/item/bedsheet, bedsheet_dream_messages, list("white"))

/obj/item/bedsheet/Initialize(mapload)
	. = ..()
	make_rotatable(only_flip = TRUE)

/// Old attack_self: lay the sheet out or pick its layer back up. A kind with its own use (a pillow) re-declares the op.
/obj/item/bedsheet/proc/bedsheet_self(datum/act/op/A)
	var/mob/user = A.actor
	user.drop_item()
	if(layer == initial(layer))
		layer = ABOVE_MOB_LAYER
	else
		reset_plane_and_layer()
	add_fingerprint(user)
	return OP_OK

CAPABILITIES(/obj/item/bedsheet)
	op("use_item", item(/obj/item), when(req(PROC_REF(held_is_sharp))), begins(MSG(bedsheet/cutting)), wait(5 SECONDS), then(PROC_REF(cut_up)))
	op("lay_out", in_hand(), label("Lay out"), then(PROC_REF(bedsheet_self)))

MSG_DEF(bedsheet/cutting, span_notice("You begin cutting up %T% with %I%."), span_infoplain(span_bold("%U%") + " begins cutting up %T% with %I%."))

/obj/item/bedsheet/proc/held_is_sharp(datum/act/op/A)
	return (is_sharp(A.held)) ? null : MSG(req_failed)

/obj/item/bedsheet/proc/cut_up(datum/act/op/A)
	return cut_into_rags(A.actor)

/// The cutting itself: the sheet is consumed and rags are left in its place (FALSE when it can't be let go).
/obj/item/bedsheet/proc/cut_into_rags(mob/user)
	var/turf/T = drop_location()
	var/message = span_notice("You cut [src] into pieces!")
	if(!consume(src, user))
		return FALSE
	to_chat(user, message)
	for(var/i in 1 to rand(2,5))
		new /obj/item/reagent_containers/glass/rag(T)
	return TRUE

/obj/item/bedsheet/ghosts_can_use_rotate_verbs()
	return CONFIG_GET(flag/ghost_interaction)

/obj/item/bedsheet/blue
	icon_state = "sheetblue"

TYPE_TABLE(/obj/item/bedsheet/blue, bedsheet_dream_messages, list("blue"))

/obj/item/bedsheet/green
	icon_state = "sheetgreen"

TYPE_TABLE(/obj/item/bedsheet/green, bedsheet_dream_messages, list("green"))

/obj/item/bedsheet/orange
	icon_state = "sheetorange"

TYPE_TABLE(/obj/item/bedsheet/orange, bedsheet_dream_messages, list("orange"))

/obj/item/bedsheet/purple
	icon_state = "sheetpurple"

TYPE_TABLE(/obj/item/bedsheet/purple, bedsheet_dream_messages, list("purple"))

/obj/item/bedsheet/rainbow
	icon_state = "sheetrainbow"

TYPE_TABLE(/obj/item/bedsheet/rainbow, bedsheet_dream_messages, list("red", "orange", "yellow", "green", "blue", "purple", "a rainbow"))

/obj/item/bedsheet/red
	icon_state = "sheetred"

TYPE_TABLE(/obj/item/bedsheet/red, bedsheet_dream_messages, list("red"))

/obj/item/bedsheet/yellow
	icon_state = "sheetyellow"

TYPE_TABLE(/obj/item/bedsheet/yellow, bedsheet_dream_messages, list("yellow"))

/obj/item/bedsheet/mime
	icon_state = "sheetmime"

TYPE_TABLE(/obj/item/bedsheet/mime, bedsheet_dream_messages, list("silence", "gestures", "a pale face", "a gaping mouth", "the mime"))

/obj/item/bedsheet/clown
	icon_state = "sheetclown"
	item_state = "sheetrainbow"

TYPE_TABLE(/obj/item/bedsheet/clown, bedsheet_dream_messages, list("honk", "laughter", "a prank", "a joke", "a smiling face", "the clown"))

/obj/item/bedsheet/captain
	icon_state = "sheetcaptain"

TYPE_TABLE(/obj/item/bedsheet/captain, bedsheet_dream_messages, list("authority", "a golden ID", "sunglasses", "a green disc", "an antique gun", "the captain"))

/obj/item/bedsheet/rd
	icon_state = "sheetrd"

TYPE_TABLE(/obj/item/bedsheet/rd, bedsheet_dream_messages, list("authority", "a silvery ID", "a bomb", "a mech", "a facehugger", "maniacal laughter", "the research director"))

/obj/item/bedsheet/medical
	name = "medical blanket"
	desc = "It's a sterilized* blanket commonly used in the Medbay.  *Sterilization is voided if a virologist is present onboard the station."
	icon_state = "sheetmedical"

TYPE_TABLE(/obj/item/bedsheet/medical, bedsheet_dream_messages, list("healing", "life", "surgery", "a doctor"))

/obj/item/bedsheet/hos
	icon_state = "sheethos"

TYPE_TABLE(/obj/item/bedsheet/hos, bedsheet_dream_messages, list("authority", "a silvery ID", "handcuffs", "a baton", "a flashbang", "sunglasses", "the head of security"))

/obj/item/bedsheet/hop
	icon_state = "sheethop"

TYPE_TABLE(/obj/item/bedsheet/hop, bedsheet_dream_messages, list("authority", "a silvery ID", "obligation", "a computer", "an ID", "a corgi", "the head of personnel"))

/obj/item/bedsheet/ce
	icon_state = "sheetce"

TYPE_TABLE(/obj/item/bedsheet/ce, bedsheet_dream_messages, list("authority", "a silvery ID", "the engine", "power tools", "an APC", "a parrot", "the chief engineer"))

/obj/item/bedsheet/brown
	icon_state = "sheetbrown"

TYPE_TABLE(/obj/item/bedsheet/brown, bedsheet_dream_messages, list("brown"))

/obj/item/bedsheet/ian
	icon_state = "sheetian"

TYPE_TABLE(/obj/item/bedsheet/ian, bedsheet_dream_messages, list("a dog", "a corgi", "woof", "bark", "arf"))

/obj/item/bedsheet/double
	icon_state = "doublesheet"
	item_state = "sheet"

/obj/item/bedsheet/bluedouble
	icon_state = "doublesheetblue"
	item_state = "sheetblue"

/obj/item/bedsheet/greendouble
	icon_state = "doublesheetgreen"
	item_state = "sheetgreen"

/obj/item/bedsheet/orangedouble
	icon_state = "doublesheetorange"
	item_state = "sheetorange"

/obj/item/bedsheet/purpledouble
	icon_state = "doublesheetpurple"
	item_state = "sheetpurple"

/obj/item/bedsheet/rainbowdouble //all the way across the sky.
	icon_state = "doublesheetrainbow"
	item_state = "sheetrainbow"

/obj/item/bedsheet/reddouble
	icon_state = "doublesheetred"
	item_state = "sheetred"

/obj/item/bedsheet/yellowdouble
	icon_state = "doublesheetyellow"
	item_state = "sheetyellow"

/obj/item/bedsheet/mimedouble
	icon_state = "doublesheetmime"
	item_state = "sheetmime"

/obj/item/bedsheet/clowndouble
	icon_state = "doublesheetclown"
	item_state = "sheetrainbow"

/obj/item/bedsheet/captaindouble
	icon_state = "doublesheetcaptain"
	item_state = "sheetcaptain"

/obj/item/bedsheet/rddouble
	icon_state = "doublesheetrd"
	item_state = "sheetrd"

/obj/item/bedsheet/hosdouble
	icon_state = "doublesheethos"
	item_state = "sheethos"

/obj/item/bedsheet/hopdouble
	icon_state = "doublesheethop"
	item_state = "sheethop"

/obj/item/bedsheet/cedouble
	icon_state = "doublesheetce"
	item_state = "sheetce"

/obj/item/bedsheet/browndouble
	icon_state = "doublesheetbrown"
	item_state = "sheetbrown"

/obj/item/bedsheet/iandouble
	icon_state = "doublesheetian"
	item_state = "sheetian"

/obj/structure/bedsheetbin
	name = "linen bin"
	desc = "A linen bin. It looks rather cosy."
	icon = 'icons/obj/structures.dmi'
	icon_state = "linenbin-full"
	anchored = TRUE
	var/amount = 20
	var/list/sheets = list() // ALLOW(instance_list): d: the bin's live stock
	var/obj/item/hidden


/obj/structure/bedsheetbin/examine(mob/user)
	. = ..()

	if(amount < 1)
		. += "There are no bed sheets in the bin."
	else if(amount == 1)
		. += "There is one bed sheet in the bin."
	else
		. += "There are [amount] bed sheets in the bin."

/obj/structure/bedsheetbin/proc/appearance_fill()
	if(amount == 0)
		return "empty"
	if(amount <= (initial(amount) / 2))
		return "half"
	return "full"

/// The look (the draw sweep: from its template).
/obj/structure/bedsheetbin/draw(datum/look/look)
	..()
	look.state("linenbin-[appearance_fill()]")


CAPABILITIES(/obj/structure/bedsheetbin)
	op("bedsheetbin_item", item(/obj/item), then(PROC_REF(interaction_item)))
	op("bedsheetbin_hand", hand(), then(PROC_REF(interaction_hand)))
	op("take_sheet", tk(), label("Take sheet"), then(PROC_REF(interaction_tk)))

/// Old attackby: put a bedsheet in, or hide a small item among the sheets.
/obj/structure/bedsheetbin/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/bedsheet))
		if(!own_bring_in(src, nameof(sheets), I, null, user, TRUE, null, FALSE))
			return TRUE
		rel_add(src, nameof(sheets), I)
		amount++
		to_chat(user, span_notice("You put [I] in [src]."))
	else if(amount && !hidden() && I.w_class < ITEMSIZE_LARGE)	//make sure there's sheets to hide it among, make sure nothing else is hidden in there.
		if(!own_bring_in(src, nameof(hidden), I, null, user, TRUE, null, FALSE))
			return TRUE
		rel_set(src, nameof(hidden), I)
		to_chat(user, span_notice("You hide [I] among the sheets."))
	return TRUE

/// Old attack_hand: take a bedsheet out (and anything hidden among them).
/obj/structure/bedsheetbin/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(amount >= 1)
		amount--

		var/obj/item/bedsheet/B
		if(sheets.len > 0)
			B = sheets[sheets.len]
			rel_remove(src, nameof(sheets), B)

		else
			B = new /obj/item/bedsheet(loc)

		B.forceMove(user.loc)
		user.put_in_hands(B)
		to_chat(user, span_notice("You take [B] out of [src]."))

		if(hidden())
			hidden().forceMove(user.loc)
			to_chat(user, span_notice("[hidden()] falls out of [B]!"))
			rel_clear(src, nameof(hidden))


	add_fingerprint(user)
	return TRUE

/// Old attack_tk: pull a sheet (and anything hidden among them) out at range.
/obj/structure/bedsheetbin/proc/interaction_tk(datum/act/op/A)
	var/mob/user = A.actor
	if(amount >= 1)
		amount--

		var/obj/item/bedsheet/B
		if(sheets.len > 0)
			B = sheets[sheets.len]
			rel_remove(src, nameof(sheets), B)

		else
			B = new /obj/item/bedsheet(loc)

		B.forceMove(loc)
		to_chat(user, span_notice("You telekinetically remove [B] from [src]."))

		if(hidden())
			hidden().forceMove(loc)
			rel_clear(src, nameof(hidden))


	add_fingerprint(user)
	return TRUE

/obj/item/bedsheet/cosmos
	icon = 'icons/obj/items.dmi'
	icon_state = "sheetcosmos"

/obj/item/bedsheet/cosmosdouble
	icon = 'icons/obj/items.dmi'
	icon_state = "doublesheetcosmos"

/obj/item/bedsheet/pirate
	icon = 'icons/obj/items.dmi'
	icon_state = "sheetpirate"

/obj/item/bedsheet/piratedouble
	icon = 'icons/obj/items.dmi'
	icon_state = "doublesheetpirate"

/// Relation view: hidden (reads null once it is gone).
/obj/structure/bedsheetbin/proc/hidden() as /obj/item
	return hidden
