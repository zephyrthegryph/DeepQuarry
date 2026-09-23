/obj/machinery/door/window
	name = "interior door"
	desc = "A strong door."
	icon = 'icons/obj/doors/windoor.dmi'
	icon_state = "left"
	var/base_state = "left"
	min_force = 4
	hitsound = 'sound/effects/Glasshit.ogg'
	max_integrity = 150 //If you change this, consiter changing ../door/window/brigdoor/ max_integrity at the bottom of this .dm file
	visible = 0.0
	use_power = USE_POWER_OFF
	flags = ON_BORDER
	opacity = 0
	var/obj/item/airlock_electronics/electronics = null
	explosion_resistance = 5
	can_atmos_pass = ATMOS_PASS_PROC
	air_properties_vary_with_direction = 1

/obj/machinery/door/window/Initialize(mapload)
	. = ..()
	update_nearby_tiles()
	if(LAZYLEN(req_access))
		icon_state = "[icon_state]"
		base_state = icon_state

/obj/machinery/door/window/update_icon()
	if(density)
		icon_state = base_state
	else
		icon_state = "[base_state]open"

/obj/machinery/door/window/proc/shatter(display_message = 1)
	new /obj/item/material/shard(src.loc)
	new /obj/item/material/shard(src.loc)
	new /obj/item/stack/cable_coil(src.loc, 1)
	var/obj/item/airlock_electronics/ae
	if(!electronics)
		ae = new/obj/item/airlock_electronics( src.loc )
		if(LAZYLEN(req_access))
			ae.conf_access = req_access
		else if (LAZYLEN(req_one_access))
			ae.conf_access = req_one_access
			ae.one_access = 1
	else
		ae = electronics
		electronics = null
		ae.loc = src.loc
	if(operating == -1)
		ae.icon_state = "door_electronics_smoked"
		operating = 0
	src.density = FALSE
	playsound(src, "shatter", 70, 1)
	if(display_message)
		visible_message("[src] shatters!")
	qdel(src)

/obj/machinery/door/window/Destroy()
	density = FALSE
	update_nearby_tiles()
	return ..()

/obj/machinery/door/window/Bumped(atom/movable/AM as mob|obj)
	if (!( ismob(AM) ))
		var/mob/living/bot/bot = AM
		if(istype(bot))
			if(density && src.check_access(bot.botcard))
				open()
				addtimer(CALLBACK(src, PROC_REF(close)), 50)
		else if(istype(AM, /obj/mecha))
			var/obj/mecha/mecha = AM
			if(density)
				if(mecha.occupant && src.allowed(mecha.occupant))
					open()
					addtimer(CALLBACK(src, PROC_REF(close)), 50)
		return
	if (!( SSticker ))
		return
	if (src.operating)
		return
	if (density && allowed(AM))
		open()
		addtimer(CALLBACK(src, PROC_REF(close)), check_access(null)? 50 : 20)

/obj/machinery/door/window/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSGLASS))
		return TRUE
	if(get_dir(mover, target) == GLOB.reverse_dir[dir]) // From elsewhere to here, can't move against our dir
		return !density
	return TRUE
/obj/machinery/door/window/can_pathfinding_enter(atom/movable/actor, dir, datum/pathfinding/search)
	return (src.dir != dir) || ..() || (has_access(req_access, req_one_access, search.ss13_with_access) && !inoperable())

/obj/machinery/door/window/can_pathfinding_exit(atom/movable/actor, dir, datum/pathfinding/search)
	return (src.dir != dir)  || ..() || (has_access(req_access, req_one_access, search.ss13_with_access) && !inoperable())
/obj/machinery/door/window/Uncross(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSGLASS))
		return TRUE
	if(get_dir(mover, target) == dir) // From here to elsewhere, can't move in our dir
		return !density
	return TRUE


/obj/machinery/door/window/CanZASPass(turf/T, is_zone)
	if(get_dir(T, loc) == turn(dir, 180))
		if(is_zone) // No merging allowed.
			return FALSE
		return !density  // Air can flow if open (density == FALSE).
	return TRUE // Windoors don't block if not facing the right way.

