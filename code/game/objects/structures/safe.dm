/*
CONTAINS:
SAFES
FLOOR SAFES
*/

//SAFES
/obj/structure/safe
	resistance_flags = BOMB_PROOF
	name = "safe"
	desc = "A huge chunk of metal with a dial embedded in it. Fine print on the dial reads \"Scarborough Arms - 2 tumbler safe, guaranteed thermite resistant, explosion resistant, and assistant resistant.\""
	icon = 'icons/obj/structures.dmi'
	icon_state = "safe"
	anchored = TRUE
	density = TRUE
	var/open = 0		//is the safe open?
	var/tumbler_1_pos	//the tumbler position- from 0 to 72
	var/tumbler_1_open	//the tumbler position to open at- 0 to 72
	var/tumbler_2_pos
	var/tumbler_2_open
	var/dial = 0		//where is the dial pointing?
	var/space = 0		//the combined w_class of everything in the safe
	var/maxspace = 24	//the maximum combined w_class of stuff in the safe


/obj/structure/safe/Initialize(mapload)
	. = ..()
	tumbler_1_pos = rand(0, 72)
	tumbler_1_open = rand(0, 72)

	tumbler_2_pos = rand(0, 72)
	tumbler_2_open = rand(0, 72)

	if(. != INITIALIZE_HINT_QDEL)
		return INITIALIZE_HINT_LATELOAD

/obj/structure/safe/LateInitialize()
	for(var/obj/item/I in contents_of(loc))
		if(space >= maxspace)
			return
		if(I.w_class + space <= maxspace)
			space += I.w_class
			I.forceMove(src)

/obj/structure/safe/proc/check_unlocked(mob/user, canhear)
	if(user && canhear)
		if(tumbler_1_pos == tumbler_1_open)
			to_chat(user, span_notice("You hear a [pick("tonk", "krunk", "plunk")] from \the [src]."))
		if(tumbler_2_pos == tumbler_2_open)
			to_chat(user, span_notice("You hear a [pick("tink", "krink", "plink")] from \the [src]."))
	if(tumbler_1_pos == tumbler_1_open && tumbler_2_pos == tumbler_2_open)
		if(user) visible_message(span_infoplain(span_bold("[pick("Spring", "Sprang", "Sproing", "Clunk", "Krunk")]!")))
		return 1
	return 0


/obj/structure/safe/proc/decrement(num)
	num -= 1
	if(num < 0)
		num = 71
	return num


/obj/structure/safe/proc/increment(num)
	num += 1
	if(num > 71)
		num = 0
	return num


APPEARANCE_TEMPLATE(/obj/structure/safe, "{initial(icon_state)}{open?-open:}")


// TGUI migration. attack_hand opens Safe.tsx; the Topic
// dial/open/retrieve actions move to tgui_act below.
/obj/structure/safe/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/safe_open_ui,
		/datum/interaction/entry_item/safe_item,
	)
	..()

/datum/interaction/entry_hand/safe_open_ui
	id = "safe_open_ui"
	name = "Use"
	effect = /atom/proc/interaction_open_ui

DECLARE_UI(/obj/structure/safe, "Safe")

UI_DATA_REPLACE(/obj/structure/safe, "dial:num", "merge:ui_data_obj_structure_safe{open:bool,contents:list}")

/// The computed part of /obj/structure/safe's window data (declared on its UI_DATA row).
/obj/structure/safe/proc/ui_data_obj_structure_safe(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["open"] = !!open
	var/list/c = list()
	FOR_REAL_CONTENTS(var/obj/item/P, src)
		c += list(list("ref" = "\ref[P]", "name" = P.name))
	data["contents"] = c
	return data

/obj/structure/safe/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!ishuman(usr))
		return FALSE
	return TRUE

UI_ACT(/obj/structure/safe, "open", ui_act_open)
UI_ACT_PROC(/obj/structure/safe, ui_act_open)
	var/mob/living/carbon/human/human_user = usr
	if(check_unlocked())
		to_chat(human_user, span_notice("You [open ? "close" : "open"] [src]."))
		open = !open
		update_icon()
	else
		to_chat(human_user, span_notice("You can't [open ? "close" : "open"] [src], the lock is engaged!"))
	return TRUE

