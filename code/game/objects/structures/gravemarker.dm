/obj/structure/gravemarker
	name = "grave marker"
	desc = "An object used in marking graves."
	icon_state = "gravemarker"

	density = TRUE
	anchored = TRUE
	throwpass = 1

	layer = ABOVE_JUNK_LAYER

	//Maybe make these calculate based on material?
	max_integrity = 100

	var/grave_name = ""		//Name of the intended occupant
	var/epitaph = ""		//A quick little blurb
//	var/dir_locked = 0		//Can it be spun?	Not currently implemented

	var/datum/material/material

/obj/structure/gravemarker/Initialize(mapload, material_name)
	. = ..()
	if(!material_name)
		material_name = MAT_WOOD
	material = get_material_by_name("[material_name]")
	if(!material)
		stack_trace("Material of type: [material_name] does not exist.")
		return INITIALIZE_HINT_QDEL
	color = material.icon_colour
	AddElement(/datum/element/climbable)
	AddElement(/datum/element/rotatable)

/obj/structure/gravemarker/examine(mob/user)
	. = ..()
	if(grave_name && get_dist(src, user) < 4)
		. += "Here Lies [grave_name]"
	if(epitaph && get_dist(src, user) < 2)
		. += epitaph

/obj/structure/gravemarker/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSTABLE))
		return TRUE
	if(get_dir(mover, target) == GLOB.reverse_dir[dir]) // From elsewhere to here, can't move against our dir
		return !density
	return TRUE

/obj/structure/gravemarker/Uncross(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSTABLE))
		return TRUE
	if(get_dir(mover, target) == dir) // From here to elsewhere, can't move in our dir
		return !density
	return TRUE

/obj/structure/gravemarker/screwdriver_act(mob/user, obj/item/W)
	var/carving_1 = sanitizeSafe(tgui_input_text(user, "Who is \the [src.name] for?", "Gravestone Naming", null, MAX_NAME_LEN, encode = FALSE), MAX_NAME_LEN)
	if(carving_1)
		user.visible_message("[user] starts carving \the [src.name].", "You start carving \the [src.name].")
		if(do_after(user, material.hardness * W.toolspeed, target = src))
			user.visible_message("[user] carves something into \the [src.name].", "You carve your message into \the [src.name].")
			grave_name += carving_1
			update_icon()
	var/carving_2 = sanitizeSafe(tgui_input_text(user, "What message should \the [src.name] have?", "Epitaph Carving", null, MAX_NAME_LEN, encode = FALSE), MAX_NAME_LEN)
	if(carving_2)
		user.visible_message("[user] starts carving \the [src.name].", "You start carving \the [src.name].")
		if(do_after(user, material.hardness * W.toolspeed, target = src))
			user.visible_message("[user] carves something into \the [src.name].", "You carve your message into \the [src.name].")
			epitaph += carving_2
			update_icon()
	return TRUE

/obj/structure/gravemarker/wrench_act(mob/user, obj/item/W)
	user.visible_message("[user] starts taking down \the [src.name].", "You start taking down \the [src.name].")
	if(do_after(user, material.hardness * W.toolspeed, target = src))
		user.visible_message("[user] takes down \the [src.name].", "You take down \the [src.name].")
		dismantle()
	return TRUE

/obj/structure/gravemarker/atom_destruction(damage_flag)
	visible_message(span_danger("\The [src] falls apart!"))
	dismantle()
	return ..()

/obj/structure/gravemarker/proc/dismantle()
	material.place_dismantled_product(get_turf(src))
	qdel(src)
	return

/obj/structure/gravemarker/ghosts_can_use_rotate_verbs()
	return CONFIG_GET(flag/ghost_interaction)
