/mob/living/bot/cleanbot/edCLN
	name = "ED-CLN Cleaning Robot"
	desc = "A large cleaning robot. It looks rather efficient."
	icon_state = "edCLN0"
	req_one_access = list(ACCESS_ROBOTICS, ACCESS_JANITOR)
	botcard_access = list(ACCESS_JANITOR)

	locked = 0 // Start unlocked so roboticist can set them to patrol.
	wait_if_pulled = 0 // One big boi.
	min_target_dist = 0

	patrol_speed = 3
	target_speed = 6
	cTimeMult = 0.3 // Big bois should be big fast :3

	vocal = 1
	cleaning = 0
	var/red_switch = 0
	var/blue_switch = 0
	var/green_switch = 0

/mob/living/bot/cleanbot/edCLN/update_icons()
	if(on && busy)
		icon_state = "edCLN"
	else
		icon_state = "edCLN[on]"

/mob/living/bot/cleanbot/edCLN/handleIdle()
	if(vocal && prob(10))
		automatic_custom_emote(AUDIBLE_MESSAGE, "makes a less than thrilled beeping sound.")
		playsound(src, 'sound/machines/synth_yes.ogg', 50, 0)

	if(red_switch && !blue_switch && !green_switch && prob(10) || src.emagged)
		if(istype(loc, /turf/simulated))
			var/turf/simulated/T = loc
			T.add_blood()

	if(!red_switch && blue_switch && !green_switch && prob(50) || src.emagged)
		if(istype(loc, /turf/simulated))
			var/turf/simulated/T = loc
			visible_message(span_infoplain(span_bold("\The [src]") + " squirts a puddle of water on the floor!"))
			T.wet_floor()

	if(!red_switch && !blue_switch && green_switch && prob(10) || src.emagged)
		if(istype(loc, /turf/simulated))
			var/turf/simulated/T = loc
			visible_message(span_warning("\The [src] stomps on \the [T], breaking it!"))
			qdel(T)

	if(red_switch && blue_switch && green_switch && prob(1))
		src.explode()

/mob/living/bot/cleanbot/edCLN/explode()
	on = 0
	visible_message(span_danger("[src] blows apart!"))
	var/turf/Tsec = get_turf(src)

	new /obj/item/secbot_assembly/ed209_assembly(Tsec)
	if(prob(50))
		new /obj/item/robot_parts/l_leg(Tsec)
	if(prob(50))
		new /obj/item/robot_parts/r_leg(Tsec)
	if(prob(50))
		if(prob(50))
			new /obj/item/reagent_containers/glass/bucket(Tsec)
		else
			new /obj/item/assembly/prox_sensor(Tsec)

	var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
	s.set_up(3, 1, src)
	s.start()
	//qdel(src)
	return ..()

/mob/living/bot/cleanbot/edCLN/tgui_data(mob/user)
	var/list/data = ..()
	data["version"] = "v3.0"
	data["rgbpanel"] = TRUE
	data["red_switch"] = red_switch
	data["green_switch"] = green_switch
	data["blue_switch"] = blue_switch
	return data

/mob/living/bot/cleanbot/edCLN/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE
	switch(action)
		if("red_switch")
			red_switch = !red_switch
			to_chat(ui.user, span_notice("You flip the red switch [red_switch ? "on" : "off"]."))
			. = TRUE
		if("green_switch")
			green_switch = !green_switch
			to_chat(ui.user, span_notice("You flip the green switch [green_switch ? "on" : "off"]."))
			. = TRUE
		if("blue_switch")
			blue_switch = !blue_switch
			to_chat(ui.user, span_notice("You flip the blue switch [blue_switch ? "on" : "off"]."))
			. = TRUE

/mob/living/bot/cleanbot/edCLN/emag_act(remaining_uses, mob/user)
	. = ..()
	if(!emagged)
		if(user)
			to_chat(user, span_notice("The [src] buzzes and beeps."))
			playsound(src, 'sound/machines/buzzbeep.ogg', 50, 0)
		emagged = 1
		return 1

// Assembly

/obj/item/secbot_assembly/edCLN_assembly
	name = "ED-CLN assembly"
	desc = "Some sort of bizarre assembly."
	icon = 'icons/obj/aibots.dmi'
	icon_state = "ed209_frame"
	item_state = "buildpipe"
	created_name = "ED-CLN Security Robot"
	construction_graph = /datum/construction_graph/secbot_assembly/edCLN

// Renaming the finished bot is not construction: keep it a plain interaction.
/obj/item/secbot_assembly/edCLN_assembly/attackby(obj/item/W as obj, mob/user as mob)
	..()
	if(istype(W, /obj/item/pen))
		var/t = sanitizeSafe(tgui_input_text(user, "Enter new robot name", name, created_name, MAX_NAME_LEN, encode = FALSE), MAX_NAME_LEN)
		if(!t)
			return
		if(!in_range(src, user) && src.loc != user)
			return
		created_name = t

