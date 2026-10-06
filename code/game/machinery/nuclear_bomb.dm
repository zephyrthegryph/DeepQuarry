GLOBAL_VAR(bomb_set)

/obj/machinery/nuclearbomb
	// The armed device owns its detonation lifecycle; ambient blasts cannot remove it.
	resistance_flags = INDESTRUCTIBLE
	name = "\improper Nuclear Fission Explosive"
	desc = "Uh oh. RUN!!!!"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "nuclearbomb0"
	density = TRUE
	var/deployable = 0.0
	var/extended = 0.0
	var/lighthack = 0
	var/opened = 0.0
	var/timeleft = 60.0
	var/timing = 0.0
	var/r_code = "ADMIN"
	var/code = ""
	var/yes_code = 0.0
	var/safety = 1.0
	var/obj/item/disk/nuclear/auth
	var/list/wires_list
	var/light_wire
	var/safety_wire
	var/timing_wire
	var/removal_stage = 0 // 0 is no removal, 1 is covers removed, 2 is covers open,
	  					// 3 is sealant open, 4 is unwrenched, 5 is removed from bolts.
	// TGUI: which view the same TGUI window shows. attack_hand sets
	// it FALSE for the main control panel; wirecutter/multitool use sets it
	// TRUE for the wire-defusion panel.
	var/wire_view = FALSE
	use_power = USE_POWER_OFF

// ALLOW(init/INSTANCE_STATE): rolls its code and its wire layout for each bomb
/obj/machinery/nuclearbomb/Initialize(mapload)
	. = ..()
	r_code = "[rand(10000, 99999.0)]"//Creates a random code upon object spawn.
	LAZYSET(wires_list, "Red", 0)
	LAZYSET(wires_list, "Blue", 0)
	LAZYSET(wires_list, "Green", 0)
	LAZYSET(wires_list, "Marigold", 0)
	LAZYSET(wires_list, "Fuschia", 0)
	LAZYSET(wires_list, "Black", 0)
	LAZYSET(wires_list, "Pearl", 0)
	var/list/w = list("Red","Blue","Green","Marigold","Black","Fuschia","Pearl")
	light_wire = pick(w)
	w -= light_wire
	timing_wire = pick(w)
	w -= timing_wire
	safety_wire = pick(w)
	w -= safety_wire

/obj/machinery/nuclearbomb/proc/work_step(datum/act/timer/A)
	if(timing)
		GLOB.bomb_set = 1 //So long as there is one nuke timing, it means one nuke is armed.
		timeleft--
		play_sfx(src, SFX_ITEMS_TIMER)
		if(timeleft <= 0)
			explode()
		for(var/mob/M in viewers(1, src))
			if((M.client && M.check_current_machine(src)))
				attack_hand(M)
	return PROCESS_KILL

/obj/machinery/nuclearbomb/proc/is_extended(mob/actor, atom/target, obj/item/held)
	return extended // ALLOW(reads): the legacy check is read when the op is tried, never from a cached menu

/// Requirement (was REQ_* is_extended): the legacy check answers TRUE to pass.
/obj/machinery/nuclearbomb/proc/is_extended_holds(datum/act/op/A)
	var/answer = is_extended(A.actor, src, A.held)
	return !istext(answer) && !!answer

