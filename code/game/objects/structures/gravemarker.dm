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

	var/datum/material/material

CAPABILITIES(/obj/structure/gravemarker)
	climb()
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))
	param(nameof(marker_material), pos = 1, apply = PROC_REF(build_of))

CAPABILITIES(/datum/prompt/text/grave_carving)
	ref_one(nameof(tool), /obj/item)

/// The marker's material (its constructor param).
/obj/structure/gravemarker/var/marker_material = MAT_WOOD

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/structure/gravemarker/proc/build_of(material_name)
	material = get_material_by_name("[material_name || MAT_WOOD]")
	if(!material)
		stack_trace("Material of type: [material_name] does not exist.")
		spent(src)
		return
	color = material.icon_colour
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
	open_request(src, /datum/prompt/text/grave_carving, PROC_REF(grave_name_chosen), valid = PROC_REF(carving_valid), answerer = user, tool = W, title = "Gravestone Naming", question = "Who is \the [src] for?", max_len = MAX_NAME_LEN, name_text = TRUE, encode = FALSE, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
	return TRUE

/// Carving a gravemarker: the name, then the epitaph. Re-checked: next to the marker, the tool still in the active hand.
/datum/prompt/text/grave_carving
	/// Set on the epitaph step: the name answered first.
	var/carved_name
	var/obj/item/tool

/// The carver still holds the tool.
/obj/structure/gravemarker/proc/carving_valid(datum/request/R)
	var/datum/prompt/text/grave_carving/C = R
	var/mob/M = R.answerer
	return istype(M) && M.get_active_hand() == C.tool

/obj/structure/gravemarker/proc/grave_name_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/text/grave_carving/C = A.request
	open_request(src, /datum/prompt/text/grave_carving, PROC_REF(carvings_chosen), valid = PROC_REF(carving_valid), answerer = C.answerer, tool = C.tool, carved_name = A.answer.value, title = "Epitaph Carving", question = "What message should \the [src] have?", max_len = MAX_NAME_LEN, name_text = TRUE, encode = FALSE, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)

/obj/structure/gravemarker/proc/carvings_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/text/grave_carving/C = A.request
	var/mob/user = C.answerer
	var/obj/item/W = C.tool
	var/carving_1 = sanitizeSafe(C.carved_name, MAX_NAME_LEN)
	var/carving_2 = sanitizeSafe(A.answer.value, MAX_NAME_LEN)
	if(carving_1)
		use_tool(user, W, src, delay = material.hardness, quality = TOOL_SCREWDRIVER, volume = 0, start_self = "You start carving \the [src.name].", start_others = "[user] starts carving \the [src.name].", receiver = src, on_done = PROC_REF(screwdriver_act_tool_done), done_args = list(user, carving_1))
	if(carving_2)
		use_tool(user, W, src, delay = material.hardness, quality = TOOL_SCREWDRIVER, volume = 0, start_self = "You start carving \the [src.name].", start_others = "[user] starts carving \the [src.name].", receiver = src, on_done = PROC_REF(screwdriver_act_tool_done2), done_args = list(user, carving_2))

/obj/structure/gravemarker/proc/screwdriver_act_tool_done(mob/user, carving_1)
	act_message(user, null, MSG_SELF("You carve your message into \the [src.name]."), MSG_OTHERS("%U% carves something into \the [src.name]."))
	grave_name += carving_1
	update_icon()
/obj/structure/gravemarker/proc/screwdriver_act_tool_done2(mob/user, carving_2)
	act_message(user, null, MSG_SELF("You carve your message into \the [src.name]."), MSG_OTHERS("%U% carves something into \the [src.name]."))
	epitaph += carving_2
	update_icon()

/obj/structure/gravemarker/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	use_tool(user, W, src, delay = material.hardness, quality = TOOL_WRENCH, volume = 0, start_self = "You start taking down \the [src.name].", start_others = "[user] starts taking down \the [src.name].", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return OP_OK

/obj/structure/gravemarker/proc/wrench_act_tool_done(mob/user)
	act_message(user, null, MSG_SELF("You take down \the [src.name]."), MSG_OTHERS("%U% takes down \the [src.name]."))
	dismantle(user)

/obj/structure/gravemarker/atom_destruction(damage_flag)
	visible_message(span_danger("\The [src] falls apart!"))
	dismantle()
	return ..()

/obj/structure/gravemarker/proc/dismantle(mob/user)
	material.place_dismantled_product(get_turf(src))
	consume(src, user)
	return

/obj/structure/gravemarker/ghosts_can_use_rotate_verbs()
	return CONFIG_GET(flag/ghost_interaction)
