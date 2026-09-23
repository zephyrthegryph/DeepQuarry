/obj/machinery/power/emitter
	material_template = /datum/material_template/energy_device
	material_total = 10 * SHEET_MATERIAL_AMOUNT
	name = "emitter"
	desc = "It is a heavy duty industrial laser."
	icon = 'icons/obj/singularity.dmi'
	icon_state = "emitter"
	anchored = FALSE
	density = TRUE
	unacidable = TRUE
	req_access = list(ACCESS_ENGINE_EQUIP)
	var/id = null

	use_power = USE_POWER_OFF	//uses powernet power, not APC power
	active_power_usage = 30000	//30 kW laser. I guess that means 30 kJ per shot.

	var/active = 0
	var/powered = 0
	var/fire_delay = 100
	var/max_burst_delay = 100
	var/min_burst_delay = 20
	var/burst_shots = 3
	var/last_shot = 0
	var/shot_number = 0
	var/state = 0
	var/locked = 0

	// Anomaly harvesting stuff
	var/anomalous = FALSE
	var/particle = ANOMALY_PARTICLE_SIGMA

	var/burst_delay = 2
	var/initial_fire_delay = 100

	max_integrity = 80

/obj/machinery/power/emitter/Destroy()
	message_admins("Emitter deleted at ([x],[y],[z] - <A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)")
	log_game("EMITTER([x],[y],[z]) Destroyed/deleted.")
	investigate_log(span_red("deleted") + " at ([x],[y],[z])","singulo")
	. = ..()

/obj/machinery/power/emitter/attack_hand(mob/user as mob)
	src.add_fingerprint(user)
	activate(user)

/obj/machinery/power/emitter/proc/activate(mob/user as mob)
	if(state == 2)
		if(!powernet)
			to_chat(user, "\The [src] isn't connected to a wire.")
			return 1
		if(!src.locked)
			if(src.active==1)
				src.active = 0
				STOP_MACHINE_PROCESSING(src)
				balloon_alert_visible("turned off")
				message_admins("Emitter turned off by [key_name(user, user.client)](<A href='byond://?_src_=holder;[HrefToken()];adminmoreinfo=\ref[user]'>?</A>) in ([x],[y],[z] - <A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)",0,1)
				log_game("EMITTER([x],[y],[z]) OFF by [key_name(user)]")
				investigate_log("turned " + span_red("off") + " by [user.key]","singulo")
			else
				src.active = 1
				material_last_charge = world.time
				START_MACHINE_PROCESSING(src)
				balloon_alert_visible("turned on")
				src.shot_number = 0
				src.fire_delay = get_initial_fire_delay()
				message_admins("Emitter turned on by [key_name(user, user.client)](<A href='byond://?_src_=holder;[HrefToken()];adminmoreinfo=\ref[user]'>?</A>) in ([x],[y],[z] - <A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)")
				log_game("EMITTER([x],[y],[z]) ON by [key_name(user)]")
				investigate_log("turned " + span_green("on") + " by [user.key]","singulo")
			update_icon()
		else
			to_chat(user, span_warning("The controls are locked!"))
	else
		to_chat(user, span_warning("\The [src] needs to be firmly secured to the floor first."))
		return 1

/obj/machinery/power/emitter/process()
	if(stat & (BROKEN))
		return PROCESS_KILL
	if(src.state != 2 || (!powernet && active_power_usage))
		src.active = 0
		update_icon()
		return PROCESS_KILL
	if(!active)
		return PROCESS_KILL
	charge_emitter()
	if(((src.last_shot + src.fire_delay) <= world.time) && (src.active == 1))
		var/burst_time = (min_burst_delay + max_burst_delay)/2 + 2*(burst_shots-1)
		var/desired_beam = active_power_usage * (burst_time / 10) / burst_shots * material_output_setting
		var/efficiency = emitter_efficiency()
		var/required_energy = desired_beam / efficiency
		if(material_stored_energy >= required_energy)
			if(!powered)
				powered = 1
				update_icon()
				log_game("EMITTER([x],[y],[z]) Regained power and is ON.")
				investigate_log("regained power and turned " + span_green("on"),"singulo")
		else
			if(powered)
				powered = 0
				update_icon()
				log_game("EMITTER([x],[y],[z]) Lost power and was ON.")
				investigate_log("lost power and turned" + span_red("off"),"singulo")
			return

		src.last_shot = world.time
		if(src.shot_number < burst_shots)
			src.fire_delay = get_burst_delay() //R-UST port
			src.shot_number ++
		else
			src.fire_delay = get_rand_burst_delay() //R-UST port
			src.shot_number = 0

		fire_delay = max(1, round(fire_delay / material_cadence_setting))
		material_stored_energy -= required_energy
		material_beam_joules += desired_beam
		material_service.output_joules += desired_beam
		material_service.loss_joules += required_energy - desired_beam
		material_service.last_output_watts = desired_beam / max(fire_delay / 10, 0.1)
		material_service.last_work_time = world.time
		material_service.add_heat(required_energy - desired_beam)

		playsound(src, 'sound/weapons/emitter.ogg', 25, 1)
		if(prob(35))
			var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
			s.set_up(5, 1, src)
			s.start()

		var/obj/item/projectile/beam/emitter/A = get_emitter_beam()
		A.damage = round(desired_beam/EMITTER_DAMAGE_POWER_TRANSFER)
		A.firer = src
		A.fire(dir2angle(dir))

