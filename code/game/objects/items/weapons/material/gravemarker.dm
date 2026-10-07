/obj/item/material/gravemarker
	name = "grave marker"
	desc = "An object used in marking graves."
	icon_state = "gravemarker"
	w_class = ITEMSIZE_LARGE
	fragile = 1
	force_divisor = 0.65
	thrown_force_divisor = 0.25

	var/icon_changes = 1	//Does the sprite change when you put words on it?
	var/grave_name = ""		//Name of the intended occupant
	var/epitaph = ""		//A quick little blurb


/// The name and the epitaph are asked, then carved.
/obj/item/material/gravemarker/proc/name_question(datum/act/A)
	return "Who is \the [src.name] for?"

/obj/item/material/gravemarker/proc/epitaph_question(datum/act/A)
	return "What message should \the [src.name] have?"

/// The answers are carved in.
/obj/item/material/gravemarker/proc/carved(datum/act/op/A)
	var/datum/prompt/name_answer = A.step_answer("name")
	var/datum/prompt/epitaph_answer = A.step_answer("epitaph")
	var/carving_1 = sanitizeSafe(name_answer?.value, MAX_NAME_LEN)
	var/carving_2 = sanitizeSafe(epitaph_answer?.value, MAX_NAME_LEN)
	if(!carving_1 && !carving_2)
		return OP_OK
	act_message(A.actor, src, MSG_SELF("You carve your message into %T%."), MSG_OTHERS("%U% carves something into %T%."))
	if(carving_1)
		grave_name += carving_1
	if(carving_2)
		epitaph += carving_2
	update_icon()
	return OP_OK

/obj/item/material/gravemarker/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	use_tool(user, W, src, delay = material.hardness, quality = TOOL_WRENCH, start_self = "You start carving 	he [src.name].", start_others = "[user] starts carving 	he [src.name].", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return OP_DECLINE

/obj/item/material/gravemarker/proc/wrench_act_tool_done(mob/user)
	var/datum/material/refund_material = material
	var/turf/location = get_turf(src)
	var/marker_name = "	he [src]"
	if(!consume(src, user))
		return
	refund_material.place_dismantled_product(location)
	act_message(user, location, MSG_SELF("You dismantle [marker_name]."), MSG_OTHERS("%U% dismantles down [marker_name]."))

/obj/item/material/gravemarker/examine(mob/user)
	. = ..()
	if(grave_name && get_dist(src, user) < 4)
		. += "Here Lies [grave_name]"
	if(epitaph && get_dist(src, user) < 2)
		. += epitaph

DECLARE_APPEARANCE_PROC(/obj/item/material/gravemarker, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/material/gravemarker/appearance_overlays()
	. = list()
	if(icon_changes)
		if(grave_name && epitaph)
			icon_state = "[initial(icon_state)]_3"
		else if(grave_name)
			icon_state = "[initial(icon_state)]_1"
		else if(epitaph)
			icon_state = "[initial(icon_state)]_2"
		else
			icon_state = initial(icon_state)

	. += ..()

CAPABILITIES(/obj/item/material/gravemarker)
	op("self", in_hand(), needs(req(PROC_REF(on_turf), silent = TRUE), req(PROC_REF(spot_free), because = MSG(gravemarker/occupied))),
		begins(MSG(gravemarker/placing)), wait(1 SECOND), then(PROC_REF(place_done)))
	op("carve", tool(TOOL_SCREWDRIVER), label("Carve"), wait(0),
		asks(/datum/prompt/text, fields = list("title" = "Gravestone Naming", "question" = computed(PROC_REF(name_question)), "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "encode" = FALSE, "timeout" = 0), step = "name"),
		asks(/datum/prompt/text, fields = list("title" = "Epitaph Carving", "question" = computed(PROC_REF(epitaph_question)), "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "encode" = FALSE, "timeout" = 0), step = "epitaph"),
		then(PROC_REF(carved)))
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))

MSG_DEF_SELF(gravemarker/placing, "You begin to place %T%.")
MSG_DEF_SELF(gravemarker/occupied, "There's already something there.")

/// Requirement: the actor stands on a turf.
/obj/item/material/gravemarker/proc/on_turf(datum/act/op/A)
	return atom_on_turf(A.actor)

/// The grave marker where `A` stands, or null.
/proc/grave_marker_at(atom/A)
	READS_FROM() // what stands where an atom does is asked when the op starts
	return locate(/obj/structure/gravemarker, A.loc)

/// Requirement: no marker stands where the actor does.
/obj/item/material/gravemarker/proc/spot_free(datum/act/op/A)
	return !grave_marker_at(A.actor)

/obj/item/material/gravemarker/proc/place_done(datum/act/op/A)
	var/mob/user = A.actor
	if(!isturf(user.loc) || locate(/obj/structure/gravemarker, user.loc))
		return OP_OK
	var/obj/structure/gravemarker/G = new /obj/structure/gravemarker/(user.loc, src.get_material())
	to_chat(user, span_notice("You place [src.name]."))
	G.grave_name = grave_name
	G.epitaph = epitaph
	G.add_fingerprint(user)
	G.dir = user.dir
	QDEL_NULL(src)
	return
