//I still dont think this should be a closet but whatever
/obj/structure/fireaxecabinet
	name = "fire axe cabinet"
	desc = "There is small label that reads \"For Emergency use only\" along with details for safe use of the axe. As if."
	var/obj/item/material/twohanded/fireaxe/fireaxe
	icon = 'icons/obj/closet.dmi'	//Not bothering to move icons out for now. But its dumb still.
	icon_state = "fireaxe1000"
	layer = ABOVE_WINDOW_LAYER
	anchored = TRUE
	density = FALSE
	flags = WALL_ITEM
	var/open = 0
	var/hitstaken = 0
	var/locked = 1
	var/smashed = 0
	var/starts_with_axe = TRUE

/obj/structure/fireaxecabinet/Initialize(mapload)
	. = ..()
	if(starts_with_axe)
		fireaxe = new /obj/item/material/twohanded/fireaxe()
	update_icon()

/obj/structure/fireaxecabinet/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/fireaxecabinet_item,
		/datum/interaction/entry_hand/fireaxecabinet_hand,
	)
	into += dq_interaction_from_spec(type, INTERACT_SILICON("Toggle lock", PROC_REF(fireaxecabinet_silicon_lock)))
	into += dq_interaction_from_spec(type, INTERACT_TK(null, PROC_REF(interaction_tk)))
	into += dq_interaction_from_spec(type, INTERACT_VERB("Open/Close", PROC_REF(toggle_openness_effect)))
	into += dq_interaction_from_spec(type, INTERACT_VERB("Remove Fire Axe", PROC_REF(remove_fire_axe_effect)))
	..()

/// Old attackby: unlock/lock the case, smash the glass, or take/replace the axe, depending on state and item.
/datum/interaction/entry_item/fireaxecabinet_item
	id = "fireaxecabinet_item"
	name = "Use"
	effect = /obj/structure/fireaxecabinet/proc/interaction_item

/obj/structure/fireaxecabinet/proc/interaction_item(mob/user, obj/item/O, datum/interaction/interaction)  //Marker -Agouri
	//..() //That's very useful, Erro

	// This could stand to be put further in, made better, etc. but fuck you. Fuck whoever
	// wrote this code. Fuck everything about this object. I hope you step on a Lego.
	user.setClickCooldown(10)
	// Seriously why the fuck is this even a closet aghasjdhasd I hate you

	if (isrobot(user) || locked)
		if(O.has_tool_quality(TOOL_MULTITOOL))
			to_chat(user, span_warning("Resetting circuitry..."))
			playsound(src, 'sound/machines/lockreset.ogg', 50, 1)
			use_tool(user, O, src, delay = 2 SECONDS, quality = TOOL_MULTITOOL, volume = 0, receiver = src, on_done = PROC_REF(attackby_tool_done), done_args = list(user))
			return TRUE
		else if(istype(O, /obj/item))
			var/obj/item/W = O
			if(smashed || open)
				if(open)
					toggle_close_open()
				return TRUE
			else
				playsound(src, 'sound/effects/Glasshit.ogg', 100, 1) //We don't want this playing every time
			if(W.force < 15)
				to_chat(user, span_notice("The cabinet's protective glass glances off the hit."))
			else
				hitstaken++
				if(hitstaken == 4)
					playsound(src, 'sound/effects/Glassbr3.ogg', 100, 1) //Break cabinet, receive goodies. Cabinet's fucked for life after that.
					smashed = 1
					locked = 0
					open= 1
			update_icon()
		return TRUE
	if (istype(O, /obj/item/material/twohanded/fireaxe) && open)
		if(!fireaxe)
			if(O:wielded)
				O:wielded = 0
				O.update_icon()
			fireaxe = O
			user.remove_from_mob(O)
			O.forceMove(src)
			to_chat(user, span_notice("You place the fire axe back in the [name]."))
			update_icon()
		else
			if(smashed)
				return TRUE
			else
				toggle_close_open()
	else
		if(smashed)
			return TRUE
		if(O.has_tool_quality(TOOL_MULTITOOL))
			if(open)
				open = 0
				update_icon()
				flick("[icon_state]closing", src)
				return TRUE
			else
				to_chat(user, span_warning("Resetting circuitry..."))
				playsound(src, 'sound/machines/lockenable.ogg', 50, 1)
				use_tool(user, O, src, delay = 2 SECONDS, quality = TOOL_MULTITOOL, volume = 0, receiver = src, on_done = PROC_REF(attackby_tool_done2), done_args = list(user))
				return TRUE
		else
			toggle_close_open()
	return TRUE

