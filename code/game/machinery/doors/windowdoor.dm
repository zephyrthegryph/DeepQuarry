/obj/machinery/door/window
	name = "interior door"
	desc = "A strong door."
	icon = 'icons/obj/doors/windoor.dmi'
	icon_state = "left"
	var/base_state = "left"
	min_force = 4
	hitsound = SFX_EFFECTS_GLASSHIT
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

/// The look: its base state ("left", "right", ...), with "open" after it while it stands open.
/obj/machinery/door/window/draw(datum/look/look)
	..()
	look.state("[base_state][density ? "" : "open"]")

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
			ae.set_one_access(1)
	else
		ae = electronics
		rel_take(src, nameof(electronics))
		ae.forceMove(src.loc)
	if(operating == -1)
		ae.icon_state = "door_electronics_smoked"
		set_operating(0)
	set_density(FALSE)
	play_sfx(src, SFX_SHATTER)
	if(display_message)
		visible_message("[src] shatters!")
	destroyed(src, null, BRUTE)

/// Something walked into the windoor: a bot with its card or a mech with its pilot's access opens it for five seconds, a mob with access for two
/// (five for a public one). Replaces the door's answer.
/obj/machinery/door/window/door_bumped(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/movable/AM = N.bumper
	if(!AM)
		return
	if (!( ismob(AM) ))
		var/mob/living/bot/bot = AM
		if(istype(bot))
			if(density && src.check_access(bot.botcard))
				open()
				after(src, 5 SECONDS, PROC_REF(close), key = "autoclose", clock = CLOCK_WORLD)
		else if(istype(AM, /obj/mecha))
			var/obj/mecha/mecha = AM
			if(density)
				if(mecha?.slot_item(MECHA_SLOT_PILOT) && src.allowed(mecha?.slot_item(MECHA_SLOT_PILOT)))
					open()
					after(src, 5 SECONDS, PROC_REF(close), key = "autoclose", clock = CLOCK_WORLD)
		return
	if (!( SSticker ))
		return
	if (src.operating)
		return
	if (density && allowed(AM))
		open()
		after(src, check_access(null) ? 5 SECONDS : 2 SECONDS, PROC_REF(close), key = "autoclose", clock = CLOCK_WORLD)

/obj/machinery/door/window/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSGLASS))
		return TRUE
	if(get_dir(mover, target) == GLOB.reverse_dir[dir]) // From elsewhere to here, can't move against our dir
		return !density
	return TRUE
/obj/machinery/door/window/can_pathfinding_enter(atom/movable/actor, dir, datum/pathfinding/search)
	return (src.dir != dir) || ..() || (has_access(req_access, req_one_access, search.ss13_with_access) && operable())

/obj/machinery/door/window/can_pathfinding_exit(atom/movable/actor, dir, datum/pathfinding/search)
	return (src.dir != dir)  || ..() || (has_access(req_access, req_one_access, search.ss13_with_access) && operable())
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
		set_operating(1)
	flick(text("[src.base_state]opening"), src)
	play_sfx(src, SFX_MACHINES_DOOR_WINDOWDOOR)
	after(src, 1 SECONDS, PROC_REF(finish_open), key = "swing", clock = CLOCK_WORLD)

/obj/machinery/door/window/proc/finish_open()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	explosion_resistance = 0
	set_density(FALSE)
	update_nearby_tiles()

	if(operating == 1) //emag again
		set_operating(0)
	return 1

/obj/machinery/door/window/close()
	if(operating || density)
		return FALSE
	set_operating(TRUE)
	flick(text("[]closing", src.base_state), src)
	play_sfx(src, SFX_MACHINES_DOOR_WINDOWDOOR)

	set_density(TRUE)
	explosion_resistance = initial(explosion_resistance)
	update_nearby_tiles()
	after(src, 1 SECONDS, PROC_REF(finish_close), key = "swing", clock = CLOCK_WORLD)

/obj/machinery/door/window/proc/finish_close()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	set_operating(FALSE)
	return TRUE

// Window doors shatter outright at zero integrity rather than persisting broken.
// Window doors shatter outright rather than persisting in the broken state the
// base door uses, so we deliberately do NOT chain to /obj/machinery/door's
// atom_destruction (which breaks it through atom_break()). Fire the destruction signal here.
/obj/machinery/door/window/atom_destruction(damage_flag)
	SHOULD_CALL_PARENT(FALSE)
	shatter()

// ---- what a windoor is, declared ----
//
// A door of reinforced glass: the base door's touch (a hand or any held thing works it by the door's access, a refused one flashes its denial) and
// its emag, with a few ops of its own: a hostile claw that smashes it, an energy blade that slices it open, a welder's repair (a slow one, outside
// combat), and a crowbar that pries an open one out of its frame into an assembly. A weapon's blow dents it by the force of the weapon (no minimum). The
// plasteel fitting and the base door's repair are not offered; a windoor does not take them.

MSG_DEF_SELF(windoor/good_condition, "It's already in good condition.")
MSG_DEF(windoor/repaired, "You repair %T%.", "%U% repairs %T%.")

