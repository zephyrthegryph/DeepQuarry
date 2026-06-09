GLOBAL_VAR(bomb_set)

/obj/machinery/nuclearbomb
	name = "\improper Nuclear Fission Explosive"
	desc = "Uh oh. RUN!!!!"
	icon = 'icons/obj/stationobjs.dmi' //chompedit, use the better one
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
	var/obj/item/disk/nuclear/auth = null
	var/list/wires_list = list()
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

/obj/machinery/nuclearbomb/Initialize(mapload)
	. = ..()
	r_code = "[rand(10000, 99999.0)]"//Creates a random code upon object spawn.
	wires_list["Red"] = 0
	wires_list["Blue"] = 0
	wires_list["Green"] = 0
	wires_list["Marigold"] = 0
	wires_list["Fuschia"] = 0
	wires_list["Black"] = 0
	wires_list["Pearl"] = 0
	var/list/w = list("Red","Blue","Green","Marigold","Black","Fuschia","Pearl")
	light_wire = pick(w)
	w -= light_wire
	timing_wire = pick(w)
	w -= timing_wire
	safety_wire = pick(w)
	w -= safety_wire

/obj/machinery/nuclearbomb/process()
	if(timing)
		GLOB.bomb_set = 1 //So long as there is one nuke timing, it means one nuke is armed.
		timeleft--
		playsound(src, 'sound/items/timer.ogg',50) //chompedit... beep :)
		if(timeleft <= 0)
			explode()
		for(var/mob/M in viewers(1, src))
			if((M.client && M.check_current_machine(src)))
				attack_hand(M)
	return ..()

/obj/machinery/nuclearbomb/attackby(obj/item/O as obj, mob/user as mob)
	if(O.has_tool_quality(TOOL_SCREWDRIVER))
		playsound(src, O.usesound, 50, 1)
		add_fingerprint(user)
		if(auth)
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

		return
	if(O.has_tool_quality(TOOL_WIRECUTTER) || istype(O, /obj/item/multitool))
		if(opened == 1)
			nukehack_win(user)
		return

	if(extended)
		if(istype(O, /obj/item/disk/nuclear))
			user.drop_item()
			O.loc = src
			auth = O
			add_fingerprint(user)
			return

	if(anchored)
		switch(removal_stage)
			if(0)
				if(O.has_tool_quality(TOOL_WELDER))

					var/obj/item/weldingtool/WT = O.get_welder()
					if(!WT.isOn()) return
					if(WT.get_fuel() < 5) // uses up 5 fuel.
						to_chat(user, span_warning("You need more fuel to complete this task."))
						return

					user.visible_message("[user] starts cutting loose the anchoring bolt covers on [src].", "You start cutting loose the anchoring bolt covers with [O]...")

					if(do_after(user, 4 SECONDS * WT.toolspeed, target = src))
						if(!src || !user || !WT.remove_fuel(5, user)) return
						user.visible_message("[user] cuts through the bolt covers on [src].", "You cut through the bolt cover.")
						removal_stage = 1
				return

			if(1)
				if(O.has_tool_quality(TOOL_CROWBAR))
					user.visible_message("[user] starts forcing open the bolt covers on [src].", "You start forcing open the anchoring bolt covers with [O]...")

					playsound(src, O.usesound, 50, 1)
					if(do_after(user,15 * O.toolspeed, target = src))
						if(!src || !user) return
						user.visible_message("[user] forces open the bolt covers on [src].", "You force open the bolt covers.")
						removal_stage = 2
				return

			if(2)
				if(O.has_tool_quality(TOOL_WELDER))

					var/obj/item/weldingtool/WT = O.get_welder()
					if(!WT.isOn()) return
					if(WT.get_fuel() < 5) // uses up 5 fuel.
						to_chat(user, span_warning("You need more fuel to complete this task."))
						return

					user.visible_message("[user] starts cutting apart the anchoring system sealant on [src].", "You start cutting apart the anchoring system's sealant with [O]...")
					playsound(src, WT.usesound, 50, 1)
					if(do_after(user, 4 SECONDS * WT.toolspeed, target = src))
						if(!src || !user || !WT.remove_fuel(5, user)) return
						user.visible_message("[user] cuts apart the anchoring system sealant on [src].", "You cut apart the anchoring system's sealant.")
						removal_stage = 3
				return

			if(3)
				if(O.has_tool_quality(TOOL_WRENCH))

					user.visible_message("[user] begins unwrenching the anchoring bolts on [src].", "You begin unwrenching the anchoring bolts...")
					playsound(src, O.usesound, 50, 1)
					if(do_after(user, 5 SECONDS * O.toolspeed, target = src))
						if(!src || !user) return
						user.visible_message("[user] unwrenches the anchoring bolts on [src].", "You unwrench the anchoring bolts.")
						removal_stage = 4
				return

			if(4)
				if(O.has_tool_quality(TOOL_CROWBAR))

					user.visible_message("[user] begins lifting [src] off of the anchors.", "You begin lifting the device off the anchors...")
					playsound(src, O.usesound, 50, 1)
					if(do_after(user, 8 SECONDS * O.toolspeed, target = src))
						if(!src || !user) return
						user.visible_message("[user] crowbars [src] off of the anchors. It can now be moved.", "You jam the crowbar under the nuclear device and lift it off its anchors. You can now move it!")
						anchored = FALSE
						removal_stage = 5
				return
	..()