/obj/machinery/nuclearbomb/proc/interaction_insert_disk(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(!insert_auth_disk(user, O))
		return TRUE
	add_fingerprint(user)
	return TRUE

/// Check the disk's actual source before recording its authentication relation.
/obj/machinery/nuclearbomb/proc/insert_auth_disk(mob/user, obj/item/disk)
	if(!own_bring_in(src, nameof(auth), disk, null, user, TRUE, null, FALSE))
		return FALSE
	rel_set(src, nameof(auth), disk)
	return TRUE

/obj/machinery/nuclearbomb/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	playsound(src, tool.usesound, 50, 1)
	add_fingerprint(user)
	if(auth())
		if(opened == 0)
			opened = 1
			add_overlay("npanel_open")
			to_chat(user, "You unscrew the control panel of [src].")

		else
			opened = 0
			cut_overlay("npanel_open")
			to_chat(user, "You screw the control panel of [src] back on.")
	else
		if(opened == 0)
			to_chat(user, "The [src] emits a buzzing noise, the panel staying locked in.")
		if(opened == 1)
			opened = 0
			cut_overlay("npanel_open")
			to_chat(user, "You screw the control panel of [src] back on.")
		flick("nuclearbombc", src)
	return OP_OK

/// The wirecutters or a multitool: behind the open cover, the wiring window.
/obj/machinery/nuclearbomb/proc/wire_tool_used(datum/act/op/A)
	add_fingerprint(A.actor)
	if(opened == 1)
		nukehack_win(A.actor)
	return OP_OK

/obj/machinery/nuclearbomb/proc/welder_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	add_fingerprint(user)
	if(!anchored)
		return OP_DECLINE
	switch(removal_stage)
		if(0)
			use_tool(user, tool, src, delay = 4 SECONDS, quality = TOOL_WELDER, amount = 5, volume = 0, start_self = "You start cutting loose the anchoring bolt covers with [tool]...", start_others = "[user] starts cutting loose the anchoring bolt covers on [src].", receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user))
			return OP_OK
		if(2)
			use_tool(user, tool, src, delay = 4 SECONDS, quality = TOOL_WELDER, amount = 5, volume = 50, start_self = "You start cutting apart the anchoring system's sealant with [tool]...", start_others = "[user] starts cutting apart the anchoring system sealant on [src].", receiver = src, on_done = PROC_REF(welder_act_tool_done2), done_args = list(user))
			return OP_OK
	return OP_OK

/obj/machinery/nuclearbomb/proc/welder_act_tool_done(mob/user)
	if(!src || !user)
		return ITEM_INTERACT_SUCCESS
	act_message(user, src, MSG_SELF("You cut through the bolt cover."), MSG_OTHERS("%U% cuts through the bolt covers on %T%."))
	removal_stage = 1
/obj/machinery/nuclearbomb/proc/welder_act_tool_done2(mob/user)
	if(!src || !user)
		return ITEM_INTERACT_SUCCESS
	act_message(user, src, MSG_SELF("You cut apart the anchoring system's sealant."), MSG_OTHERS("%U% cuts apart the anchoring system sealant on %T%."))
	removal_stage = 3

/obj/machinery/nuclearbomb/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	add_fingerprint(user)
	if(!anchored)
		return OP_DECLINE
	switch(removal_stage)
		if(1)
			use_tool(user, tool, src, delay = 15, quality = TOOL_CROWBAR, volume = 50, start_self = "You start forcing open the anchoring bolt covers with [tool]...", start_others = "[user] starts forcing open the bolt covers on [src].", receiver = src, on_done = PROC_REF(crowbar_act_tool_done), done_args = list(user))
			return OP_OK
		if(4)
			use_tool(user, tool, src, delay = 8 SECONDS, quality = TOOL_CROWBAR, volume = 50, start_self = "You begin lifting the device off the anchors...", start_others = "[user] begins lifting [src] off of the anchors.", receiver = src, on_done = PROC_REF(crowbar_act_tool_done2), done_args = list(user))
			return OP_OK
	return OP_OK

/obj/machinery/nuclearbomb/proc/crowbar_act_tool_done(mob/user)
	if(!src || !user)
		return ITEM_INTERACT_SUCCESS
	act_message(user, src, MSG_SELF("You force open the bolt covers."), MSG_OTHERS("%U% forces open the bolt covers on %T%."))
	removal_stage = 2
/obj/machinery/nuclearbomb/proc/crowbar_act_tool_done2(mob/user)
	if(!src || !user)
		return ITEM_INTERACT_SUCCESS
	act_message(user, src, MSG_SELF("You jam the crowbar under the nuclear device and lift it off its anchors. You can now move it!"), \
		MSG_OTHERS("%U% crowbars %T% off of the anchors. It can now be moved."))
	set_anchored(FALSE)
	removal_stage = 5

