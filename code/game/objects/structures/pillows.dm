//Pillows with sprites ported from skyrat

/obj/item/bedsheet/pillow
	name = "pillow"
	desc = "A surprisingly soft stuffed pillow."
	icon = 'icons/obj/pillows.dmi'
	icon_state = "pillow_pink_square"
	slot_flags = 0
	var/pile_type = "/obj/structure/bed/pillowpile"
	throw_range = 7
	special_handling = TRUE

/obj/item/bedsheet/pillow/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	user.drop_item()
	if(icon_state == initial(icon_state))
		icon_state = "[icon_state]_placed"
	add_fingerprint(user)

/obj/item/bedsheet/pillow/pickup(mob/user)
	..()
	icon_state = initial(icon_state)

EXTEND_INTERACTIONS(/obj/item/bedsheet/pillow, INTERACT_ITEM(null, PROC_REF(pillow_interaction_item)))

/// Old attackby.
/obj/item/bedsheet/pillow/proc/pillow_interaction_item(mob/user, obj/item/component, datum/interaction/interaction)
	if (istype(component,src))
		to_chat(user, span_notice("You assemble a pillow pile!"))
		user.drop_item()
		consume(component, user)
		var/turf/T = get_turf(src)
		new pile_type(T)
		consume(src, user)
	else
		to_chat(user, span_notice("You can't assemble a pillow pile out of mismatched stuff, it'd look hideous!"))
	return INTERACTION_HANDLED_PASS

//Pillow Piles, they're piles of pillows! 	layer = BELOW_MOB_LAYER

/obj/structure/bed/pillowpile
	name = "pillow pile"
	desc = "A massive pile of pillows!"
	icon = 'icons/obj/pillows.dmi'
	icon_state = "pillowpile_large_pink"
	var/pillowpilefront = "/obj/structure/bed/pillowpilefront"
	var/sourcepillow = "/obj/item/bedsheet/pillow"
	flippable = FALSE

/obj/structure/bed/pillowpilefront
	name = "pillow pile"
	desc = "A massive pile of pillows!"
	icon = 'icons/obj/pillows.dmi'
	icon_state = "pillowpile_large_pink_overlay"
	layer = ABOVE_MOB_LAYER
	plane = MOB_PLANE
	var/sourcepillow = "/obj/item/bedsheet/pillow"

/obj/structure/bed/pillowpile/Initialize(mapload)
	. = ..()
	var/turf/T = get_turf(src)
	new pillowpilefront(T)

/obj/structure/bed/pillowpilefront/update_icon()
	return

/obj/structure/bed/pillowpile/update_icon()
	return

/obj/structure/bed/pillowpile/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/pillowpile_hand,
	)

/// Old attack_hand: disassemble the pile.
/datum/interaction/entry_hand/pillowpile_hand
	id = "pillowpile_hand"
	name = "Disassemble"
	effect = /obj/structure/bed/pillowpile/proc/interaction_hand

/obj/structure/bed/pillowpile/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("Now disassembling the large pillow pile..."))
	om_do_after(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_hand_timed_done), done_args = list(user))
	return TRUE

/obj/structure/bed/pillowpile/proc/attack_hand_timed_done(mob/user)
	to_chat(user, span_notice("You dissasembled the large pillow pile!"))
	replace_with(src, sourcepillow)

/obj/structure/bed/pillowpilefront/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/pillowpilefront_hand,
	)

/// Old attack_hand: disassemble the front piece.
/datum/interaction/entry_hand/pillowpilefront_hand
	id = "pillowpilefront_hand"
	name = "Disassemble"
	effect = /obj/structure/bed/pillowpilefront/proc/interaction_hand

/obj/structure/bed/pillowpilefront/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("Now disassembling the front of the pillow pile..."))
	om_do_after(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_hand_timed_done2), done_args = list(user))
	return TRUE

/obj/structure/bed/pillowpilefront/proc/attack_hand_timed_done2(mob/user)
	to_chat(user, span_notice("You dissasembled the the front of the pillow pile!"))
	replace_with(src, sourcepillow)

//Colours

//teal

/obj/item/bedsheet/pillow/teal
	icon_state = "pillow_teal_square"
	pile_type = "/obj/structure/bed/pillowpile/teal"

/obj/structure/bed/pillowpile/teal
	icon_state = "pillowpile_large_teal"
	pillowpilefront = "/obj/structure/bed/pillowpilefront/teal"
	sourcepillow = "/obj/item/bedsheet/pillow/teal"

/obj/structure/bed/pillowpilefront/teal
	icon_state = "pillowpile_large_teal_overlay"
	sourcepillow = "/obj/item/bedsheet/pillow/teal"

//yellow

/obj/item/bedsheet/pillow/yellow
	icon_state = "pillow_yellow_square"
	pile_type = "/obj/structure/bed/pillowpile/yellow"

/obj/structure/bed/pillowpile/yellow
	icon_state = "pillowpile_large_yellow"
	pillowpilefront = "/obj/structure/bed/pillowpilefront/yellow"
	sourcepillow = "/obj/item/bedsheet/pillow/yellow"

