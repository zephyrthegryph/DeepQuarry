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
	op("carve", tool(TOOL_SCREWDRIVER), label("Carve"), wait(0),
		asks(/datum/prompt/text, fields = list("title" = "Gravestone Naming", "question" = computed(PROC_REF(name_question)), "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "encode" = FALSE, "timeout" = 0), step = "name"),
		asks(/datum/prompt/text, fields = list("title" = "Epitaph Carving", "question" = computed(PROC_REF(epitaph_question)), "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "encode" = FALSE, "timeout" = 0), step = "epitaph"),
		then(PROC_REF(carved)))
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))
	param(nameof(marker_material), pos = 1, apply = PROC_REF(build_of))

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

/// The name and the epitaph are asked, then carved.
/obj/structure/gravemarker/proc/name_question(datum/act/A)
	return "Who is \the [src.name] for?"

/obj/structure/gravemarker/proc/epitaph_question(datum/act/A)
	return "What message should \the [src.name] have?"

/// The answers are carved in.
/obj/structure/gravemarker/proc/carved(datum/act/op/A)
	var/datum/prompt/name_answer = A.step_answer("name")
	var/datum/prompt/epitaph_answer = A.step_answer("epitaph")
	var/carving_1 = sanitizeSafe(name_answer?.value, MAX_NAME_LEN)
	var/carving_2 = sanitizeSafe(epitaph_answer?.value, MAX_NAME_LEN)
	if(!carving_1 && !carving_2)
		return OP_OK
	act_message(A.actor, null, MSG_SELF("You carve your message into \the [src.name]."), MSG_OTHERS("%U% carves something into \the [src.name]."))
	if(carving_1)
		grave_name += carving_1
	if(carving_2)
		epitaph += carving_2
	return OP_OK

/obj/structure/gravemarker/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	use_tool(user, W, src, delay = material.hardness, quality = TOOL_WRENCH, volume = 0, start_self = "You start taking down 	he [src.name].", start_others = "[user] starts taking down 	he [src.name].", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return OP_OK

/obj/structure/gravemarker/proc/wrench_act_tool_done(mob/user)
	act_message(user, null, MSG_SELF("You take down 	he [src.name]."), MSG_OTHERS("%U% takes down 	he [src.name]."))
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