/obj/machinery/door/window/open()
	if (operating == 1 || !density) //doors can still open when emag-disabled
		return 0
	if (!SSticker)
		return 0
	if (!operating) //in case of emag
		operating = 1
	flick(text("[src.base_state]opening"), src)
	playsound(src, 'sound/machines/door/windowdoor.ogg', 100, 1)
	addtimer(CALLBACK(src, PROC_REF(finish_open)), 1 SECONDS, TIMER_DELETE_ME)

/obj/machinery/door/window/proc/finish_open()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	explosion_resistance = 0
	density = FALSE
	update_icon()
	update_nearby_tiles()

	if(operating == 1) //emag again
		operating = 0
	return 1

/obj/machinery/door/window/close()
	if(operating || density)
		return FALSE
	operating = TRUE
	flick(text("[]closing", src.base_state), src)
	playsound(src, 'sound/machines/door/windowdoor.ogg', 100, 1)

	density = TRUE
	update_icon()
	explosion_resistance = initial(explosion_resistance)
	update_nearby_tiles()
	addtimer(CALLBACK(src, PROC_REF(finish_close)), 1 SECONDS, TIMER_DELETE_ME)

/obj/machinery/door/window/proc/finish_close()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	operating = FALSE
	return TRUE

// Window doors shatter outright at zero integrity rather than persisting broken.
// Window doors shatter outright rather than persisting in the broken state the
// base door uses, so we deliberately do NOT chain to /obj/machinery/door's
// atom_destruction (which breaks it through atom_break()). Fire the destruction signal here.
/obj/machinery/door/window/atom_destruction(damage_flag)
	SHOULD_CALL_PARENT(FALSE)
	shatter()

/obj/machinery/door/window/attack_hand(mob/user as mob)
	src.add_fingerprint(user)

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.species.can_shred(H, FALSE, 15))
			playsound(src, 'sound/effects/Glasshit.ogg', 75, 1)
			visible_message(span_danger("[user] smashes against the [src.name]."), 1)
			user.do_attack_animation(src)
			user.setClickCooldown(user.get_attack_speed())
			take_damage(25, BRUTE, MELEE)
			return

	if (src.allowed(user))
		if (src.density)
			open()
		else
			close()

	else if (src.density)
		flick(text("[]deny", src.base_state), src)

	return

/obj/machinery/door/window/emag_act(remaining_charges, mob/user)
	if (density && operable())
		operating = -1
		flick("[src.base_state]spark", src)
		sleep(6)
		open()
		return 1

/obj/machinery/door/window/attackby(obj/item/I as obj, mob/user as mob)

	//If it's in the process of opening/closing, ignore the click
	if (src.operating == 1)
		return

	if(istype(I))
		//Emags and ninja swords? You may pass.
		if (istype(I, /obj/item/melee/energy/blade))
			if(emag_act(10, user))
				var/datum/effect/effect/system/spark_spread/spark_system = new /datum/effect/effect/system/spark_spread()
				spark_system.set_up(5, 0, src.loc)
				spark_system.start()
				playsound(src, "sparks", 50, 1)
				playsound(src, 'sound/weapons/blade1.ogg', 50, 1)
				visible_message(span_warning("The glass door was sliced open by [user]!"))
			return 1

		//If it's a weapon, smash windoor. Unless it's an id card, agent card, ect.. then ignore it (Cards really shouldnt damage a door anyway)
		if(src.density && istype(I, /obj/item) && !istype(I, /obj/item/card))
			user.setClickCooldown(user.get_attack_speed(I))
			var/aforce = I.force
			playsound(src, 'sound/effects/Glasshit.ogg', 75, 1)
			visible_message(span_danger("[src] was hit by [I]."))
			if(I.obj_damage_type())
				take_damage(aforce, I.obj_damage_type(), MELEE)
			return


	src.add_fingerprint(user)

	if (src.allowed(user))
		if (src.density)
			open()
		else
			close()

	else if (src.density)
		flick(text("[]deny", src.base_state), src)

	return

