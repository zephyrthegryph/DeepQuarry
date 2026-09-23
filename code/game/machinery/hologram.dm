/* Holograms!
 * Contains:
 *		Holopad
 *		Hologram
 *		Other stuff
 */

/*
Revised. Original based on space ninja hologram code. Which is also mine. /N
How it works:
AI clicks on holopad in camera view. View centers on holopad.
AI clicks again on the holopad to display a hologram. Hologram stays as long as AI is looking at the pad and it (the hologram) is in range of the pad.
AI can use the directional keys to move the hologram around, provided the above conditions are met and the AI in question is the holopad's master.
Only one AI may project from a holopad at any given time.
AI may cancel the hologram at any time by clicking on the holopad once more.

Possible to do for anyone motivated enough:
	Give an AI variable for different hologram icons.
	Itegrate EMP effect to disable the unit.
*/

/*
 * Holopad
 */
#define HOLOPAD_PASSIVE_POWER_USAGE 1
#define HOLOGRAM_POWER_USAGE 2
#define RANGE_BASED 4
#define AREA_BASED 6

#define IS_RANGE_BASED

/obj/machinery/hologram/holopad
	name = "\improper AI holopad"
	desc = "It's a floor-mounted device for projecting holographic images. It is activated remotely."
	icon_state = "holopad0"
	show_messages = 1
	circuit = /obj/item/circuitboard/holopad
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER
	var/power_per_hologram = 500 //per usage per hologram
	idle_power_usage = 5
	use_power = USE_POWER_IDLE
	var/list/mob/living/silicon/ai/masters //Lazy list of AIs that use the holopad
	var/last_request = 0 //to prevent request spam. ~Carn
	var/holo_range = 5 // Change to change how far the AI can move away from the holopad before deactivating.

/obj/machinery/hologram/holopad/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/holopad_request,
		/datum/interaction/machine_hand/ungated/holopad_request,
	)
	..()

/datum/interaction/machine_item/holopad_request
	id = "holopad_request_item"
	name = "Request AI presence"
	held_type = /obj/item
	effect = /obj/machinery/hologram/holopad/proc/interaction_request

/datum/interaction/machine_hand/ungated/holopad_request
	id = "holopad_request_hand"
	name = "Request AI presence"
	effect = /obj/machinery/hologram/holopad/proc/interaction_request

/obj/machinery/hologram/holopad/screwdriver_act(mob/user, obj/item/tool)
	return deconstruct_display(user, tool)

/obj/machinery/hologram/holopad/proc/interaction_request(mob/living/carbon/human/user, obj/item/held, datum/interaction/interaction) //Carn: Hologram requests.
	if(!istype(user))
		return TRUE
	if(tgui_alert(user,"Would you like to request an AI's presence?","Request AI",list("Yes","No")) == "Yes")
		if(last_request + 200 < world.time) //don't spam the AI with requests you jerk!
			last_request = world.time
			to_chat(user, span_notice("You request an AI's presence."))
			var/area/area = get_area(src)
			for(var/mob/living/silicon/ai/AI in GLOB.living_mob_list)
				if(!AI.client)	continue
				to_chat(AI, span_info("Your presence is requested at <a href='byond://?src=\ref[AI];jumptoholopad=\ref[src]'>\the [area]</a>."))
		else
			to_chat(user, span_notice("A request for AI presence was already sent recently."))
	return TRUE

/obj/machinery/hologram/holopad/attack_ai(mob/living/silicon/ai/user)
	if(!istype(user))
		return
	/*There are pretty much only three ways to interact here.
	I don't need to check for client since they're clicking on an object.
	This may change in the future but for now will suffice.*/
	if(user.eyeobj.loc != src.loc)//Set client eye on the object if it's not already.
		user.eyeobj.setLoc(get_turf(src))
	else if(!LAZYACCESS(masters, user))//If there is no hologram, possibly make one.
		activate_holo(user)
	else//If there is a hologram, remove it.
		clear_holo(user)
	return

/obj/machinery/hologram/holopad/proc/activate_holo(mob/living/silicon/ai/user)
	if(!(stat & NOPOWER) && user.eyeobj.loc == src.loc)//If the projector has power and client eye is on it
		if(user.holo)
			to_chat(user, span_danger("ERROR:") + " Image feed in progress.")
			return
		create_holo(user)//Create one.
		visible_message("A holographic image of [user] flicks to life right before your eyes!")
	else
		to_chat(user, span_danger("ERROR:") + " Unable to project hologram.")
	return

/*This is the proc for special two-way communication between AI and holopad/people talking near holopad.
For the other part of the code, check silicon say.dm. Particularly robot talk.*/
/obj/machinery/hologram/holopad/hear_talk(mob/M, list/message_pieces, verb)
	if(M && LAZYLEN(masters))
		for(var/mob/living/silicon/ai/master in masters)
			if(LAZYACCESS(masters, master) && M != master)
				master.relay_speech(M, message_pieces, verb)