/obj/machinery/power/emitter/proc/construction_tool_act(mob/user, obj/item/W, tool_quality)

	if(tool_quality == TOOL_WRENCH)
		if(active)
			to_chat(user, "Turn off [src] first.")
			return
		switch(state)
			if(0)
				state = 1
				playsound(src, W.usesound, 75, 1)
				user.visible_message("[user.name] secures [src] to the floor.", \
					"You secure the external reinforcing bolts to the floor.", \
					"You hear a ratchet.")
				src.anchored = TRUE
			if(1)
				state = 0
				playsound(src, W.usesound, 75, 1)
				user.visible_message("[user.name] unsecures [src] reinforcing bolts from the floor.", \
					"You undo the external reinforcing bolts.", \
					"You hear a ratchet.")
				src.anchored = FALSE
				disconnect_from_network()
			if(2)
				to_chat(user, span_warning("\The [src] needs to be unwelded from the floor."))
		update_icon()
		return

	if(tool_quality == TOOL_WELDER)
		if(active)
			to_chat(user, "Turn off [src] first.")
			return
		switch(state)
			if(0)
				to_chat(user, span_warning("\The [src] needs to be wrenched to the floor."))
			if(1)
				if(use_tool(user, W, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50, \
						message_self = "You start to weld [src] to the floor.", message_others = "[user.name] starts to weld [src] to the floor."))
					if(!src)
						return
					state = 2
					to_chat(user, "You weld [src] to the floor.")
					connect_to_network()
			if(2)
				if(use_tool(user, W, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50, \
						message_self = "You start to cut [src] free from the floor.", message_others = "[user.name] starts to cut [src] free from the floor."))
					if(!src)
						return
					state = 1
					to_chat(user, "You cut [src] free from the floor.")
					disconnect_from_network()
		update_icon()
		return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/emitter/attackby(obj/item/W, mob/user)
	if(istype(W, /obj/item/stack/material) && W.get_material_name() == MAT_STEEL)
		var/amt = CEILING((max_integrity - get_integrity()) / 10, 1)
		if(!amt)
			to_chat(user, span_notice("\The [src] is already fully repaired."))
			return
		var/obj/item/stack/P = W
		if(!P.can_use(amt))
			to_chat(user, span_warning("You don't have enough sheets to repair this! You need at least [amt] sheets."))
			return
		to_chat(user, span_notice("You begin repairing \the [src]..."))
		if(do_after(user, 3 SECONDS, target = src))
			if(P.use(amt))
				to_chat(user, span_notice("You have repaired \the [src]."))
				repair_damage(max_integrity)
				return
			else
				to_chat(user, span_warning("You don't have enough sheets to repair this! You need at least [amt] sheets."))
				return

	if(istype(W, /obj/item/card/id) || istype(W, /obj/item/pda))
		if(emagged)
			to_chat(user, span_warning("The lock seems to be broken."))
			return
		if(src.allowed(user))
			src.locked = !src.locked
			to_chat(user, "The controls are now [src.locked ? "locked." : "unlocked."]")
			update_icon()
		else
			to_chat(user, span_warning("Access denied."))
		return
	if(istype(W, /obj/item/anomaly_scanner))
		anomalous = !anomalous
		burst_delay = anomalous ? 3 : 8
		to_chat(user, span_notice("The beam is now set to [anomalous ? "anomalous." : "normal."]"))
		if(anomalous)
			description_info = "Use a multitool to change the particle type."
		else
			description_info = initial(description_info)
		return
	..()
	return

/obj/machinery/power/emitter/wrench_act(mob/user, obj/item/W)
	return construction_tool_act(user, W, TOOL_WRENCH)