/datum/construction_graph/secbot_assembly/edCLN
	id = "edCLN_assembly"
	states = list(0, 1, 2, 3, 4, 5, 6, 7, 8)
	initial_states = list(0)
	state_var = "build_step"
	edge_types = list(
		/datum/interaction/construction/secbot/edCLN/leg_0,
		/datum/interaction/construction/secbot/edCLN/leg_1,
		/datum/interaction/construction/secbot/edCLN/bucket,
		/datum/interaction/construction/secbot/edCLN/weld_bucket,
		/datum/interaction/construction/secbot/edCLN/prox,
		/datum/interaction/construction/secbot/edCLN/wire,
		/datum/interaction/construction/secbot/edCLN/mop,
		/datum/interaction/construction/secbot/edCLN/attach_mop,
		/datum/interaction/construction/secbot/edCLN/finish,
	)

/datum/interaction/construction/secbot/edCLN/leg_0
	parent_type = /datum/interaction/construction/secbot/leg
	from_state = 0
	to_state = 1

/datum/interaction/construction/secbot/edCLN/leg_1
	parent_type = /datum/interaction/construction/secbot/leg
	from_state = 1
	to_state = 2

/datum/interaction/construction/secbot/edCLN/bucket
	from_state = 2
	to_state = 3
	step_text = "add a bucket"
	item_type = /obj/item/reagent_containers/glass/bucket
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/edCLN/bucket/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/edCLN_assembly/assembly = target
	assembly.name = "bucket/legs/frame assembly"
	assembly.item_state = "edCLN_bucket"
	assembly.icon_state = "edCLN_bucket"
	to_chat(actor, span_notice("You add \the [held] to \the [target]."))
	return TRUE

/datum/interaction/construction/secbot/edCLN/weld_bucket
	from_state = 3
	to_state = 4
	step_text = "weld the bucket on"
	tool = TOOL_WELDER

/datum/interaction/construction/secbot/edCLN/weld_bucket/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/edCLN_assembly/assembly = target
	assembly.name = "bucketed frame assembly"
	to_chat(actor, span_notice("You welded the bucket to \the [target]."))
	return TRUE

/datum/interaction/construction/secbot/edCLN/prox
	from_state = 4
	to_state = 5
	step_text = "add the prox sensor"
	item_type = /obj/item/assembly/prox_sensor
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/edCLN/prox/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/edCLN_assembly/assembly = target
	assembly.name = "proximity bucket ED assembly"
	assembly.item_state = "edCLN_prox"
	assembly.icon_state = "edCLN_prox"
	to_chat(actor, span_notice("You add \the [held] to \the [target]."))
	return TRUE

/datum/interaction/construction/secbot/edCLN/wire
	from_state = 5
	to_state = 6
	step_text = "wire it"
	item_type = /obj/item/stack/cable_coil
	item_amount = 1
	item_use = CONSTRUCTION_ITEM_USE
	duration = 4 SECONDS
	tool_scaled = FALSE
	start_self = "You start to wire %TARGET%."

/datum/interaction/construction/secbot/edCLN/wire/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/edCLN_assembly/assembly = target
	assembly.name = "wired ED-CLN assembly"
	to_chat(actor, span_notice("You wire the ED-CLN assembly."))
	return TRUE

/datum/interaction/construction/secbot/edCLN/mop
	from_state = 6
	to_state = 7
	step_text = "add a mop"
	item_type = /obj/item/mop
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/edCLN/mop/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/edCLN_assembly/assembly = target
	assembly.name = "mop ED-CLN assembly"
	assembly.item_state = "edCLN_mop"
	assembly.icon_state = "edCLN_mop"
	to_chat(actor, span_notice("You add \the [held] to \the [target]."))
	return TRUE

/datum/interaction/construction/secbot/edCLN/attach_mop
	from_state = 7
	to_state = 8
	step_text = "attach the mop to the frame"
	tool = TOOL_SCREWDRIVER
	tool_volume = 100
	duration = 4 SECONDS
	tool_scaled = FALSE
	start_self = "Attatching the mop to the frame..."

/datum/interaction/construction/secbot/edCLN/attach_mop/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/edCLN_assembly/assembly = target
	assembly.name = "mopped ED-CLN assembly"
	to_chat(actor, span_notice("Mop attached."))
	return TRUE

/datum/interaction/construction/secbot/edCLN/finish
	from_state = 8
	to_state = CONSTRUCTION_DONE
	step_text = "install a cell to finish it"
	item_type = /obj/item/cell
	item_use = CONSTRUCTION_ITEM_DELETE

/datum/interaction/construction/secbot/edCLN/finish/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/item/secbot_assembly/edCLN_assembly/assembly = target
	to_chat(actor, span_notice("You complete the ED-CLN."))
	var/turf/where = get_turf(assembly)
	var/mob/living/bot/cleanbot/edCLN/bot = new /mob/living/bot/cleanbot/edCLN(where)
	bot.name = assembly.created_name
	actor.drop_from_inventory(assembly)
	qdel(assembly)
	return TRUE
