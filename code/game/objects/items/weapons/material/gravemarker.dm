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


/obj/item/material/gravemarker/screwdriver_act(mob/user, obj/item/W)
	om_ask(user, /datum/om/prompt/text/gravemarker_carving, PROC_REF(grave_name_chosen), title = "Gravestone Naming", message = "Who is \the [src.name] for?", subject = W)
	return NONE

/// A carving for a grave marker (the name, then the epitaph). Re-checked on the answer: the tool (the subject) is still in hand.
/datum/om/prompt/text/gravemarker_carving
	max_length = MAX_NAME_LEN
	encode = FALSE
	ask_flags = ASK_HELD | ASK_CAPABLE
	/// The name given at the first step.
	var/carved_name

/obj/item/material/gravemarker/proc/grave_name_chosen(datum/om/prompt/text/gravemarker_carving/ask)
	om_ask(ask.answerer, /datum/om/prompt/text/gravemarker_carving, PROC_REF(carvings_chosen), title = "Epitaph Carving", message = "What message should \the [src.name] have?", subject = ask.subject, carved_name = ask.text)

/obj/item/material/gravemarker/proc/carvings_chosen(datum/om/prompt/text/gravemarker_carving/ask)
	var/mob/user = ask.answerer
	var/obj/item/W = ask.subject
	var/carving_1 = sanitizeSafe(ask.carved_name, MAX_NAME_LEN)
	var/carving_2 = sanitizeSafe(ask.text, MAX_NAME_LEN)
	if(carving_1)
		use_tool(user, W, src, delay = material.hardness, quality = TOOL_SCREWDRIVER, start_self = "You start carving \the [src.name].", start_others = "[user] starts carving \the [src.name].", receiver = src, on_done = PROC_REF(screwdriver_act_tool_done), done_args = list(user, carving_1))
	if(carving_2)
		use_tool(user, W, src, delay = material.hardness, quality = TOOL_SCREWDRIVER, start_self = "You start carving \the [src.name].", start_others = "[user] starts carving \the [src.name].", receiver = src, on_done = PROC_REF(screwdriver_act_tool_done2), done_args = list(user, carving_2))

/obj/item/material/gravemarker/proc/screwdriver_act_tool_done(mob/user, carving_1)
	user.visible_message("[user] carves something into \the [src.name].", "You carve your message into \the [src.name].")
	grave_name += carving_1
	update_icon()
/obj/item/material/gravemarker/proc/screwdriver_act_tool_done2(mob/user, carving_2)
	user.visible_message("[user] carves something into \the [src.name].", "You carve your message into \the [src.name].")
	epitaph += carving_2
	update_icon()

/obj/item/material/gravemarker/wrench_act(mob/user, obj/item/W)
	use_tool(user, W, src, delay = material.hardness, quality = TOOL_WRENCH, start_self = "You start carving \the [src.name].", start_others = "[user] starts carving \the [src.name].", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return NONE

/obj/item/material/gravemarker/proc/wrench_act_tool_done(mob/user)
	material.place_dismantled_product(get_turf(src))
	user.visible_message("[user] dismantles down \the [src.name].", "You dismantle \the [src.name].")
	qdel(src)

/obj/item/material/gravemarker/examine(mob/user)
	. = ..()
	if(grave_name && get_dist(src, user) < 4)
		. += "Here Lies [grave_name]"
	if(epitaph && get_dist(src, user) < 2)
		. += epitaph

/obj/item/material/gravemarker/update_icon()
	if(icon_changes)
		if(grave_name && epitaph)
			icon_state = "[initial(icon_state)]_3"
		else if(grave_name)
			icon_state = "[initial(icon_state)]_1"
		else if(epitaph)
			icon_state = "[initial(icon_state)]_2"
		else
			icon_state = initial(icon_state)

	..()

DECLARE_INTERACTIONS(/obj/item/material/gravemarker, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/material/gravemarker/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	src.add_fingerprint(user)

	if(!isturf(user.loc))
		return TRUE

	if(locate(/obj/structure/gravemarker, user.loc))
		to_chat(user, span_warning("There's already something there."))
		return TRUE
	else
		to_chat(user, span_notice("You begin to place \the [src.name]."))
		om_task_timed(user, 1 SECOND, target = src, receiver = src, on_done = PROC_REF(place_done), done_args = list(user))
	return TRUE

/obj/item/material/gravemarker/proc/place_done(mob/user)
	if(!isturf(user.loc) || locate(/obj/structure/gravemarker, user.loc))
		return
	var/obj/structure/gravemarker/G = new /obj/structure/gravemarker/(user.loc, src.get_material())
	to_chat(user, span_notice("You place \the [src.name]."))
	G.grave_name = grave_name
	G.epitaph = epitaph
	G.add_fingerprint(user)
	G.dir = user.dir
	QDEL_NULL(src)
	return