/obj/structure/bed/pillowpilefront/yellow
	icon_state = "pillowpile_large_yellow_overlay"
	sourcepillow = "/obj/item/bedsheet/pillow/yellow"

//white

/obj/item/bedsheet/pillow/white
	icon_state = "pillow_white_square"
	pile_type = "/obj/structure/bed/pillowpile/white"

/obj/structure/bed/pillowpile/white
	icon_state = "pillowpile_large_white"
	pillowpilefront = "/obj/structure/bed/pillowpilefront/white"
	sourcepillow = "/obj/item/bedsheet/pillow/white"

/obj/structure/bed/pillowpilefront/white
	icon_state = "pillowpile_large_white_overlay"
	sourcepillow = "/obj/item/bedsheet/pillow/white"

//black

/obj/item/bedsheet/pillow/black
	icon_state = "pillow_black_square"
	pile_type = "/obj/structure/bed/pillowpile/black"

/obj/structure/bed/pillowpile/black
	icon_state = "pillowpile_large_black"
	pillowpilefront = "/obj/structure/bed/pillowpilefront/black"
	sourcepillow = "/obj/item/bedsheet/pillow/black"

/obj/structure/bed/pillowpilefront/black
	icon_state = "pillowpile_large_black_overlay"
	sourcepillow = "/obj/item/bedsheet/pillow/black"

//green

/obj/item/bedsheet/pillow/green
	icon_state = "pillow_green_square"
	pile_type = "/obj/structure/bed/pillowpile/green"

/obj/structure/bed/pillowpile/green
	icon_state = "pillowpile_large_green"
	pillowpilefront = "/obj/structure/bed/pillowpilefront/green"
	sourcepillow = "/obj/item/bedsheet/pillow/green"

/obj/structure/bed/pillowpilefront/green
	icon_state = "pillowpile_large_green_overlay"
	sourcepillow = "/obj/item/bedsheet/pillow/green"

//red

/obj/item/bedsheet/pillow/red
	icon_state = "pillow_red_square"
	pile_type = "/obj/structure/bed/pillowpile/red"

/obj/structure/bed/pillowpile/red
	icon_state = "pillowpile_large_red"
	pillowpilefront = "/obj/structure/bed/pillowpilefront/red"
	sourcepillow = "/obj/item/bedsheet/pillow/red"

/obj/structure/bed/pillowpilefront/red
	icon_state = "pillowpile_large_red_overlay"
	sourcepillow = "/obj/item/bedsheet/pillow/red"

//orange

/obj/item/bedsheet/pillow/orange
	icon_state = "pillow_orange_square"
	pile_type = "/obj/structure/bed/pillowpile/orange"

/obj/structure/bed/pillowpile/orange
	icon_state = "pillowpile_large_orange"
	pillowpilefront = "/obj/structure/bed/pillowpilefront/orange"
	sourcepillow = "/obj/item/bedsheet/pillow/orange"

/obj/structure/bed/pillowpilefront/orange
	icon_state = "pillowpile_large_orange_overlay"
	sourcepillow = "/obj/item/bedsheet/pillow/orange"

//crafting

/datum/crafting_recipe/pillowpink
	name = "pillow (pink)"
	result = /obj/item/bedsheet/pillow
	reqs = list(
		list(/obj/item/stack/material/cloth = 6)
	)
	time = 60
	category = CAT_MISC

/datum/crafting_recipe/pillowteal
	name = "pillow (teal)"
	result = /obj/item/bedsheet/pillow/teal
	reqs = list(
		list(/obj/item/stack/material/cloth = 6)
	)
	time = 60
	category = CAT_MISC

/datum/crafting_recipe/pillowwhite
	name = "pillow (white)"
	result = /obj/item/bedsheet/pillow/white
	reqs = list(
		list(/obj/item/stack/material/cloth = 6)
	)
	time = 60
	category = CAT_MISC

/datum/crafting_recipe/pillowblack
	name = "pillow (black)"
	result = /obj/item/bedsheet/pillow/black
	reqs = list(
		list(/obj/item/stack/material/cloth = 6)
	)
	time = 60
	category = CAT_MISC

/datum/crafting_recipe/pillowgreen
	name = "pillow (green)"
	result = /obj/item/bedsheet/pillow/green
	reqs = list(
		list(/obj/item/stack/material/cloth = 6)
	)
	time = 60
	category = CAT_MISC

/datum/crafting_recipe/pillowyellow
	name = "pillow (yellow)"
	result = /obj/item/bedsheet/pillow/yellow
	reqs = list(
		list(/obj/item/stack/material/cloth = 6)
	)
	time = 60
	category = CAT_MISC

/datum/crafting_recipe/pillowred
	name = "pillow (red)"
	result = /obj/item/bedsheet/pillow/red
	reqs = list(
		list(/obj/item/stack/material/cloth = 6)
	)
	time = 60
	category = CAT_MISC

/datum/crafting_recipe/pilloworange
	name = "pillow (orange)"
	result = /obj/item/bedsheet/pillow/orange
	reqs = list(
		list(/obj/item/stack/material/cloth = 6)
	)
	time = 60
	category = CAT_MISC
