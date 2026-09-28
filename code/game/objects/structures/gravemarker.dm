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
	make_climbable()
	make_rotatable()

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
	om_prompt_sequence(src, user, list(
		list("key" = "name", "kind" = "text", "message" = "Who is \the [src.name] for?", "title" = "Gravestone Naming", "max_length" = MAX_NAME_LEN, "encode" = FALSE),
		list("key" = "epitaph", "kind" = "text", "message" = "What message should \the [src.name] have?", "title" = "Epitaph Carving", "max_length" = MAX_NAME_LEN, "encode" = FALSE),
	), PROC_REF(carvings_chosen), list("requires" = PROMPT_ADJACENT, "data" = list("tool" = W)))
	return TRUE

/obj/structure/gravemarker/proc/carvings_chosen(mob/user, datum/om/prompt/ask)
	var/obj/item/W = ask.get("tool")
	if(user.get_active_hand() != W)
		return
	var/carving_1 = sanitizeSafe(ask.get("name"), MAX_NAME_LEN)
	var/carving_2 = sanitizeSafe(ask.get("epitaph"), MAX_NAME_LEN)
	if(carving_1)
		use_tool(user, W, src, delay = material.hardness, quality = TOOL_SCREWDRIVER, volume = 0, message_self = "You start carving \the [src.name].", message_others = "[user] starts carving \the [src.name].", receiver = src, on_done = PROC_REF(screwdriver_act_tool_done), done_args = list(user, carving_1))
	if(carving_2)
		use_tool(user, W, src, delay = material.hardness, quality = TOOL_SCREWDRIVER, volume = 0, message_self = "You start carving \the [src.name].", message_others = "[user] starts carving \the [src.name].", receiver = src, on_done = PROC_REF(screwdriver_act_tool_done2), done_args = list(user, carving_2))

/obj/structure/gravemarker/proc/screwdriver_act_tool_done(mob/user, carving_1)
	user.visible_message("[user] carves something into \the [src.name].", "You carve your message into \the [src.name].")
	grave_name += carving_1
	update_icon()
/obj/structure/gravemarker/proc/screwdriver_act_tool_done2(mob/user, carving_2)
	user.visible_message("[user] carves something into \the [src.name].", "You carve your message into \the [src.name].")
	epitaph += carving_2
	update_icon()

/obj/structure/gravemarker/wrench_act(mob/user, obj/item/W)
	use_tool(user, W, src, delay = material.hardness, quality = TOOL_WRENCH, volume = 0, message_self = "You start taking down \the [src.name].", message_others = "[user] starts taking down \the [src.name].", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return TRUE

/obj/structure/gravemarker/proc/wrench_act_tool_done(mob/user)
	user.visible_message("[user] takes down \the [src.name].", "You take down \the [src.name].")
	dismantle()

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