/obj/machinery/power/emitter/welder_act(mob/user, obj/item/W)
	return construction_tool_act(user, W, TOOL_WELDER)

/obj/machinery/power/emitter/multitool_act(mob/user, obj/item/W)
	if(!anomalous)
		return ITEM_INTERACT_BLOCKING
	var/chosen_particle = tgui_input_list(user, "Select particle type", "Particle Selection", ANOMALY_PARTICLE_ALL)
	if(!chosen_particle)
		return ITEM_INTERACT_BLOCKING
	particle = chosen_particle
	balloon_alert_visible("changed to [chosen_particle]")
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/emitter/emag_act(remaining_charges, mob/user)
	if(!emagged)
		locked = 0
		emagged = 1
		user.visible_message("[user.name] emags [src].",span_warning("You short out the lock."))
		return 1

/obj/machinery/power/emitter/atom_destruction(damage_flag)
	if(powernet && avail(active_power_usage))
		visible_message(src, span_danger("\The [src] explodes violently!"), span_danger("You hear an explosion!"))
		explosion(get_turf(src), 1, 2, 4)
	else
		visible_message(span_danger("\The [src] crumples apart!"), span_warning("You hear metal collapsing."))
	return ..()

/obj/machinery/power/emitter/examine(mob/user)
	. = ..()
	switch(state)
		if(0)
			. += span_warning("It is not secured in place!")
		if(1)
			. += span_warning("It has been bolted down securely, but not welded into place.")
		if(2)
			. += span_notice("It has been bolted down securely and welded down into place.")
	var/integrity_percentage = round((get_integrity() / max_integrity) * 100)
	switch(integrity_percentage)
		if(0 to 30)
			. += span_danger("It is close to falling apart!")
		if(31 to 70)
			. += span_danger("It is damaged.")
		if(77 to 99)
			. += span_warning("It is slightly damaged.")

//R-UST port
/obj/machinery/power/emitter/proc/get_initial_fire_delay()
	return initial_fire_delay

/obj/machinery/power/emitter/proc/get_rand_burst_delay()
	return rand(min_burst_delay, max_burst_delay)

/obj/machinery/power/emitter/proc/get_burst_delay()
	return burst_delay

/obj/machinery/power/emitter/proc/get_emitter_beam()
	if(anomalous)
		var/obj/item/projectile/energy/anomaly/projectile = new /obj/item/projectile/energy/anomaly(get_turf(src))
		projectile.particle_type = particle
		return projectile
	return new /obj/item/projectile/beam/emitter(get_turf(src))

/obj/machinery/power/emitter/pre_mapped
	anchored = TRUE
	state = 2

/obj/machinery/power/emitter/pre_mapped/Initialize(mapload)
	. = ..()
	connect_to_network()
	update_icon()


/obj/machinery/power/emitter
	icon = 'icons/obj/singularity_vr.dmi' // New emitter sprite
	icon_state = "emitter0"
	var/previous_state = 0

/obj/machinery/power/emitter/Initialize(mapload)
	. = ..()
	previous_state = state
	if(state == 2 && anchored)
		connect_to_network()
	AddElement(/datum/element/climbable)
	AddElement(/datum/element/rotatable)
	AddElement(/datum/element/empprotection, EMP_PROTECT_SELF)

/obj/machinery/power/emitter/update_icon()
	cut_overlays()
	icon_state = "emitter[state]"
	if (state != previous_state)
		flick("emitterflick-[previous_state][state]",src)
		previous_state = state

	if(powered && powernet && avail(active_power_usage) && active)
		var/image/emitterbeam = image(icon,"emitter-beam")
		emitterbeam.plane = PLANE_LIGHTING_ABOVE
		add_overlay(emitterbeam)

	if(locked)
		var/image/emitterlock = image(icon,"emitter-lock")
		emitterlock.plane = PLANE_LIGHTING_ABOVE
		add_overlay(emitterlock)

// The old emitter sprite
/obj/machinery/power/emitter/antique
	name = "antique emitter"
	desc = "An old fashioned heavy duty industrial laser."
	icon_state = "emitter"

/obj/machinery/power/emitter/antique/update_icon()
	if(powered && powernet && avail(active_power_usage) && active)
		icon_state = "emitter_+a"
	else
		icon_state = "emitter"

/obj/machinery/power/emitter/antique/pre_mapped
	anchored = TRUE
	state = 2

/obj/machinery/power/emitter/antique/pre_mapped/Initialize(mapload)
	. = ..()
	connect_to_network()
	update_icon()
