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


/// Takes in the items lying on its turf, as space allows.
/obj/structure/safe/proc/take_loose_items(datum/act/timer/A)
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


/// The look (the draw sweep: from its template).
/obj/structure/safe/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][open ? "-open" : ""]")


// TGUI migration. attack_hand opens Safe.tsx; the Topic
// dial/open/retrieve actions move to tgui_act below.
CAPABILITIES(/obj/structure/safe)
	after_init(0, then(PROC_REF(take_loose_items)))
	interface("Safe")
	// the old attackby: put an item in the open safe, or a stethoscope hint while closed
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("open", ui_act("open"), then(PROC_REF(ui_act_open)))
	op("decrement", ui_act("decrement"), then(PROC_REF(ui_act_decrement)))
	op("increment", ui_act("increment"), then(PROC_REF(ui_act_increment)))
	op("retrieve", ui_act("retrieve", arg("ref")), then(PROC_REF(ui_act_retrieve)))
	extend(TAG_UI, needs(req(PROC_REF(user_is_human), because = MSG(safe/not_human))))
	rolls(nameof(tumbler_1_pos), range_of(0, 72))
	rolls(nameof(tumbler_1_open), range_of(0, 72))
	rolls(nameof(tumbler_2_pos), range_of(0, 72))
	rolls(nameof(tumbler_2_open), range_of(0, 72))

MSG_DEF_SELF(safe/not_human, "You can't work the dial.")

/// Only a human works the dial.
/obj/structure/safe/proc/user_is_human(datum/act/op/A)
	return ishuman(A.actor)

/obj/structure/safe/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["dial"] = dial
	data["open"] = !!open
	var/list/c = list()
	FOR_REAL_CONTENTS(var/obj/item/P, src)
		c += list(list("ref" = "ef[P]", "name" = P.name))
	data["contents"] = c
	return data

/obj/structure/safe/proc/ui_act_open(datum/act/op/A)
	var/mob/living/carbon/human/human_user = A.actor
	if(check_unlocked())
		to_chat(human_user, span_notice("You [open ? "close" : "open"] [src]."))
		open = !open
	else
		to_chat(human_user, span_notice("You can't [open ? "close" : "open"] [src], the lock is engaged!"))
	return TRUE

/obj/structure/safe/proc/ui_act_decrement(datum/act/op/A)
	var/mob/living/carbon/human/human_user = A.actor
	var/canhear = 0
	if(human_user.get_type_in_hands(/obj/item/clothing/accessory/stethoscope))
		canhear = 1
	dial = decrement(dial)
	if(dial == tumbler_1_pos + 1 || dial == tumbler_1_pos - 71)
		tumbler_1_pos = decrement(tumbler_1_pos)
		if(canhear)
			to_chat(human_user, span_notice("You hear a [pick("clack", "scrape", "clank")] from 	he [src]."))
		if(tumbler_1_pos == tumbler_2_pos + 37 || tumbler_1_pos == tumbler_2_pos - 35)
			tumbler_2_pos = decrement(tumbler_2_pos)
			if(canhear)
				to_chat(human_user, span_notice("You hear a [pick("click", "chink", "clink")] from 	he [src]."))
				play_sfx(src, SFX_MACHINES_CLICK, 0.4)
		check_unlocked(human_user, canhear)
	return TRUE

/obj/structure/safe/proc/ui_act_increment(datum/act/op/A)
	var/mob/living/carbon/human/human_user = A.actor
	var/canhear = 0
	if(human_user.get_type_in_hands(/obj/item/clothing/accessory/stethoscope))
		canhear = 1
	dial = increment(dial)
	if(dial == tumbler_1_pos - 1 || dial == tumbler_1_pos + 71)
		tumbler_1_pos = increment(tumbler_1_pos)
		if(canhear)
			to_chat(human_user, span_notice("You hear a [pick("clack", "scrape", "clank")] from 	he [src]."))
		if(tumbler_1_pos == tumbler_2_pos - 37 || tumbler_1_pos == tumbler_2_pos + 35)
			tumbler_2_pos = increment(tumbler_2_pos)
			if(canhear)
				to_chat(human_user, span_notice("You hear a [pick("click", "chink", "clink")] from 	he [src]."))
				play_sfx(src, SFX_MACHINES_CLICK, 0.4)
		check_unlocked(human_user, canhear)
	return TRUE

/// The window hands back one of the things it listed.
/obj/structure/safe/proc/ui_act_retrieve(datum/act/op/A, ref)
	var/mob/living/carbon/human/human_user = A.actor
	var/obj/item/P = ui_ref(ref, contents_of(src), /obj/item)
	if(open && P && in_range(src, human_user))
		var/was_stored = P.loc == src
		human_user.put_in_hands(P)
		if(was_stored && P.loc != src)
			space = max(0, space - P.w_class)
	return TRUE


/obj/structure/safe/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(open)
		if(I.w_class + space <= maxspace)
			if(!own_bring_in(src, nameof(contents), I, null, user, TRUE, null, FALSE))
				return OP_OK
			space += I.w_class
			to_chat(user, span_notice("You put [I] in \the [src]."))
			updateUsrDialog(user)
		else
			to_chat(user, span_notice("[I] won't fit in \the [src]."))
	else
		if(istype(I, /obj/item/clothing/accessory/stethoscope))
			to_chat(user, "Hold [I] in one of your hands while you manipulate the dial.")
	return OP_OK


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

/obj/structure/safe/floor/hide(intact)
	invisibility = intact ? INVISIBILITY_ABSTRACT : INVISIBILITY_NONE

/obj/structure/safe/floor/hides_under_flooring()
	return 1