/obj/structure/fireaxecabinet/proc/attackby_tool_done(mob/user)
	locked = 0
	to_chat(user, span_warning("You disable the locking modules."))
	update_icon()
/obj/structure/fireaxecabinet/proc/attackby_tool_done2(mob/user)
	locked = 1
	to_chat(user, span_warning("You re-enable the locking modules."))

/// Old attack_hand: take the axe if open, or toggle the case.
/datum/interaction/entry_hand/fireaxecabinet_hand
	id = "fireaxecabinet_hand"
	name = "Use"
	effect = /obj/structure/fireaxecabinet/proc/interaction_hand

/obj/structure/fireaxecabinet/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)

	if(locked)
		to_chat(user, span_warning("The cabinet won't budge!"))
		return TRUE

	if(open)
		if(fireaxe)
			user.put_in_hands(fireaxe)
			fireaxe = null
			to_chat (user, span_notice("You take the fire axe from the [name]."))
			add_fingerprint(user)
			update_icon()
		else
			if(smashed)
				return TRUE
			else
				toggle_close_open()

	else
		toggle_close_open()
	return TRUE

/// Old attack_tk: pull the axe out of an open case at range; otherwise act as a hand would.
/obj/structure/fireaxecabinet/proc/interaction_tk(mob/user, obj/item/held, datum/interaction/interaction)
	if(open && fireaxe)
		fireaxe.forceMove(loc)
		to_chat(user, span_notice("You telekinetically remove the fire axe."))
		fireaxe = null
		update_icon()
		return TRUE
	attack_hand(user)
	return TRUE

/obj/structure/fireaxecabinet/proc/toggle_close_open()
	open = !open
	if(open)
		update_icon()
		flick("[icon_state]opening", src)
	else
		update_icon()
		flick("[icon_state]closing", src)

/obj/structure/fireaxecabinet/proc/toggle_openness_effect(mob/user, obj/item/held, datum/interaction/interaction) //nice name, huh? HUH?! -Erro //YEAH -Agouri

	if (isrobot(user) || locked || smashed)
		if(locked)
			to_chat(user, span_warning("The cabinet won't budge!"))
		else if(smashed)
			to_chat(user, span_notice("The protective glass is broken!"))
		return

	toggle_close_open()
	update_icon()

/obj/structure/fireaxecabinet/proc/remove_fire_axe_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if (isrobot(user))
		return

	if (open)
		if(fireaxe)
			user.put_in_hands(fireaxe)
			fireaxe = null
			to_chat(user, span_notice("You take the Fire axe from the [name]."))
		else
			to_chat(user, span_notice("The [name] is empty."))
	else
		to_chat(user, span_notice("The [name] is closed."))
	update_icon()

/// Old attack_ai: lock or unlock it remotely.
/obj/structure/fireaxecabinet/proc/fireaxecabinet_silicon_lock(mob/user, obj/item/held, datum/interaction/interaction)
	if(smashed)
		to_chat(user, span_warning("The security of the cabinet is compromised."))
		return TRUE
	locked = !locked
	if(locked)
		to_chat(user, span_warning("Cabinet locked."))
	else
		to_chat(user, span_notice("Cabinet unlocked."))
	return TRUE

/obj/structure/fireaxecabinet/update_icon() //Template: fireaxe[has fireaxe][is opened][hits taken][is smashed]. If you want the opening or closing animations, add "opening" or "closing" right after the numbers
	var/hasaxe = 0
	if(fireaxe)
		hasaxe = 1
	icon_state = text("fireaxe[][][][]",hasaxe,open,hitstaken,smashed)

/obj/structure/fireaxecabinet/empty
	starts_with_axe = FALSE

DECLARE_REF(/obj/structure/fireaxecabinet, "fireaxe", HELD, null)
