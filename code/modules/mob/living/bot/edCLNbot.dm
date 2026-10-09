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
	if(on && bot_busy())
		icon_state = "edCLN"
	else
		icon_state = "edCLN[on]"

/mob/living/bot/cleanbot/edCLN/handleIdle()
	if(vocal && prob(10))
		automatic_custom_emote(AUDIBLE_MESSAGE, "makes a less than thrilled beeping sound.")
		play_sfx(src, SFX_MACHINES_SYNTH_YES)

	if(red_switch && !blue_switch && !green_switch && prob(10) || src.emagged)
		if(istype(loc, /turf/simulated))
			var/turf/simulated/T = loc
			T.add_blood()

	if(!red_switch && blue_switch && !green_switch && prob(50) || src.emagged)
		if(istype(loc, /turf/simulated))
			var/turf/simulated/T = loc
			act_message(src, null, others = span_infoplain(span_bold("%U%") + " squirts a puddle of water on the floor!"))
			T.wet_floor()

	if(!red_switch && !blue_switch && green_switch && prob(10) || src.emagged)
		if(istype(loc, /turf/simulated))
			var/turf/simulated/T = loc
			act_message(src, T, others = span_warning("%U% stomps on %T%, breaking it!"))
			spent(T)

	if(red_switch && blue_switch && green_switch && prob(1))
		src.explode()

/mob/living/bot/cleanbot/edCLN/explode()
	set_on(0)
	act_message(src, null, others = span_danger("%U% blows apart!"))
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

	fx_sparks(src, 3)
	return ..()