/obj/machinery/hologram/holopad/see_emote(mob/living/M, text)
	if(M)
		for(var/mob/living/silicon/ai/master in masters)
			//var/name_used = M.GetVoice()
			var/rendered = span_game(span_say(span_italics("Holopad received, " + span_message("[text]"))))
			//The lack of name_used is needed, because message already contains a name.  This is needed for simple mobs to emote properly.
			master.show_message(rendered, 2)
	return

/obj/machinery/hologram/holopad/show_message(msg, type, alt, alt_type)
	for(var/mob/living/silicon/ai/master in masters)
		var/rendered = span_game(span_say(span_italics("Holopad received, " + span_message("[msg]"))))
		master.show_message(rendered, type)
	return

/obj/machinery/hologram/holopad/proc/create_holo(mob/living/silicon/ai/A, turf/T = loc)
	var/obj/effect/overlay/aiholo/hologram = new(T) // Spawn a blank effect at the location. // to specific type for adding vars
	hologram.master = A // So you can reference the master AI from in the hologram procs
	hologram.icon = A.holo_icon
	hologram.pixel_x = 16 - round(A.holo_icon.Width() / 2) // centers the hologram on the tile
	// hologram.mouse_opacity = 0//So you can't click on it. // Removal
	hologram.layer = FLY_LAYER//Above all the other objects/mobs. Or the vast majority of them.
	hologram.anchored = TRUE//So space wind cannot drag it.
	hologram.name = "[A.name] (Hologram)"//If someone decides to right click.

	if(!isnull(color))
		hologram.color = color
	else
		hologram.color = A.holo_color

	if(hologram.color)	//hologram lighting
		hologram.set_light(2,1,hologram.color)
	else
		hologram.set_light(2)

	for(var/obj/belly/B as anything in A.vore_organs)
		B.forceMove(hologram)

	LAZYSET(masters, A, hologram)
	set_light(2)			//pad lighting
	icon_state = "holopad1"
	flick("holopadload", src)
	A.holo = src
	if(LAZYLEN(masters))
		START_MACHINE_PROCESSING(src)

	// Let the AI experience area ambiences too
	var/area/ar = get_area(hologram.loc)
	ar?.play_ambience(A, initial = TRUE)
	return 1

/obj/machinery/hologram/holopad/proc/clear_holo(mob/living/silicon/ai/user)
	if(user.holo == src)
		user.holo = null
	qdel(LAZYACCESS(masters, user))//Get rid of user's hologram
	LAZYREMOVE(masters, user) //Discard AI from the list of those who use holopad
	if(!LAZYLEN(masters))//If no users left
		set_light(0)			//pad lighting (hologram lighting will be handled automatically since its owner was deleted)
		icon_state = "holopad0"
	return 1

/obj/machinery/hologram/holopad/process()
	for (var/mob/living/silicon/ai/master in masters)
		var/active_ai = (master && !master.stat && master.client && master.eyeobj)//If there is an AI attached, it's not incapacitated, it has a client, and the client eye is centered on the projector.
		if((stat & NOPOWER) || !active_ai)
			clear_holo(master)
			continue

		use_power(power_per_hologram)
	if(..() == PROCESS_KILL && !LAZYLEN(masters))
		return PROCESS_KILL

/obj/machinery/hologram/holopad/proc/move_hologram(mob/living/silicon/ai/user)
	if(LAZYACCESS(masters, user))
		var/obj/effect/overlay/aiholo/H = LAZYACCESS(masters, user)
		walk_towards(H, user.eyeobj)
		//Hologram left the screen (got stuck on a wall or something)
		if(get_dist(H, user.eyeobj) > world.view)
			clear_holo(user)
		#ifdef IS_RANGE_BASED
		if((get_dist(H, src) > holo_range))
			clear_holo(user)
		#else
		var/area/holopad_area = get_area(src)
		var/area/hologram_area = get_area(H)

		if(!(hologram_area in holopad_area))
			clear_holo(user)
		#endif

	return 1

/*
 * Hologram
 */

/obj/machinery/hologram
	icon = 'icons/obj/stationobjs.dmi'
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 5
	active_power_usage = 100

//Destruction procs.
/obj/machinery/hologram/holopad/Destroy()
	for (var/mob/living/silicon/ai/master in masters)
		clear_holo(master)
	return ..()

/*
 * Other Stuff: Is this even used?
 */
/obj/machinery/hologram/projector
	name = "hologram projector"
	desc = "It makes a hologram appear...with magnets or something..."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "hologram0"

#undef RANGE_BASED
#undef AREA_BASED
#undef HOLOPAD_PASSIVE_POWER_USAGE
#undef HOLOGRAM_POWER_USAGE
#undef IS_RANGE_BASED
