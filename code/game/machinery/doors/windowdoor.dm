/// welder_act(): the windoor's stance-declared weld repair.
#define WINDOOR_ENTRY_WELD "windoor_weld"

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

APPEARANCE_TEMPLATE(/obj/machinery/door/window, "{base_state}{density?:open}")

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
		own_take(src, "electronics")
		ae.forceMove(src.loc)
	if(operating == -1)
		ae.icon_state = "door_electronics_smoked"
		operating = 0
	set_density(FALSE)
	play_sfx(src, SFX_SHATTER)
	if(display_message)
		visible_message("[src] shatters!")
	qdel(src)

/obj/machinery/door/window/Bumped(atom/movable/AM as mob|obj)
	if (!( ismob(AM) ))
		var/mob/living/bot/bot = AM
		if(istype(bot))
			if(density && src.check_access(bot.botcard))
				open()
				om_after(src, 50, PROC_REF(close))
		else if(istype(AM, /obj/mecha))
			var/obj/mecha/mecha = AM
			if(density)
				if(mecha?.slot_item(MECHA_SLOT_PILOT) && src.allowed(mecha?.slot_item(MECHA_SLOT_PILOT)))
					open()
					om_after(src, 50, PROC_REF(close))
		return
	if (!( SSticker ))
		return
	if (src.operating)
		return
	if (density && allowed(AM))
		open()
		om_after(src, check_access(null)? 50 : 20, PROC_REF(close))

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
		operating = 1
	flick(text("[src.base_state]opening"), src)
	play_sfx(src, SFX_MACHINES_DOOR_WINDOWDOOR)
	om_after(src, 1 SECONDS, PROC_REF(finish_open))

/obj/machinery/door/window/proc/finish_open()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	explosion_resistance = 0
	set_density(FALSE)
	update_nearby_tiles()

	if(operating == 1) //emag again
		operating = 0
	return 1

/obj/machinery/door/window/close()
	if(operating || density)
		return FALSE
	operating = TRUE
	flick(text("[]closing", src.base_state), src)
	play_sfx(src, SFX_MACHINES_DOOR_WINDOWDOOR)

	set_density(TRUE)
	explosion_resistance = initial(explosion_resistance)
	update_nearby_tiles()
	om_after(src, 1 SECONDS, PROC_REF(finish_close))

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

/obj/machinery/door/window/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/windowdoor_emag,
		/datum/interaction/machine_item/windowdoor_smash,
		/datum/interaction/machine_item/windowdoor_item_toggle,
		/datum/interaction/machine_hand/windowdoor_shred,
		/datum/interaction/machine_hand/windowdoor_toggle,
	)
	..()

/datum/interaction/machine_hand/windowdoor_shred
	id = "windowdoor_shred"
	name = "Smash"
	category = INTERACTION_CAT_ATTACK
	behind_gate = FALSE
	tags = list(INTERACTION_TAG_HOSTILE)
	offered_when = list(REQ_ON(PRED_ACTOR, /obj/machinery/door/window/proc/actor_can_shred, null))
	requires = list(REQ_INTERACTION_REACH)
	effect = /obj/machinery/door/window/proc/interaction_shred

/obj/machinery/door/window/proc/actor_can_shred(mob/actor, atom/target, obj/item/held)
	if(!ishuman(actor))
		return FALSE
	var/mob/living/carbon/human/H = actor
	return H.species.can_shred(H, FALSE, 15)

/obj/machinery/door/window/proc/interaction_shred(mob/user, obj/item/held, datum/interaction/interaction)
	play_sfx(src, SFX_EFFECTS_GLASSHIT)
	act_message(user, null, others = span_danger("%U% smashes against the [src.name]."))
	user.do_attack_animation(src)
	user.setClickCooldown(user.get_attack_speed())
	take_damage(25, BRUTE, MELEE)
	return TRUE

/datum/interaction/machine_hand/windowdoor_toggle
	id = "windowdoor_toggle"
	name = "Open/close"
	category = INTERACTION_CAT_TOGGLE
	behind_gate = FALSE
	requires = list(REQ_INTERACTION_REACH)
	effect = /obj/machinery/door/window/proc/interaction_toggle

/obj/machinery/door/window/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	src.add_fingerprint(user)

	if (src.allowed(user))
		if (src.density)
			open()
		else
			close()

	else if (src.density)
		flick(text("[]deny", src.base_state), src)

	return TRUE

/obj/machinery/door/window/emag_act(remaining_charges, mob/user)
	if (density && operable())
		operating = -1
		flick("[src.base_state]spark", src)
		om_after(src, 6, PROC_REF(open))
		return 1

/datum/interaction/machine_item/windowdoor_emag
	id = "windowdoor_emag"
	name = "Slice open"
	held_type = /obj/item/melee/energy/blade
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/door/window/proc/not_operating, null))
	effect = /obj/machinery/door/window/proc/interaction_emag_slice

/obj/machinery/door/window/proc/not_operating(mob/actor, atom/target, obj/item/held)
	return operating != 1

/obj/machinery/door/window/proc/interaction_emag_slice(mob/user, obj/item/I, datum/interaction/interaction)
	if(emag_act(10, user))
		fx_sparks(src.loc, 5, FALSE)
		play_sfx(src, SFX_SPARKS)
		play_sfx(src, SFX_WEAPONS_BLADE1)
		act_message(user, null, others = span_warning("The glass door was sliced open by %U%!"))
	return TRUE