// TGUI migration. attack_hand opens the main control view
// of NuclearBomb.tsx; nukehack_win switches to the wire-defusion view of
// the same window. All keypad/auth/timer/safety/anchor and wire/pulse
// actions are dispatched via tgui_act below.
/obj/machinery/nuclearbomb/attack_hand(mob/user as mob)
	if(extended)
		if(!ishuman(user))
			to_chat(user, span_warning("You don't have the dexterity to do this!"))
			return 1
		user.set_machine(src)
		wire_view = FALSE
		tgui_interact(user)
	else if(deployable)
		if(removal_stage < 5)
			anchored = TRUE
			visible_message(span_warning("With a steely snap, bolts slide out of [src] and anchor it to the flooring!"))
		else
			visible_message(span_warning("\The [src] makes a highly unpleasant crunching noise. It looks like the anchoring bolts have been cut."))
		if(!lighthack)
			flick("nuclearbombc", src)
			icon_state = "nuclearbomb1"
		extended = 1
	return

/obj/machinery/nuclearbomb/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "NuclearBomb", "Nuclear Fission Explosive")
		ui.open()

/obj/machinery/nuclearbomb/tgui_data(mob/user)
	var/list/data = list()
	data["wire_view"] = !!wire_view
	data["lighthack"] = !!lighthack
	var/list/wires_out = list()
	for(var/wire in wires_list)
		wires_out += list(list(
			"name" = wire,
			"cut" = !!wires_list[wire],
		))
	data["wires"] = wires_out
	data["auth"] = !!auth
	data["yes_code"] = !!yes_code
	data["timing"] = !!timing
	data["timeleft"] = timeleft
	data["safety"] = !!safety
	data["anchored"] = !!anchored
	var/safe_label = safety ? "Safe" : "Engaged"
	var/status
	if(auth)
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
	if(!auth)
		display = "AUTH"
	else if(yes_code)
		display = "*****"
	else
		display = code || ""
	data["code_display"] = display
	return data

/obj/machinery/nuclearbomb/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	if(!usr.canmove || usr.stat || usr.restrained())
		return TRUE
	if(get_dist(src, usr) > 1 && !isAI(usr))
		return TRUE
	add_fingerprint(usr)
	switch(action)
		if("auth")
			if(auth)
				auth.loc = src.loc
				yes_code = 0
				auth = null
			else
				var/obj/item/I = usr.get_active_hand()
				if(istype(I, /obj/item/disk/nuclear))
					usr.drop_item()
					I.loc = src
					auth = I
			return TRUE
		if("type")
			if(!auth)
				return TRUE
			var/key = params["key"]
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
		if("time")
			if(!auth || !yes_code)
				return TRUE
			var/delta = text2num(params["delta"])
			timeleft += delta
			timeleft = min(max(round(timeleft), 60), 600)
			return TRUE
		if("timer")
			if(!auth || !yes_code || timing == -1.0)
				return TRUE
			if(safety)
				to_chat(usr, span_warning("The safety is still on."))
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
		if("safety")
			if(!auth || !yes_code)
				return TRUE
			safety = !safety
			if(safety)
				timing = 0
				GLOB.bomb_set = 0
				set_security_level("red")
			return TRUE
		if("anchor")
			if(!auth || !yes_code)
				return TRUE
			if(removal_stage == 5)
				anchored = FALSE
				visible_message(span_warning("\The [src] makes a highly unpleasant crunching noise. It looks like the anchoring bolts have been cut."))
				return TRUE
			anchored = !anchored
			if(anchored)
				visible_message(span_warning("With a steely snap, bolts slide out of [src] and anchor it to the flooring."))
			else
				visible_message(span_warning("The anchoring bolts slide back into the depths of [src]."))
			return TRUE
		if("wire")
			var/wire = params["wire"]
			if(!(wire in wires_list))
				return TRUE
			var/obj/item/I = usr.get_active_hand()
			if(!I?.has_tool_quality(TOOL_WIRECUTTER))
				to_chat(usr, "You need wirecutters!")
				return TRUE
			wires_list[wire] = !wires_list[wire]
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
		if("pulse")
			var/wire = params["wire"]
			if(!(wire in wires_list))
				return TRUE
			if(!istype(usr.get_active_hand(), /obj/item/multitool))
				to_chat(usr, "You need a multitool!")
				return TRUE
			if(wires_list[wire])
				to_chat(usr, "You can't pulse a cut wire.")
				return TRUE
			if(light_wire == wire)
				lighthack = !lighthack
				spawn(100) lighthack = !lighthack
			if(timing_wire == wire && timing)
				explode()
			if(safety_wire == wire)
				safety = !safety
				spawn(100) safety = !safety
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