/obj/machinery/nuclearbomb/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	add_fingerprint(user)
	if(!anchored)
		return OP_DECLINE
	if(removal_stage != 3)
		return OP_OK
	use_tool(user, tool, src, delay = 5 SECONDS, quality = TOOL_WRENCH, volume = 50, start_self = "You begin unwrenching the anchoring bolts...", start_others = "[user] begins unwrenching the anchoring bolts on [src].", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return OP_OK

/obj/machinery/nuclearbomb/proc/wrench_act_tool_done(mob/user)
	if(!src || !user)
		return ITEM_INTERACT_SUCCESS
	act_message(user, src, MSG_SELF("You unwrench the anchoring bolts."), MSG_OTHERS("%U% unwrenches the anchoring bolts on %T%."))
	removal_stage = 4

// TGUI migration. attack_hand opens the main control view
// of NuclearBomb.tsx; nukehack_win switches to the wire-defusion view of
// the same window. All keypad/auth/timer/safety/anchor and wire/pulse
// actions are dispatched via tgui_act below.
/obj/machinery/nuclearbomb/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	if(extended)
		if(!ishuman(user))
			to_chat(user, span_warning("You don't have the dexterity to do this!"))
			return TRUE
		user.set_machine(src)
		wire_view = FALSE
		tgui_interact(user)
	else if(deployable)
		if(removal_stage < 5)
			set_anchored(TRUE)
			visible_message(span_warning("With a steely snap, bolts slide out of [src] and anchor it to the flooring!"))
		else
			visible_message(span_warning("\The [src] makes a highly unpleasant crunching noise. It looks like the anchoring bolts have been cut."))
		if(!lighthack)
			flick("nuclearbombc", src)
			icon_state = "nuclearbomb1"
		extended = 1
	return TRUE

CAPABILITIES(/obj/machinery/nuclearbomb)
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition))
	interface("NuclearBomb", title = "Nuclear Fission Explosive")
	op("auth", ui_act("auth"), then(PROC_REF(ui_act_auth)))
	op("type", ui_act("type", arg("key", schema_text(4096))), then(PROC_REF(ui_act_type)))
	op("time", ui_act("time", arg("delta", num())), then(PROC_REF(ui_act_time)))
	op("timer", ui_act("timer"), then(PROC_REF(ui_act_timer)))
	op("safety", ui_act("safety"), then(PROC_REF(ui_act_safety)))
	op("anchor", ui_act("anchor"), then(PROC_REF(ui_act_anchor)))
	op("wire", ui_act("wire", arg("wire", schema_text(4096))), then(PROC_REF(ui_act_wire)))
	op("pulse", ui_act("pulse", arg("wire", schema_text(4096))), then(PROC_REF(ui_act_pulse)))
	extend(TAG_UI, needs(req(PROC_REF(bomb_reachable), because = MSG(nuclearbomb/unreachable))))
	extend(TAG_UI, then(PROC_REF(ui_fingerprint), early = TRUE))
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(crowbar_used)))
	op("use_welder", tool(TOOL_WELDER), priority(OP_PRIORITY_DEFAULT), wait(0), costs(RES_FUEL, 0), then(PROC_REF(welder_used)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("insert_disk", item(/obj/item/disk/nuclear), priority(OP_PRIORITY_DEFAULT - 1), label("Insert authentication disk"), when(req(PROC_REF(is_extended_holds))), then(PROC_REF(interaction_insert_disk)))
	op("use", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_use)))
	op("make_deployable", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Make Deployable"), needs(req_adjacent(), req_capable(), req(PROC_REF(dq_actor_can_act_holds), because = PROC_REF(dq_actor_can_act_refusal)), req(PROC_REF(can_make_deployable_holds), because = PROC_REF(can_make_deployable_refusal))), then(PROC_REF(interaction_make_deployable)))
	op("use_wire_tools", any_of_tools(TOOL_WIRECUTTER, TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), label("Wires"), then(PROC_REF(wire_tool_used)))

MSG_DEF_SELF(nuclearbomb/unreachable, "You can't work the bomb's panel.")

/// The panel answers someone who can move and act and stands next to the bomb (an AI works it from anywhere).
/obj/machinery/nuclearbomb/proc/bomb_reachable(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.canmove || user.stat || user.restrained()) // ALLOW(reads): the person is read when a button is pressed, never from a cached menu
		return FALSE
	return get_dist(src, user) <= 1 || isAI(user)

/// Whoever presses a button leaves their prints on the bomb.
/obj/machinery/nuclearbomb/proc/ui_fingerprint(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

/obj/machinery/nuclearbomb/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["wire_view"] = !!wire_view
	data["lighthack"] = !!lighthack
	var/list/wires_out = list()
	for(var/wire in wires_list)
		wires_out += list(list(
			"name" = wire,
			"cut" = !!LAZYACCESS(wires_list, wire),
		))
	data["wires"] = wires_out
	data["auth"] = !!auth()
	data["yes_code"] = !!yes_code
	data["timing"] = !!timing
	data["safety"] = !!safety
	data["anchored"] = !!anchored
	var/safe_label = safety ? "Safe" : "Engaged"
	var/status
	if(auth())
		if(yes_code)
			status = "[timing ? "Func/Set" : "Functional"]-[safe_label]"
		else
			status = "Auth. S2-[safe_label]"
	else if(timing)
		status = "Set-[safe_label]"
	else
		status = "Auth. S1-[safe_label]"
	data["status_label"] = status
	var/display
	if(!auth())
		display = "AUTH"
	else if(yes_code)
		display = "*****"
	else
		display = code || ""
	data["code_display"] = display
	data["timeleft"] = timeleft
	return data


/obj/machinery/nuclearbomb/proc/ui_act_auth(datum/act/op/A)
	var/mob/user = A.actor
	if(auth())
		auth().forceMove(src.loc)
		yes_code = 0
		rel_clear(src, nameof(/obj/machinery/nuclearbomb::auth))
	else
		var/obj/item/I = user.get_active_hand()
		if(istype(I, /obj/item/disk/nuclear))
			insert_auth_disk(user, I)
	return TRUE

/obj/machinery/nuclearbomb/proc/ui_act_type(datum/act/op/A, raw_key)
	if(!auth())
		return TRUE
	var/key = raw_key
	if(key == "E")
		if(code == r_code)
			yes_code = 1
			code = null
		else
			code = "ERROR"
	else if(key == "R")
		yes_code = 0
		code = null
	else
		code = "[code][key]"
		if(length(code) > 5)
			code = "ERROR"
	return TRUE

/obj/machinery/nuclearbomb/proc/ui_act_time(datum/act/op/A, raw_delta)
	if(!auth() || !yes_code)
		return TRUE
	var/delta = raw_delta
	timeleft += delta
	timeleft = min(max(round(timeleft), 60), 600)
	return TRUE

/obj/machinery/nuclearbomb/proc/ui_act_timer(datum/act/op/A)
	var/mob/user = A.actor
	if(!auth() || !yes_code || timing == -1.0)
		return TRUE
	if(safety)
		to_chat(user, span_warning("The safety is still on."))
		return TRUE
	timing = !timing
	if(timing)
		if(!lighthack)
			icon_state = "nuclearbomb2"
		if(!safety)
			GLOB.bomb_set = 1
			set_security_level("delta")
		else
			GLOB.bomb_set = 0
			set_security_level("red")
	else
		GLOB.bomb_set = 0
		set_security_level("red")
		if(!lighthack)
			icon_state = "nuclearbomb1"
	return TRUE

/obj/machinery/nuclearbomb/proc/ui_act_safety(datum/act/op/A)
	if(!auth() || !yes_code)
		return TRUE
	safety = !safety
	if(safety)
		timing = 0
		GLOB.bomb_set = 0
		set_security_level("red")
	return TRUE

/obj/machinery/nuclearbomb/proc/ui_act_anchor(datum/act/op/A)
	if(!auth() || !yes_code)
		return TRUE
	if(removal_stage == 5)
		set_anchored(FALSE)
		visible_message(span_warning("\The [src] makes a highly unpleasant crunching noise. It looks like the anchoring bolts have been cut."))
		return TRUE
	set_anchored(!anchored)
	if(anchored)
		visible_message(span_warning("With a steely snap, bolts slide out of [src] and anchor it to the flooring."))
	else
		visible_message(span_warning("The anchoring bolts slide back into the depths of [src]."))
	return TRUE

/obj/machinery/nuclearbomb/proc/ui_act_wire(datum/act/op/A, raw_wire)
	var/mob/user = A.actor
	var/wire = raw_wire
	if(!(wire in wires_list))
		return TRUE
	var/obj/item/I = user.get_active_hand()
	if(!I?.has_tool_quality(TOOL_WIRECUTTER))
		to_chat(user, "You need wirecutters!")
		return TRUE
	LAZYSET(wires_list, wire, !LAZYACCESS(wires_list, wire))
	if(safety_wire == wire && timing)
		explode()
	if(timing_wire == wire)
		if(!lighthack && icon_state == "nuclearbomb2")
			icon_state = "nuclearbomb1"
		timing = 0
		GLOB.bomb_set = 0
		set_security_level("red")
	if(light_wire == wire)
		lighthack = !lighthack
	return TRUE

/obj/machinery/nuclearbomb/proc/ui_act_pulse(datum/act/op/A, raw_wire)
	var/mob/user = A.actor
	var/wire = raw_wire
	if(!(wire in wires_list))
		return TRUE
	var/obj/item/hand_item = user.get_active_hand()
	if(!hand_item?.has_tool_quality(TOOL_MULTITOOL))
		to_chat(user, "You need a multitool!")
		return TRUE
	if(LAZYACCESS(wires_list, wire))
		to_chat(user, "You can't pulse a cut wire.")
		return TRUE
	if(light_wire == wire)
		toggle_lighthack()
		after(src, 10 SECONDS, PROC_REF(toggle_lighthack))
	if(timing_wire == wire && timing)
		explode()
	if(safety_wire == wire)
		toggle_safety()
		after(src, 10 SECONDS, PROC_REF(toggle_safety))
		if(safety == 1)
			visible_message(span_notice("The [src] quiets down."))
			if(!lighthack && icon_state == "nuclearbomb2")
				icon_state = "nuclearbomb1"
		else
			visible_message(span_notice("The [src] emits a quiet whirling noise!"))
	return TRUE

/obj/machinery/nuclearbomb/proc/nukehack_win(mob/user as mob)
	// wire-defusion view of the same TGUI window. Setting wire_view
	// before re-opening swaps the React-side view.
	wire_view = TRUE
	tgui_interact(user)

/// Requirement: only something with hands can adjust the panels.
/obj/machinery/nuclearbomb/proc/can_make_deployable(mob/user, atom/target, obj/item/held)
	if(!user.canmove || user.stat || user.restrained()) // ALLOW(reads): the legacy check is read when the op is tried, never from a cached menu
		return TRUE // the effect declines silently
	if(!ishuman(user))
		return "you don't have the dexterity to do this"
	return TRUE

/// Requirement (was REQ_* dq_actor_can_act): the legacy check answers TRUE to pass.
/obj/machinery/nuclearbomb/proc/dq_actor_can_act_holds(datum/act/op/A)
	var/answer = dq_actor_can_act(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why dq_actor_can_act_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/nuclearbomb/proc/dq_actor_can_act_refusal(datum/act/op/A)
	var/answer = dq_actor_can_act(A.actor, src, A.held)
	return istext(answer) ? answer : "you can't do that right now"

/// Requirement (was REQ_* can_make_deployable): the legacy check answers TRUE to pass.
/obj/machinery/nuclearbomb/proc/can_make_deployable_holds(datum/act/op/A)
	var/answer = can_make_deployable(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_make_deployable_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/nuclearbomb/proc/can_make_deployable_refusal(datum/act/op/A)
	var/answer = can_make_deployable(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/machinery/nuclearbomb/proc/interaction_make_deployable(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.canmove || user.stat || user.restrained())
		return TRUE
	if(deployable)
		to_chat(user, span_warning("You close several panels to make [src] undeployable."))
		deployable = 0
	else
		to_chat(user, span_warning("You adjust some panels to make [src] deployable."))
		deployable = 1
	return TRUE

#define NUKERANGE 80
/obj/machinery/nuclearbomb/proc/explode()
	if(safety)
		timing = 0
		return
	timing = -1.0
	yes_code = 0
	safety = 1
	if(!lighthack)
		icon_state = "nuclearbomb3"
	world << sound('sound/machines/Alarm.ogg') // The nuclear alarm is audible world-wide.
	if(SSticker && SSticker.mode)
		SSticker.mode.explosion_in_progress = 1
	after(src, 10 SECONDS, PROC_REF(detonate))

/// Ten seconds after the alarm: the blast, the cinematic and the round outcome.
/obj/machinery/nuclearbomb/proc/detonate()

	var/off_station = 0
	var/turf/bomb_location = get_turf(src)
	if(bomb_location && (bomb_location.z in using_map.station_levels))
		if((bomb_location.x < (128-NUKERANGE)) || (bomb_location.x > (128+NUKERANGE)) || (bomb_location.y < (128-NUKERANGE)) || (bomb_location.y > (128+NUKERANGE)))
			off_station = 1
	else
		off_station = 2

	if(SSticker)
		if(SSticker.mode && SSticker.mode.name == "Mercenary")
			var/obj/machinery/computer/shuttle_control/multi/syndicate/syndie_location = locate(/obj/machinery/computer/shuttle_control/multi/syndicate)
			if(syndie_location)
				SSticker.mode:syndies_didnt_escape = (syndie_location.z > 1 ? 0 : 1)	//muskets will make me change this, but it will do for now
			SSticker.mode:nuke_off_station = off_station

		var/datum/cinematic/cinematic_type
		switch(off_station)
			if(0)
				cinematic_type = SSticker.mode.name == "mercenary" ? /datum/cinematic/nuke/ops_victory : /datum/cinematic/nuke/self_destruct
			if(1)
				cinematic_type = SSticker.mode.name == "mercenary" ? /datum/cinematic/nuke/ops_miss : /datum/cinematic/nuke/self_destruct_miss
			if(2)
				cinematic_type = /datum/cinematic/nuke/far_explosion
		play_cinematic(cinematic_type)
		// The rest happens at the blast, once the intro has played (it slept through it before S10b).
		after(null, initial(cinematic_type.intro_time), GLOBAL_PROC_REF(nuke_blast_aftermath), with = list(off_station, SSticker.mode.name == "mercenary"))

/// A nuke's blast, after its cinematic's intro: kills the station for a self-destruct hit,
/// then settles the round.
/proc/nuke_blast_aftermath(off_station, mercenary)
	if(off_station == 0 && !mercenary)
		// FIXME: Probably a better way
		for(var/mob/living/M in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS))
			switch(M.z)
				if(0)	//inside a crate or something
					var/turf/T = get_turf(M)
					if(T && (T.z in using_map.station_levels))				//we don't use M.death(0) because it calls a for(/mob) loop and
						M.set_stat(DEAD)
				if(1)	//on a z-level 1 turf.
					M.set_stat(DEAD)

	if(SSticker?.mode)
		SSticker.mode.explosion_in_progress = 0
		to_chat(world, span_boldannounce("The station was destoyed by the nuclear blast!"))

		SSticker.mode.station_was_nuked = (off_station<2)	//offstation==1 is a draw. the station becomes irradiated and needs to be evacuated.
														//kinda shit but I couldn't  get permission to do what I wanted to do.

		if(!SSticker.mode.check_finished())//If the mode does not deal with the nuke going off so just reboot because everyone is stuck as is
			to_chat(world, span_boldannounce("Resetting in 30 seconds!"))

			feedback_set_details("end_error","nuke - unhandled ending")

			if(GLOB.blackbox)
				GLOB.blackbox.save_all_data_to_sql()
			after(null, 30 SECONDS, /proc/nuke_reboot)

/proc/nuke_reboot()
	log_game("Rebooting due to nuclear detonation")
	world.Reboot()

#undef NUKERANGE

REGISTRY_MEMBERSHIP(/obj/item/disk/nuclear, REGISTRY_NUKE_DISKS)

// the last disk respawns at a blob start.
/obj/item/disk/nuclear/on_destroy(force)
	if(!REGISTRY_COUNT(REGISTRY_NUKE_DISKS) && GLOB.blobstart.len > 0)
		var/obj/D = new /obj/item/disk/nuclear(pick(GLOB.blobstart))
		message_admins("[src], the last authentication disk, has been destroyed. Spawning [D] at ([D.x], [D.y], [D.z]).")
		log_game("[src], the last authentication disk, has been destroyed. Spawning [D] at ([D.x], [D.y], [D.z]).")
	..()

/obj/item/disk/nuclear/touch_map_edge()
	spent(src)

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/nuclearbomb/step_start_condition()
	return timing

/obj/machinery/nuclearbomb/proc/toggle_lighthack()
	lighthack = !lighthack

/obj/machinery/nuclearbomb/proc/toggle_safety()
	safety = !safety

/// auth (a relation view: it reads null once the target is deleted).
/obj/machinery/nuclearbomb/proc/auth() as /obj/item/disk/nuclear
	return auth
