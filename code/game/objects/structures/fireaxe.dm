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
	/// The axe it starts with (a declared default child), or null for an empty cabinet.
	var/fireaxe_type = /obj/item/material/twohanded/fireaxe

TRACKED(/obj/structure/fireaxecabinet, open)
TRACKED(/obj/structure/fireaxecabinet, hitstaken)
TRACKED(/obj/structure/fireaxecabinet, smashed)

MSG_DEF_SELF(fireaxecabinet/locked, "The cabinet won't budge.")

CAPABILITIES(/obj/structure/fireaxecabinet)
	op("item", item(/obj/item), label("Use"), when(req_actor_kind(/mob/living/silicon/robot, not = TRUE)), then(PROC_REF(interaction_item)))
	// a cyborg's module only ever strikes the glass or resets the lock, as if the cabinet were locked
	op("robot_item", item(/obj/item), label("Use"), when(req_actor_kind(/mob/living/silicon/robot)), then(PROC_REF(struck_shut)))
	op("hand", hand(), label("Use"), needs(req_is(nameof(locked), FALSE, because = MSG(fireaxecabinet/locked))), then(PROC_REF(interaction_hand)))
	op("fireaxecabinet_silicon_lock", remote(), label("Toggle lock"), then(PROC_REF(fireaxecabinet_silicon_lock)))
	op("tk", tk(), label("Interaction tk"), then(PROC_REF(interaction_tk)))
	op("toggle_openness_effect", menu(), label("Open/Close"), when(req_actor_kind(/mob/living/silicon/robot, not = TRUE)), needs(req_adjacent(), req_capable()), then(PROC_REF(toggle_openness_effect)))
	op("remove_fire_axe_effect", menu(), label("Remove Fire Axe"), when(req_actor_kind(/mob/living/silicon/robot, not = TRUE)), needs(req_adjacent(), req_capable()), then(PROC_REF(remove_fire_axe_effect)))

/obj/structure/fireaxecabinet/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	//..() //That's very useful, Erro

	// This could stand to be put further in, made better, etc. but fuck you. Fuck whoever
	// wrote this code. Fuck everything about this object. I hope you step on a Lego.
	user.setClickCooldown(10)
	// Seriously why the fuck is this even a closet aghasjdhasd I hate you

	if(locked)
		return struck_shut(A)
	if (istype(O, /obj/item/material/twohanded/fireaxe) && open)
		if(!fireaxe)
			if(!move_into(src, nameof(src.fireaxe), O, user))
				return OP_OK
			O.update_held_icon() // it is in the cabinet now, not in a hand: the axe unwields itself
			to_chat(user, span_notice("You place the fire axe back in the [name]."))
		else
			if(smashed)
				return OP_OK
			else
				toggle_close_open()
	else
		if(smashed)
			return OP_OK
		if(O.has_tool_quality(TOOL_MULTITOOL))
			if(open)
				set_open(0)
				flick("[cabinet_state()]closing", src)
				return OP_OK
			else
				to_chat(user, span_warning("Resetting circuitry..."))
				play_sfx(src, SFX_MACHINES_LOCKENABLE)
				use_tool(user, O, src, delay = 2 SECONDS, quality = TOOL_MULTITOOL, volume = 0, receiver = src, on_done = PROC_REF(attackby_tool_done2), done_args = list(user))
				return OP_OK
		else
			toggle_close_open()
	return OP_OK