/obj/machinery/nuclearbomb/verb/make_deployable()
	set category = "Object"
	set name = "Make Deployable"
	set src in oview(1)

	if(!usr.canmove || usr.stat || usr.restrained())
		return
	if(!ishuman(usr))
		to_chat(usr, span_warning("You don't have the dexterity to do this!"))
		return 1

	if(deployable)
		to_chat(usr, span_warning("You close several panels to make [src] undeployable."))
		deployable = 0
	else
		to_chat(usr, span_warning("You adjust some panels to make [src] deployable."))
		deployable = 1
	return

/obj/machinery/nuclearbomb/ex_act(severity)
	return


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
	world << sound('sound/machines/Alarm.ogg')//chompedit, nuke is big event, make it global
	if(SSticker && SSticker.mode)
		SSticker.mode.explosion_in_progress = 1
	sleep(100)

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

		switch(off_station)
			if(0)
				if(SSticker.mode.name == "mercenary")
					play_cinematic(/datum/cinematic/nuke/ops_victory)
				else
					play_cinematic(/datum/cinematic/nuke/self_destruct)

					// FIXME: Probably a better way
					for(var/mob/living/M in GLOB.living_mob_list)
						switch(M.z)
							if(0)	//inside a crate or something
								var/turf/T = get_turf(M)
								if(T && (T.z in using_map.station_levels))				//we don't use M.death(0) because it calls a for(/mob) loop and
									M.health = 0
									M.set_stat(DEAD)
							if(1)	//on a z-level 1 turf.
								M.health = 0
								M.set_stat(DEAD)
			if(1)
				if(SSticker.mode.name == "mercenary")
					play_cinematic(/datum/cinematic/nuke/ops_miss)
				else
					play_cinematic(/datum/cinematic/nuke/self_destruct_miss)
			if(2)
				play_cinematic(/datum/cinematic/nuke/far_explosion)

		if(SSticker.mode)
			SSticker.mode.explosion_in_progress = 0
			to_chat(world, span_boldannounce("The station was destoyed by the nuclear blast!"))

			SSticker.mode.station_was_nuked = (off_station<2)	//offstation==1 is a draw. the station becomes irradiated and needs to be evacuated.
															//kinda shit but I couldn't  get permission to do what I wanted to do.

			if(!SSticker.mode.check_finished())//If the mode does not deal with the nuke going off so just reboot because everyone is stuck as is
				to_chat(world, span_boldannounce("Resetting in 30 seconds!"))

				feedback_set_details("end_error","nuke - unhandled ending")

				if(GLOB.blackbox)
					GLOB.blackbox.save_all_data_to_sql()
				sleep(300)
				log_game("Rebooting due to nuclear detonation")
				world.Reboot()
				return
	return

#undef NUKERANGE

/obj/item/disk/nuclear/Initialize(mapload)
	. = ..()
	GLOB.nuke_disks += src

/obj/item/disk/nuclear/Destroy()
	if(!GLOB.nuke_disks.len && GLOB.blobstart.len > 0)
		var/obj/D = new /obj/item/disk/nuclear(pick(GLOB.blobstart))
		message_admins("[src], the last authentication disk, has been destroyed. Spawning [D] at ([D.x], [D.y], [D.z]).")
		log_game("[src], the last authentication disk, has been destroyed. Spawning [D] at ([D.x], [D.y], [D.z]).")
	. = ..()

/obj/item/disk/nuclear/touch_map_edge()
	qdel(src)
