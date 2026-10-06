GLOBAL_LIST_INIT(has_rocks, list("dirt5", "dirt6", "dirt7", "dirt8", "dirt9"))

CAPABILITIES(/turf/simulated/floor/outdoors/newdirt)
	op("newdirt_hand", hand(), ungated(), stance(I_HELP), label("Dig"), then(PROC_REF(newdirt_hand)))

/// Old attack_hand: loosen rocks, or pile the dirt into a growplot. Outside combat mode only (the interaction's stance); pulling or out of reach, the turf's own touch.
/turf/simulated/floor/outdoors/newdirt/proc/newdirt_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user?.pulling_target())
		return OP_DECLINE
	if(!Adjacent(user))
		return OP_DECLINE
	if(icon_state in GLOB.has_rocks)
		act_message(user, src, MSG_SELF("You loosen rocks from %T%..."), MSG_OTHERS("%U% loosens rocks from %T%..."))
		om_task_timed(user, 5 SECONDS, src, src, PROC_REF(loosen_rocks_done))
		return TRUE
	if(locate_on(src, /obj))
		to_chat(user, span_notice("The [name] isn't clear."))
		return TRUE
	else
		open_request(src, /datum/prompt/yes_no/build_growplot, PROC_REF(growplot_answered), answerer = user)
	return TRUE

/// Re-checked: next to the dirt, and it's still clear.
/datum/prompt/yes_no/build_growplot
	title = "Build growplot?"
	question = "Do you want to build a growplot out of the dirt?"
	timeout = 0
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE

/datum/prompt/yes_no/build_growplot/recheck_extra()
	return locate_on(owner, /obj) ? "not clear" : null

/turf/simulated/floor/outdoors/newdirt/proc/growplot_answered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/mob/user = A.request.answerer
	act_message(user, src, MSG_SELF("You start piling up %T%..."), MSG_OTHERS("%U% starts piling up %T%..."))
	om_task_timed(user, 5 SECONDS, src, src, PROC_REF(pile_done))

/turf/simulated/floor/outdoors/newdirt/proc/loosen_rocks_done()
	if(!(icon_state in GLOB.has_rocks))
		return
	var/obj/item/stack/material/flint/R = new(get_turf(src), rand(1,4))
	R.pixel_x = rand(-6,6)
	R.pixel_y = rand(-6,6)
	icon_state = "dirt0"

/turf/simulated/floor/outdoors/newdirt/proc/pile_done()
	if(!locate_on(src, /obj))
		new /obj/machinery/portable_atmospherics/hydroponics/soil(src)

/turf/simulated/floor/outdoors/newdirt/get_dig_loot_type(mob/user, obj/item/W)
	if(prob(5))
		return /obj/item/stack/material/flint
	if(prob(2))
		return pick(/obj/fruitspawner/potato, /obj/fruitspawner/carrot)
	. = ..()

/turf/simulated/floor/outdoors/dirt/get_dig_loot_type(mob/user, obj/item/W)
	if(prob(10))
		return /obj/item/stack/material/flint
	if(prob(2))
		return pick(/obj/fruitspawner/potato, /obj/fruitspawner/carrot)
	. = ..()

/turf/simulated/floor/outdoors/rocks/get_dig_loot_type(mob/user, obj/item/W)
	return /obj/item/stack/material/flint


/turf/simulated/floor/outdoors/newdirt/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		var/static/list/has_rocks = list("dirt5", "dirt6", "dirt7", "dirt8", "dirt9")
		if(icon_state in has_rocks)
			. += span_notice("There are some rocks in the dirt.")

/obj/structure/flora/tree
	var/sticks = TRUE

/obj/structure/flora/tree/proc/sticks_found(mob/user)
	if(!sticks)
		return
	var/obj/item/stack/material/stick/S = new(get_turf(user), rand(1,3))
	S.pixel_x = rand(-6,6)
	S.pixel_y = rand(-6,6)
	sticks = FALSE

/// Old attack_hand: search for loose sticks (tree_hand, trees.dm).
/obj/structure/flora/tree/proc/interaction_search_sticks(datum/act/op/A)
	var/mob/user = A.actor
	if(sticks)
		act_message(user, src, MSG_SELF("You search %T% for loose sticks..."), MSG_OTHERS("%U% searches %T% for loose sticks..."))
		om_task_timed(user, 5 SECONDS, src, src, PROC_REF(sticks_found), list(user))
	else
		to_chat(user, span_notice("You don't see any loose sticks..."))
	return OP_OK