/datum/interaction/machine_item/windowdoor_smash
	id = "windowdoor_smash"
	name = "Smash"
	category = INTERACTION_CAT_ATTACK
	held_type = /obj/item
	tags = list(INTERACTION_TAG_HOSTILE)
	offered_when = list(
		REQ_ON(PRED_TARGET, /obj/machinery/door/window/proc/not_operating, null),
		REQ_ON(PRED_TARGET, /obj/machinery/door/window/proc/is_open_or_closed_smashable, null),
	)
	effect = /obj/machinery/door/window/proc/interaction_smash

/// density && !istype(card): whether the held item can smash the windoor.
/obj/machinery/door/window/proc/is_open_or_closed_smashable(mob/actor, atom/target, obj/item/held)
	return density && istype(held, /obj/item) && !istype(held, /obj/item/card)

/obj/machinery/door/window/proc/interaction_smash(mob/user, obj/item/I, datum/interaction/interaction)
	user.setClickCooldown(user.get_attack_speed(I))
	var/aforce = I.force
	play_sfx(src, SFX_EFFECTS_GLASSHIT)
	visible_message(span_danger("[src] was hit by [I]."))
	if(I.obj_damage_type())
		take_damage(aforce, I.obj_damage_type(), MELEE)
	return TRUE

/datum/interaction/machine_item/windowdoor_item_toggle
	id = "windowdoor_item_toggle"
	name = "Open/close"
	held_type = /obj/item
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/door/window/proc/not_operating, null))
	effect = /obj/machinery/door/window/proc/interaction_item_toggle

/obj/machinery/door/window/proc/interaction_item_toggle(mob/user, obj/item/I, datum/interaction/interaction)
	src.add_fingerprint(user)

	if (src.allowed(user))
		if (src.density)
			open()
		else
			close()

	else if (src.density)
		flick(text("[]deny", src.base_state), src)

	return TRUE

/obj/machinery/door/window/welder_act(mob/user, obj/item/tool)
	if(operating == 1)
		return FALSE
	// Outside combat mode only (the stance-declared repair); otherwise the welder goes on to strike.
	if(run_interaction_entry(user, src, tool, WINDOOR_ENTRY_WELD))
		return TRUE
	return FALSE

/// Weld-repair the windoor, outside combat mode (run from welder_act()).
/datum/interaction/windowdoor_repair
	id = "windowdoor_repair"
	name = "Repair"
	entry = WINDOOR_ENTRY_WELD
	default_action = INPUT_ACTION_USE
	category = INTERACTION_CAT_REPAIR
	stance = I_HELP
	tool = TOOL_WELDER
	tool_volume = 0
	requires = list(REQ_REACH_ADJACENT, REQ_TARGET_STATE(/obj/machinery/door/window/proc/can_repair))
	effect = /obj/machinery/door/window/proc/interaction_repair

/obj/machinery/door/window/declare_interactions(list/into)
	into += list(
		/datum/interaction/windowdoor_repair,
	)
	..()

/// Requirement: only a damaged door needs repair.
/obj/machinery/door/window/proc/can_repair(mob/user, atom/target, obj/item/tool)
	if(get_integrity() >= max_integrity)
		return "it's already in good condition"
	return TRUE

/obj/machinery/door/window/proc/interaction_repair(mob/user, obj/item/tool, datum/interaction/interaction)
	use_tool(user, tool, src, delay = 4 SECONDS, quality = TOOL_WELDER, volume = 50, amount = 1, start_self = "You begin repairing [src]...", receiver = src, on_done = PROC_REF(welder_act_tool_done_windoor), done_args = list(user))
	return TRUE

/obj/machinery/door/window/proc/welder_act_tool_done_windoor(mob/user)
	repair_damage(max_integrity)
	update_icon()
	to_chat(user, span_notice("You repair [src]."))

/obj/machinery/door/window/crowbar_act(mob/user, obj/item/tool)
	if(operating == 1 || density)
		return FALSE
	use_tool(user, tool, src, delay = 4 SECONDS, quality = TOOL_CROWBAR, volume = 50, start_self = "You start to pry the windoor out of the frame.", start_others = "[user] begins prying the windoor out of the frame.", receiver = src, on_done = PROC_REF(crowbar_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/door/window/proc/crowbar_act_tool_done(mob/user)
	to_chat(user, span_notice("You pried the windoor out of the frame!"))
	var/obj/structure/windoor_assembly/assembly = new(loc)
	if(istype(src, /obj/machinery/door/window/brigdoor))
		assembly.secure = "secure_"
	if(base_state == "right" || base_state == "rightsecure")
		assembly.facing = "r"
	assembly.set_dir(dir)
	assembly.set_anchored(TRUE)
	assembly.created_name = name
	assembly.state = "02"
	assembly.step = 2
	assembly.update_state()
	if(operating == -1)
		own_set(assembly, "electronics", new /obj/item/circuitboard/broken(assembly))
	else if(!electronics)
		own_set(assembly, "electronics", new /obj/item/airlock_electronics(assembly))
		if(LAZYLEN(req_access))
			assembly.electronics.conf_access = req_access
		else if(LAZYLEN(req_one_access))
			assembly.electronics.conf_access = req_one_access
			assembly.electronics.one_access = TRUE
	else
		var/obj/item/airlock_electronics/door_electronics = electronics
		door_electronics.forceMove(assembly)
		own_move(door_electronics, assembly, "electronics") // from the door to the assembly
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

OWN(/obj/machinery/door/window, electronics, OWN_CONTAINED)

// Brig timers find their doors by id (REL_KEYED sources).
KEYED_TARGET(/obj/machinery/door/window/brigdoor, id)