/// A locked cabinet (or any cyborg module) only strikes the glass, or a multitool resets the lock.
/obj/structure/fireaxecabinet/proc/struck_shut(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	user.setClickCooldown(10)
	if(O.has_tool_quality(TOOL_MULTITOOL))
		to_chat(user, span_warning("Resetting circuitry..."))
		play_sfx(src, SFX_MACHINES_LOCKRESET)
		use_tool(user, O, src, delay = 2 SECONDS, quality = TOOL_MULTITOOL, volume = 0, receiver = src, on_done = PROC_REF(attackby_tool_done), done_args = list(user))
		return OP_OK
	else if(istype(O, /obj/item))
		var/obj/item/W = O
		if(smashed || open)
			if(open)
				toggle_close_open()
			return OP_OK
		else
			play_sfx(src, SFX_EFFECTS_GLASSHIT, volume = 100) //We don't want this playing every time
		if(W.force < 15)
			to_chat(user, span_notice("The cabinet's protective glass glances off the hit."))
		else
			set_hitstaken(hitstaken + 1)
			if(hitstaken == 4)
				play_sfx(src, SFX_EFFECTS_GLASSBR3) //Break cabinet, receive goodies. Cabinet's fucked for life after that.
				set_smashed(1)
				locked = 0
				set_open(1)

	return OP_OK

/obj/structure/fireaxecabinet/proc/attackby_tool_done(mob/user)
	locked = 0
	to_chat(user, span_warning("You disable the locking modules."))
/obj/structure/fireaxecabinet/proc/attackby_tool_done2(mob/user)
	locked = 1
	to_chat(user, span_warning("You re-enable the locking modules."))

/obj/structure/fireaxecabinet/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor

	if(open)
		if(fireaxe)
			user.put_in_hands(fireaxe)
			rel_take(src, nameof(fireaxe))
			to_chat (user, span_notice("You take the fire axe from the [name]."))
			add_fingerprint(user)
		else
			if(smashed)
				return OP_OK
			else
				toggle_close_open()

	else
		toggle_close_open()
	return OP_OK

/// Old attack_tk: pull the axe out of an open case at range; otherwise act as a hand would.
/obj/structure/fireaxecabinet/proc/interaction_tk(datum/act/op/A)
	var/mob/user = A.actor
	if(open && fireaxe)
		fireaxe.forceMove(loc)
		to_chat(user, span_notice("You telekinetically remove the fire axe."))
		rel_take(src, nameof(fireaxe))
		return OP_OK
	attack_hand(user)
	return OP_OK

/obj/structure/fireaxecabinet/proc/toggle_close_open()
	set_open(!open)
	if(open)
		flick("[cabinet_state()]opening", src)
	else
		flick("[cabinet_state()]closing", src)

/obj/structure/fireaxecabinet/proc/toggle_openness_effect(datum/act/op/A)
	var/mob/user = A.actor

	if (locked || smashed)
		if(locked)
			to_chat(user, span_warning("The cabinet won't budge!"))
		else if(smashed)
			to_chat(user, span_notice("The protective glass is broken!"))
		return

	toggle_close_open()

/obj/structure/fireaxecabinet/proc/remove_fire_axe_effect(datum/act/op/A)
	var/mob/user = A.actor

	if (open)
		if(fireaxe)
			user.put_in_hands(fireaxe)
			rel_take(src, nameof(fireaxe))
			to_chat(user, span_notice("You take the Fire axe from the [name]."))
		else
			to_chat(user, span_notice("The [name] is empty."))
	else
		to_chat(user, span_notice("The [name] is closed."))

/// Old attack_ai: lock or unlock it remotely.
/obj/structure/fireaxecabinet/proc/fireaxecabinet_silicon_lock(datum/act/op/A)
	var/mob/user = A.actor
	if(smashed)
		to_chat(user, span_warning("The security of the cabinet is compromised."))
		return OP_OK
	locked = !locked
	if(locked)
		to_chat(user, span_warning("Cabinet locked."))
	else
		to_chat(user, span_notice("Cabinet unlocked."))
	return OP_OK

//Template: fireaxe[has fireaxe][is opened][hits taken][is smashed]. If you want the opening or closing animations, add "opening" or "closing" right after the numbers
/obj/structure/fireaxecabinet/proc/appearance_hasaxe()
	return fireaxe ? 1 : 0

/// The look (the draw sweep: from its template).
/obj/structure/fireaxecabinet/draw(datum/look/look)
	..()
	look.state(cabinet_state())

/// The cabinet's sprite for its state: the draw shows it, and the door animations are named after it ("<state>opening").
/obj/structure/fireaxecabinet/proc/cabinet_state()
	return "fireaxe[appearance_hasaxe()][open][hitstaken][smashed]"

/obj/structure/fireaxecabinet/empty
	fireaxe_type = null

/obj/structure/fireaxecabinet/ownership()
	. = ..()
	. += owns(nameof(fireaxe), policy = OWN_CONTAINED, starts = nameof(fireaxe_type))