CAPABILITIES(/obj/machinery/door/window)
	without("reinforce")
	without("weld_plasteel")
	without("unreinforce")
	without("repair")
	owns_one(nameof(electronics), /obj/item/airlock_electronics)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(door_emp)))
	op("slice", item(/obj/item/melee/energy/blade), label("Slice open"), when(PROC_REF(not_swinging)), priority(OP_PRIORITY_TAKE_OUT), wait(0), then(PROC_REF(sliced_open)))
	op("shred", hand(), hostile(), label("Smash"), when(req_can_shred(15)), wait(0), then(PROC_REF(shredded)))
	op("weld_repair", tool(TOOL_WELDER), stance(I_HELP), label("Repair"), when(PROC_REF(not_swinging)), priority(OP_PRIORITY_PART), wait(4 SECONDS), costs(RES_FUEL, 1),
		needs(req(PROC_REF(damaged_now), because = MSG(windoor/good_condition))), then(PROC_REF(repaired)), says(MSG(windoor/repaired)))
	op("crowbar_shut", tool(TOOL_CROWBAR), when(nameof(density)), priority(OP_PRIORITY_PART), wait(0), then(PROC_REF(nothing_done)))
	op("pry_out", tool(TOOL_CROWBAR), label("Pry out of the frame"), when(cond_not(nameof(density))), when(PROC_REF(not_swinging)), priority(OP_PRIORITY_PART), wait(4 SECONDS),
		then(PROC_REF(pried_out)))

/// A crowbar does nothing to a shut windoor (it neither opens it as a touch nor pries it out).
/obj/machinery/door/window/proc/nothing_done(datum/act/op/A)
	return OP_OK

/// It is not mid-swing (a windoor that an emag keeps open for good still answers).
/obj/machinery/door/window/proc/not_swinging(datum/act/A)
	return operating != 1

/// It has taken damage a welder can mend.
/obj/machinery/door/window/proc/damaged_now(datum/act/A)
	return get_integrity() < max_integrity // ALLOW(reads): a door's max_integrity is its type's constant

/// An energy blade slices through the glass: the door gives way as to an emag (it stays open for good).
/obj/machinery/door/window/proc/sliced_open(datum/act/op/A)
	if(emag_target(src, 10, A.actor))
		fx_sparks(src.loc, 5, FALSE)
		play_sfx(src, SFX_SPARKS)
		play_sfx(src, SFX_WEAPONS_BLADE1)
		act_message(A.actor, null, others = span_warning("The glass door was sliced open by %U%!"))
	return OP_OK

/// A hostile body with claws (a species that can shred) smashes at the glass.
/obj/machinery/door/window/proc/shredded(datum/act/op/A)
	var/mob/user = A.actor
	play_sfx(src, SFX_EFFECTS_GLASSHIT)
	act_message(user, null, others = span_danger("%U% smashes against the [src.name]."))
	user.do_attack_animation(src)
	user.setClickCooldown(user.get_attack_speed())
	take_damage(25, BRUTE, MELEE)
	return OP_OK

/// A weapon's blow on the glass dents it by the weapon's force, whatever it is (there is no minimum force).
/obj/machinery/door/window/strike_with(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	user.setClickCooldown(user.get_attack_speed(I))
	var/aforce = I.force
	play_sfx(src, SFX_EFFECTS_GLASSHIT)
	visible_message(span_danger("[src] was hit by [I]."))
	if(I.obj_damage_type())
		take_damage(aforce, I.obj_damage_type(), MELEE)
	return OP_OK

/// A welder has mended it in full.
/obj/machinery/door/window/proc/repaired(datum/act/op/A)
	repair_damage(max_integrity)
	return OP_OK

/// What it flashes: its own sprites for the spark and the denial.
/obj/machinery/door/window/do_animate(animation)
	switch(animation)
		if("spark")
			if(density)
				flick("[base_state]spark", src)
		if("deny")
			if(density)
				flick("[base_state]deny", src)
	return

/// A crowbar pries the open door out of its frame: an assembly stands there, with the door's electronics in it.
/obj/machinery/door/window/proc/pried_out(datum/act/op/A)
	to_chat(A.actor, span_notice("You pried the windoor out of the frame!"))
	var/obj/structure/windoor_assembly/assembly = new(loc)
	if(istype(src, /obj/machinery/door/window/brigdoor))
		assembly.set_secure("secure_")
	if(base_state == "right" || base_state == "rightsecure")
		assembly.set_facing("r")
	assembly.set_dir(dir)
	assembly.set_anchored(TRUE)
	assembly.created_name = name
	graph_place(assembly, STAGE_WINDOOR_ASSEMBLY_BOARDED)
	if(operating == -1)
		rel_set(assembly, nameof(assembly.electronics), new /obj/item/circuitboard/broken(assembly))
	else if(!electronics)
		rel_set(assembly, nameof(assembly.electronics), new /obj/item/airlock_electronics(assembly))
		if(LAZYLEN(req_access))
			assembly.electronics.conf_access = req_access
		else if(LAZYLEN(req_one_access))
			assembly.electronics.conf_access = req_one_access
			assembly.electronics.one_access = TRUE
	else
		var/obj/item/airlock_electronics/door_electronics = electronics
		door_electronics.forceMove(assembly)
		own_move(door_electronics, assembly, nameof(assembly.electronics)) // from the door to the assembly
	assembly.update_state()
	set_operating(0)
	replace_with(src, assembly)
	return OP_OK

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
