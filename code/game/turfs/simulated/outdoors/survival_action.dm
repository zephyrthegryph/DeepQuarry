GLOBAL_LIST_INIT(has_rocks, list("dirt5", "dirt6", "dirt7", "dirt8", "dirt9"))

EXTEND_INTERACTIONS(/turf/simulated/floor/outdoors/newdirt, INTERACT_HAND_UNGATED("Dig", PROC_REF(newdirt_hand)))

/// Old attack_hand: loosen rocks, or pile the dirt into a growplot. Pulling, out of reach or in combat mode, the turf's own touch.
/turf/simulated/floor/outdoors/newdirt/proc/newdirt_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(user?.pulling_target())
		return FALSE
	if(!Adjacent(user))
		return FALSE
	if(!IS_HELPING(user))
		return FALSE
	if(icon_state in GLOB.has_rocks)
		user.visible_message("[user] loosens rocks from \the [src]...", "You loosen rocks from \the [src]...")
		om_do_after(user, 5 SECONDS, src, src, PROC_REF(loosen_rocks_done))
		return TRUE
	if(locate_on(src, /obj))
		to_chat(user, span_notice("The [name] isn't clear."))
		return TRUE
	else
		om_ask(user, /datum/om/prompt/confirm/build_growplot, PROC_REF(growplot_answered))
	return TRUE

/// Re-checked: next to the dirt, and it's still clear.
/datum/om/prompt/confirm/build_growplot
	title = "Build growplot?"
	message = "Do you want to build a growplot out of the dirt?"
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE

/datum/om/prompt/confirm/build_growplot/valid()
	return locate_on(subject, /obj) ? "not clear" : null

/turf/simulated/floor/outdoors/newdirt/proc/growplot_answered(datum/om/prompt/confirm/build_growplot/ask)
	var/mob/user = ask.answerer
	user.visible_message("[user] starts piling up \the [src]...", "You start piling up \the [src]...")
	om_do_after(user, 5 SECONDS, src, src, PROC_REF(pile_done))

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
/obj/structure/flora/tree/proc/interaction_search_sticks(mob/user, obj/item/held, datum/interaction/interaction)
	if(sticks)
		user.visible_message("[user] searches \the [src] for loose sticks...", "You search \the [src] for loose sticks...")
		om_do_after(user, 5 SECONDS, src, src, PROC_REF(sticks_found), list(user))
	else
		to_chat(user, span_notice("You don't see any loose sticks..."))
	return TRUE