/mob/living/bot/cleanbot/edCLN/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["red_switch"] = red_switch
	data["green_switch"] = green_switch
	data["blue_switch"] = blue_switch
	var/list/merged_1 = ui_data_mob_living_bot_cleanbot_edCLN(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /mob/living/bot/cleanbot/edCLN's window data.
/mob/living/bot/cleanbot/edCLN/proc/ui_data_mob_living_bot_cleanbot_edCLN(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["version"] = "v3.0"
	data["rgbpanel"] = TRUE
	return data

CAPABILITIES(/mob/living/bot/cleanbot/edCLN)
	op("red_switch", ui_act(), then(PROC_REF(ui_act_red_switch)))
	op("green_switch", ui_act(), then(PROC_REF(ui_act_green_switch)))
	op("blue_switch", ui_act(), then(PROC_REF(ui_act_blue_switch)))

/mob/living/bot/cleanbot/edCLN/proc/ui_act_red_switch(datum/act/op/A)
	add_fingerprint(A.actor)
	red_switch = !red_switch
	to_chat(A.actor, span_notice("You flip the red switch [red_switch ? "on" : "off"]."))
	return OP_OK

/mob/living/bot/cleanbot/edCLN/proc/ui_act_green_switch(datum/act/op/A)
	add_fingerprint(A.actor)
	green_switch = !green_switch
	to_chat(A.actor, span_notice("You flip the green switch [green_switch ? "on" : "off"]."))
	return OP_OK

/mob/living/bot/cleanbot/edCLN/proc/ui_act_blue_switch(datum/act/op/A)
	add_fingerprint(A.actor)
	blue_switch = !blue_switch
	to_chat(A.actor, span_notice("You flip the blue switch [blue_switch ? "on" : "off"]."))
	return OP_OK

/mob/living/bot/cleanbot/edCLN/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	. = ..()
	if(!emagged)
		if(user)
			to_chat(user, span_notice("The [src] buzzes and beeps."))
			play_sfx(src, SFX_MACHINES_BUZZBEEP)
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

// Renaming with a pen is inherited from /obj/item/secbot_assembly (secbot_assembly_rename).

STAGE_DEF(edcln, bucketed)
STAGE_DEF(edcln, welded)
STAGE_DEF(edcln, sensing)
STAGE_DEF(edcln, wired)
STAGE_DEF(edcln, moped)
STAGE_DEF(edcln, attached)
STAGE_DEF(edcln, finished)

MSG_DEF_SELF(stage/edcln/bucketed, "It has its bucket.")
MSG_DEF_SELF(stage/edcln/welded, "Its bucket is welded on.")
MSG_DEF_SELF(stage/edcln/sensing, "It has its proximity sensor.")
MSG_DEF_SELF(stage/edcln/wired, "It is wired.")
MSG_DEF_SELF(stage/edcln/moped, "It has its mop.")
MSG_DEF_SELF(stage/edcln/attached, "Its mop is attached to the frame.")
MSG_DEF_SELF(stage/edcln/finished, "It is finished.")
MSG_DEF_SELF(edcln/start_attach_mop, "Attatching the mop to the frame...")

CAPABILITIES(/obj/item/secbot_assembly/edCLN_assembly)
	without(CAP_CONSTRUCTION)
	construction(start(STAGE_BOT_FRAME_BARE), bot_frame_legs(),
		stage(STAGE_EDCLN_BUCKETED, item(/obj/item/reagent_containers/glass/bucket), consumes(), wait(0), then(PROC_REF(bucket_added)), undo = NO_UNDO),
		stage(STAGE_EDCLN_WELDED, tool(TOOL_WELDER), wait(0), then(PROC_REF(bucket_welded)), undo = NO_UNDO),
		stage(STAGE_EDCLN_SENSING, item(/obj/item/assembly/prox_sensor), consumes(), wait(0), then(PROC_REF(sensor_added)), undo = NO_UNDO),
		stage(STAGE_EDCLN_WIRED, stack(/obj/item/stack/cable_coil, 1), wait(4 SECONDS), begins(MSG(bot_frame/start_wire)), then(PROC_REF(wired_up)), undo = NO_UNDO),
		stage(STAGE_EDCLN_MOPED, item(/obj/item/mop), consumes(), wait(0), then(PROC_REF(mop_added)), undo = NO_UNDO),
		stage(STAGE_EDCLN_ATTACHED, tool(TOOL_SCREWDRIVER), wait(4 SECONDS), begins(MSG(edcln/start_attach_mop)), then(PROC_REF(mop_attached)), undo = NO_UNDO),
		stage(STAGE_EDCLN_FINISHED, item(/obj/item/cell), consumes(), wait(0), then(PROC_REF(finished)), undo = NO_UNDO))

/obj/item/secbot_assembly/edCLN_assembly/proc/bucket_added(datum/act/op/A)
	name = "bucket/legs/frame assembly"
	item_state = "edCLN_bucket"
	icon_state = "edCLN_bucket"
	to_chat(A.actor, span_notice("You add \the [A.held] to \the [src]."))
	return OP_OK

/obj/item/secbot_assembly/edCLN_assembly/proc/bucket_welded(datum/act/op/A)
	name = "bucketed frame assembly"
	to_chat(A.actor, span_notice("You welded the bucket to \the [src]."))
	return OP_OK

/obj/item/secbot_assembly/edCLN_assembly/sensor_added(datum/act/op/A)
	name = "proximity bucket ED assembly"
	item_state = "edCLN_prox"
	icon_state = "edCLN_prox"
	to_chat(A.actor, span_notice("You add \the [A.held] to \the [src]."))
	return OP_OK

/obj/item/secbot_assembly/edCLN_assembly/proc/wired_up(datum/act/op/A)
	name = "wired ED-CLN assembly"
	to_chat(A.actor, span_notice("You wire the ED-CLN assembly."))
	return OP_OK

/obj/item/secbot_assembly/edCLN_assembly/proc/mop_added(datum/act/op/A)
	name = "mop ED-CLN assembly"
	item_state = "edCLN_mop"
	icon_state = "edCLN_mop"
	to_chat(A.actor, span_notice("You add \the [A.held] to \the [src]."))
	return OP_OK

/obj/item/secbot_assembly/edCLN_assembly/proc/mop_attached(datum/act/op/A)
	name = "mopped ED-CLN assembly"
	to_chat(A.actor, span_notice("Mop attached."))
	return OP_OK

/obj/item/secbot_assembly/edCLN_assembly/finished(datum/act/op/A)
	to_chat(A.actor, span_notice("You complete the ED-CLN."))
	var/turf/where = get_turf(src)
	var/mob/living/bot/cleanbot/edCLN/bot = new /mob/living/bot/cleanbot/edCLN(where)
	bot.name = created_name
	consume(src, A.actor)
	return OP_OK