/obj/machinery/door/window/welder_act(mob/user, obj/item/tool)
	if(operating == 1 || user.a_intent != I_HELP)
		return FALSE
	if(get_integrity() >= max_integrity)
		to_chat(user, span_warning("[src] is already in good condition!"))
		return TRUE
	if(use_tool(user, tool, src, delay = 4 SECONDS, quality = TOOL_WELDER, volume = 50, amount = 1,
			message_self = "You begin repairing [src]..."))
		repair_damage(max_integrity)
		update_icon()
		to_chat(user, span_notice("You repair [src]."))
	return TRUE

/obj/machinery/door/window/crowbar_act(mob/user, obj/item/tool)
	if(operating == 1 || density)
		return FALSE
	if(!use_tool(user, tool, src, delay = 4 SECONDS, quality = TOOL_CROWBAR, volume = 50,
			message_self = "You start to pry the windoor out of the frame.",
			message_others = "[user] begins prying the windoor out of the frame."))
		return TRUE
	to_chat(user, span_notice("You pried the windoor out of the frame!"))
	var/obj/structure/windoor_assembly/assembly = new(loc)
	if(istype(src, /obj/machinery/door/window/brigdoor))
		assembly.secure = "secure_"
	if(base_state == "right" || base_state == "rightsecure")
		assembly.facing = "r"
	assembly.set_dir(dir)
	assembly.anchored = TRUE
	assembly.created_name = name
	assembly.state = "02"
	assembly.step = 2
	assembly.update_state()
	if(operating == -1)
		assembly.electronics = new /obj/item/circuitboard/broken()
	else if(!electronics)
		assembly.electronics = new /obj/item/airlock_electronics()
		if(LAZYLEN(req_access))
			assembly.electronics.conf_access = req_access
		else if(LAZYLEN(req_one_access))
			assembly.electronics.conf_access = req_one_access
			assembly.electronics.one_access = TRUE
	else
		assembly.electronics = electronics
		electronics = null
	operating = 0
	qdel(src)
	return TRUE

/obj/machinery/door/window/brigdoor
	name = "secure door"
	icon = 'icons/obj/doors/windoor.dmi'
	icon_state = "leftsecure"
	base_state = "leftsecure"
	req_access = list(ACCESS_SECURITY)
	var/id = null
	max_integrity = 300 //Stronger doors for prison (regular window door integrity is 150)

/obj/machinery/door/window/brigdoor/shatter()
	new /obj/item/stack/rods(src.loc, 2)
	..()

/obj/machinery/door/window/northleft
	dir = NORTH

/obj/machinery/door/window/eastleft
	dir = EAST

/obj/machinery/door/window/westleft
	dir = WEST

/obj/machinery/door/window/southleft
	dir = SOUTH

/obj/machinery/door/window/northright
	dir = NORTH
	icon_state = "right"
	base_state = "right"

/obj/machinery/door/window/eastright
	dir = EAST
	icon_state = "right"
	base_state = "right"

/obj/machinery/door/window/westright
	dir = WEST
	icon_state = "right"
	base_state = "right"

/obj/machinery/door/window/southright
	dir = SOUTH
	icon_state = "right"
	base_state = "right"

/obj/machinery/door/window/brigdoor/northleft
	dir = NORTH

/obj/machinery/door/window/brigdoor/eastleft
	dir = EAST

/obj/machinery/door/window/brigdoor/westleft
	dir = WEST

/obj/machinery/door/window/brigdoor/southleft
	dir = SOUTH

/obj/machinery/door/window/brigdoor/northright
	dir = NORTH
	icon_state = "rightsecure"
	base_state = "rightsecure"

/obj/machinery/door/window/brigdoor/eastright
	dir = EAST
	icon_state = "rightsecure"
	base_state = "rightsecure"

/obj/machinery/door/window/brigdoor/westright
	dir = WEST
	icon_state = "rightsecure"
	base_state = "rightsecure"

/obj/machinery/door/window/brigdoor/southright
	dir = SOUTH
	icon_state = "rightsecure"
	base_state = "rightsecure"