UI_ACT(/obj/structure/safe, "decrement", ui_act_decrement)
UI_ACT_PROC(/obj/structure/safe, ui_act_decrement)
	var/mob/living/carbon/human/human_user = usr
	var/canhear = 0
	if(human_user.get_type_in_hands(/obj/item/clothing/accessory/stethoscope))
		canhear = 1
	dial = decrement(dial)
	if(dial == tumbler_1_pos + 1 || dial == tumbler_1_pos - 71)
		tumbler_1_pos = decrement(tumbler_1_pos)
		if(canhear)
			to_chat(human_user, span_notice("You hear a [pick("clack", "scrape", "clank")] from \the [src]."))
		if(tumbler_1_pos == tumbler_2_pos + 37 || tumbler_1_pos == tumbler_2_pos - 35)
			tumbler_2_pos = decrement(tumbler_2_pos)
			if(canhear)
				to_chat(human_user, span_notice("You hear a [pick("click", "chink", "clink")] from \the [src]."))
				play_sfx(src, SFX_MACHINES_CLICK, 0.4)
		check_unlocked(human_user, canhear)
	return TRUE

UI_ACT(/obj/structure/safe, "increment", ui_act_increment)
UI_ACT_PROC(/obj/structure/safe, ui_act_increment)
	var/mob/living/carbon/human/human_user = usr
	var/canhear = 0
	if(human_user.get_type_in_hands(/obj/item/clothing/accessory/stethoscope))
		canhear = 1
	dial = increment(dial)
	if(dial == tumbler_1_pos - 1 || dial == tumbler_1_pos + 71)
		tumbler_1_pos = increment(tumbler_1_pos)
		if(canhear)
			to_chat(human_user, span_notice("You hear a [pick("clack", "scrape", "clank")] from \the [src]."))
		if(tumbler_1_pos == tumbler_2_pos - 37 || tumbler_1_pos == tumbler_2_pos + 35)
			tumbler_2_pos = increment(tumbler_2_pos)
			if(canhear)
				to_chat(human_user, span_notice("You hear a [pick("click", "chink", "clink")] from \the [src]."))
				play_sfx(src, SFX_MACHINES_CLICK, 0.4)
		check_unlocked(human_user, canhear)
	return TRUE

UI_ACT(/obj/structure/safe, "retrieve", ui_act_retrieve, UI_ARG_REF("ref", "contents", /obj/item))
UI_ACT_PROC(/obj/structure/safe, ui_act_retrieve)
	var/mob/living/carbon/human/human_user = usr
	var/obj/item/P = params["ref"]
	if(open && P && in_range(src, human_user))
		human_user.put_in_hands(P)
	return TRUE


/// Old attackby: put an item in the open safe, or a stethoscope hint while closed.
/datum/interaction/entry_item/safe_item
	id = "safe_item"
	name = "Use"
	effect = /obj/structure/safe/proc/interaction_item

/obj/structure/safe/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(open)
		if(I.w_class + space <= maxspace)
			space += I.w_class
			user.drop_item()
			I.forceMove(src)
			to_chat(user, span_notice("You put [I] in \the [src]."))
			updateUsrDialog(user)
		else
			to_chat(user, span_notice("[I] won't fit in \the [src]."))
	else
		if(istype(I, /obj/item/clothing/accessory/stethoscope))
			to_chat(user, "Hold [I] in one of your hands while you manipulate the dial.")
	return TRUE


//FLOOR SAFES
/obj/structure/safe/floor
	name = "floor safe"
	icon_state = "floorsafe"
	density = FALSE
	level = 1	//underfloor
	plane = PLATING_PLANE
	layer = ABOVE_UTILITY

/obj/structure/safe/floor/Initialize(mapload)
	. = ..()
	var/turf/T = loc
	if(istype(T) && !T.is_plating())
		hide(1)
	update_icon()

/obj/structure/safe/floor/hide(intact)
	invisibility = intact ? INVISIBILITY_ABSTRACT : INVISIBILITY_NONE

/obj/structure/safe/floor/hides_under_flooring()
	return 1
