/turf/simulated/wall
	name = "wall"
	desc = "A huge chunk of metal used to separate rooms."
	icon = 'icons/turf/wall_masks.dmi'
	icon_state = "generic"
	opacity = 1
	density = TRUE
	blocks_air = 1
	thermal_conductivity = WALL_HEAT_TRANSFER_COEFFICIENT
	heat_capacity = 312500 //a little over 5 cm thick , 312500 for 1 m by 2.5 m by 0.25 m plasteel wall

	var/icon/wall_masks = 'icons/turf/wall_masks.dmi'
	var/damage = 0
	var/damage_overlay = 0
	var/global/damage_overlays[16]
	var/active
	var/can_open = 0
	var/datum/material/girder_material
	var/datum/material/material
	var/datum/material/reinf_material
	var/last_state
	var/construction_stage

	// There's basically always going to be wall connections, making this lazy doesn't seem like it'd help much unless you wanted to make it bitflags instead.
	var/list/wall_connections = list("0", "0", "0", "0")
	rad_insulation = RAD_MEDIUM_INSULATION

// Walls always hide the stuff below them.
/turf/simulated/wall/levelupdate()
	for(var/obj/O in src)
		O.hide(1)

/turf/simulated/wall/Initialize(mapload, materialtype, rmaterialtype, girdertype)
	. = ..()
	icon_state = "blank"
	if(!materialtype)
		materialtype = DEFAULT_WALL_MATERIAL
	material = get_material_by_name(materialtype)
	if(!girdertype)
		girdertype = DEFAULT_WALL_MATERIAL
	girder_material = get_material_by_name(girdertype)
	if(!isnull(rmaterialtype))
		reinf_material = get_material_by_name(rmaterialtype)
	update_material()
	START_PROCESSING(SSturfs, src)

/turf/simulated/wall/Destroy()
	STOP_PROCESSING(SSturfs, src)
	return ..()

/turf/simulated/wall/examine_icon()
	return icon(icon=initial(icon), icon_state=initial(icon_state))

/turf/simulated/wall/process()
	// Calling parent will kill processing
	if(!radiate())
		return PROCESS_KILL

/turf/simulated/wall/proc/get_material()
	return material

/turf/simulated/wall/bullet_act(obj/item/projectile/Proj)
	if(istype(Proj,/obj/item/projectile/beam))
		burn(2500)
	else if(istype(Proj,/obj/item/projectile/ion))
		burn(500)

	var/proj_damage = Proj.get_structure_damage()

	//cap the amount of damage, so that things like emitters can't destroy walls in one hit.
	var/damage = min(proj_damage, 100)

	if(Proj.damage_type == BURN && damage > 0)
		if(thermite)
			thermitemelt()

	if(istype(Proj,/obj/item/projectile/beam))
		if(material && material.reflectivity >= 0.5) // Time to reflect lasers.
			var/new_damage = damage * material.reflectivity
			var/outgoing_damage = damage - new_damage
			damage = new_damage
			Proj.damage = outgoing_damage

			visible_message(span_danger("\The [src] reflects \the [Proj]!"))

			// Find a turf near or on the original location to bounce to
			var/new_x = Proj.starting.x + pick(0, 0, 0, -1, 1, -2, 2)
			var/new_y = Proj.starting.y + pick(0, 0, 0, -1, 1, -2, 2)
			//var/turf/curloc = get_turf(src)
			var/turf/curloc = get_step(src, get_dir(src, Proj.starting))

			Proj.penetrating += 1 // Needed for the beam to get out of the wall.

			// redirect the projectile
			Proj.redirect(new_x, new_y, curloc, null)

	take_damage(damage)
	return

/turf/simulated/wall/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	..()
	if(ismob(source))
		return
	var/tforce = 0
	if(isobj(source))
		var/obj/object = source
		var/speed = throwingdatum?.speed || THROWFORCE_SPEED_DIVISOR
		if(isitem(object))
			var/obj/item/our_item = object
			tforce = our_item.throwforce * (speed/THROWFORCE_SPEED_DIVISOR)
		else
			tforce = object.w_class * (speed/THROWFORCE_SPEED_DIVISOR)
	if(tforce < 15)
		return

	take_damage(tforce)

/turf/simulated/wall/proc/clear_plants()
	for(var/obj/effect/overlay/wallrot/WR in src)
		qdel(WR)
	for(var/obj/effect/plant/plant in range(src, 1))
		if(!plant.floor) //shrooms drop to the floor
			plant.floor = 1
			plant.update_icon()
			plant.pixel_x = 0
			plant.pixel_y = 0
		plant.update_neighbors()

/turf/simulated/wall/ChangeTurf(turf/N, tell_universe, force_lighting_update, preserve_outdoors)
	clear_plants()
	. = ..(N, tell_universe, force_lighting_update, preserve_outdoors)

//Appearance
/turf/simulated/wall/examine(mob/user)
	. = ..()

	if(!damage)
		. += span_notice("It looks fully intact.")
	else
		var/dam = damage / material.integrity
		if(dam <= 0.3)
			. += span_warning("It looks slightly damaged.")
		else if(dam <= 0.6)
			. += span_warning("It looks moderately damaged.")
		else
			. += span_danger("It looks heavily damaged.")

	if(locate(/obj/effect/overlay/wallrot) in src)
		. += span_warning("There is fungus growing on [src].")

//Damage

/turf/simulated/wall/melt()

	if(!can_melt())
		return

	src.ChangeTurf(/turf/simulated/floor/plating)

	var/turf/simulated/floor/F = src
	if(!F)
		return
	F.burn_tile()
	F.icon_state = "wall_thermite"
	visible_message(span_danger("\The [src] spontaneously combusts!.")) //!!OH SHIT!!
	return

/turf/simulated/wall/take_damage(dam)
	if(dam)
		damage = max(0, damage + dam)
		update_damage()
	return

/turf/simulated/wall/proc/update_damage()
	var/cap = material.integrity
	if(reinf_material)
		cap += reinf_material.integrity

	if(locate(/obj/effect/overlay/wallrot) in src)
		cap = cap / 10

	if(damage >= cap)
		dismantle_wall()
	else
		update_icon()

	return

/turf/simulated/wall/fire_act(datum/gas_mixture/air, exposed_temperature, exposed_volume)//Doesn't fucking work because walls don't interact with air :(
	burn(exposed_temperature)

/turf/simulated/wall/adjacent_fire_act(turf/simulated/floor/adj_turf, datum/gas_mixture/adj_air, adj_temp, adj_volume)
	burn(adj_temp)
	if(adj_temp > material.melting_point)
		take_damage(log(RAND_F(0.9, 1.1) * (adj_temp - material.melting_point)))

	return ..()

/turf/simulated/wall/proc/dismantle_wall(devastated, explode, no_product)

	playsound(src, 'sound/items/Welder.ogg', 100, 1)
	if(!no_product)
		if(reinf_material)
			reinf_material.place_dismantled_girder(src, reinf_material, girder_material)
		else
			material.place_dismantled_girder(src, null, girder_material)
		if(!devastated)
			if (reinf_material)
				material.place_dismantled_product(src)
			else
				material.place_dismantled_product(src, 2)

	for(var/obj/O in src.contents) //Eject contents!
		if(istype(O,/obj/structure/sign/poster))
			var/obj/structure/sign/poster/P = O
			P.roll_and_drop(src)
		else
			O.loc = src

	clear_plants()
	material = get_material_by_name("placeholder")
	reinf_material = null
	girder_material = null
	update_connections(1)

	ChangeTurf(/turf/simulated/floor/plating)

/turf/simulated/wall/ex_act(severity)
	switch(severity)
		if(1.0)
			if(girder_material.explosion_resistance >= 25 && prob(girder_material.explosion_resistance))
				new /obj/structure/girder/displaced(src, girder_material.name)
			src.ChangeTurf(get_base_turf_by_area(src))
		if(2.0)
			if(prob(75))
				take_damage(rand(150, 250))
			else
				dismantle_wall(1,1)
		if(3.0)
			take_damage(rand(0, 250))
		else
			return

// Wall-rot effect, a nasty fungus that destroys walls.
/turf/simulated/wall/proc/rot()
	if(locate(/obj/effect/overlay/wallrot) in src)
		return FALSE

	// Wall-rot can't go onto walls that are surrounded in all four GLOB.cardinal directions.
	// Because of spores, or something. It's actually to avoid the pain that is removing wallrot surrounded by
	// four r-walls.
	var/at_least_one_open_turf = FALSE
	for(var/direction in GLOB.cardinal)
		var/turf/T = get_step(src, direction)
		if(!T.check_density())
			at_least_one_open_turf = TRUE
			break

	if(!at_least_one_open_turf)
		return FALSE

	var/number_rots = rand(2,3)
	for(var/i=0, i<number_rots, i++)
		new/obj/effect/overlay/wallrot(src)
	return TRUE

/turf/simulated/wall/proc/can_melt()
	if(material.flags & MATERIAL_UNMELTABLE)
		return 0
	return 1

/turf/simulated/wall/proc/thermitemelt(mob/user as mob)
	if(!can_melt())
		return
	var/obj/effect/overlay/O = new/obj/effect/overlay( src )
	O.name = "Thermite"
	O.desc = "Looks hot."
	O.icon = 'icons/effects/fire.dmi'
	O.icon_state = "2"
	O.anchored = TRUE
	O.density = TRUE
	O.plane = ABOVE_PLANE

	if(girder_material.integrity >= 150 && !girder_material.is_brittle()) //Strong girders will remain in place when a wall is melted.
		dismantle_wall(1,1)
	else
		src.ChangeTurf(/turf/simulated/floor/plating)

	var/turf/simulated/floor/F = src
	F.burn_tile()
	F.icon_state = "dmg[rand(1,4)]"
	to_chat(user, span_warning("The thermite starts melting through the wall."))

	spawn(100)
		if(O)
			qdel(O)
//	F.sd_LumReset()		//TODO: ~Carn
	return

/turf/simulated/wall/proc/radiate()
	SIGNAL_HANDLER
	// DQEdit — radioactivity moved to a component on /datum/material.
	var/total_radiation = dq_material_radioactivity(material) + (reinf_material ? dq_material_radioactivity(reinf_material) / 2 : 0) + (girder_material ? dq_material_radioactivity(girder_material) / 2 : 0)
	if(!total_radiation)
		return

	radiation_pulse(
		src,
		max_range = 5,
		threshold = RAD_MEDIUM_INSULATION,
		chance = total_radiation,
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = total_radiation
	)
	return total_radiation

/turf/simulated/wall/proc/burn(temperature)
	if(material.combustion_effect(src, temperature, 0.7))
		spawn(2)
			new /obj/structure/girder(src, girder_material.name)
			src.ChangeTurf(/turf/simulated/floor)
			for(var/turf/simulated/wall/W in range(3,src))
				W.burn((temperature/4))
			for(var/obj/machinery/door/airlock/phoron/D in range(3,src))
				D.ignite(temperature/4)

/turf/simulated/wall/can_engrave()
	return (material && material.hardness >= 10 && material.hardness <= 100)

/* CHOMPEdit - moved this block to modular_chomp\code\game\objects\items\weapons\rcd.dm
/turf/simulated/wall/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(material.integrity > 1000) // Don't decon things like elevatorium.
		return FALSE
	if(reinf_material && !the_rcd.can_remove_rwalls) // Gotta do it the old fashioned way if your RCD can't.
		return FALSE

	if(passed_mode == RCD_DECONSTRUCT)
		var/delay_to_use = material.integrity / 3 // Steel has 150 integrity, so it'll take five seconds to down a regular wall.
		if(reinf_material)
			delay_to_use += reinf_material.integrity / 3
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = delay_to_use,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 5
			)
	return FALSE

/turf/simulated/wall/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		ChangeTurf(/turf/simulated/floor/airless, preserve_outdoors = TRUE)
		return TRUE
	return FALSE
*/

/turf/simulated/wall/occult_act(mob/living/user)
	to_chat(user, span_cult("You consecrate the wall."))
	ChangeTurf(/turf/simulated/wall/cult, preserve_outdoors = TRUE)
	return TRUE

/turf/simulated/wall/click_alt(mob/user)
	if(isliving(user))
		var/mob/living/livingUser = user
		if(try_graffiti(livingUser, livingUser.get_active_hand()))
			return
	. = ..()


// === merged from RCD_chomp.dm during hard-fork de-suffix. Placed in this file because it
// is the highest-positioned definer in the override chain for the members it
// sets, so every override stays after its base definition (resolution preserved). ===
/obj/item/rcd
	allow_concurrent_building = 1
	var/airlock_glass = FALSE // So the floor's rcd_act knows how much ammo to use
	var/advanced_airlock_setting = 1 //Set to 1 if you want more paintjobs available
	var/list/conf_access = null
	var/use_one_access = 0 //If the airlock should require ALL or only ONE of the listed accesses.
	var/girder_type = /obj/structure/girder
	var/frame_type = /obj/structure/frame
	var/wall_frame_type = /obj/machinery/alarm
	var/window_dir = "FULL"
	var/emagged = 0
	window_type = "rglass"
	var/turret_faction = null
	modes = list(RCD_FLOORWALL, RCD_AIRLOCK, RCD_WINDOWGRILLE, RCD_DECONSTRUCT, RCD_WINDOOR, RCD_FIRELOCK, RCD_FRAME, RCD_WALLFRAME, RCD_CONVEYOR, RCD_TURRET)
	var/static/image/radial_image_firelock = image(icon = 'icons/mob/radial.dmi', icon_state = "firelock")
	var/static/image/radial_image_windoor = image(icon= 'icons/mob/radial.dmi', icon_state = "windoor")
	var/static/image/radial_image_frame = image(icon = 'icons/mob/radial.dmi', icon_state = "machine")
	var/static/image/radial_image_wallframe = image(icon = 'icons/mob/radial.dmi', icon_state = "wallframe")
	var/static/image/radial_image_access = image(icon = 'icons/mob/radial.dmi', icon_state = "access")
	var/static/image/radial_image_airlock_type = image(icon = 'icons/mob/radial.dmi', icon_state = "airlocktype")
	var/static/image/radial_image_conveyor = image(icon = 'icons/mob/radial.dmi', icon_state = "conveyor")
	var/static/image/radial_image_turret = image(icon = 'icons/mob/radial.dmi', icon_state = "turret")

/obj/item/rcd/advanced
	can_remove_rwalls = 1
/*
Material values
plasteel = 12
steel = 3.99
tile = 0.99
rod = 1.98
glass = 3.99
rglass = 6
borosilicate = 9
rborosilicate = 12
*/

/obj/item/rcd/emag_act(remaining_charges, mob/user)
	..()
	if(!emagged)
		emagged = 1
		to_chat(user, span_warning("You short out the safeties on \the [src]'s construction limiter"))
		return TRUE

/obj/item/rcd/attackby(obj/item/W, mob/user)
	var/loaded = 0
	if(istype(W, /obj/item/rcd_ammo))
		var/obj/item/rcd_ammo/cartridge = W
		var/can_store = min(max_stored_matter - stored_matter, cartridge.remaining)
		if(can_store <= 0)
			to_chat(user, span_warning("There's either no space or \the [cartridge] is empty!"))
			return FALSE
		stored_matter += can_store
		cartridge.remaining -= can_store
		if(!cartridge.remaining)
			to_chat(user, span_warning("\The [cartridge] dissolves as it empties of compressed matter."))
			user.drop_from_inventory(W)
			qdel(W)
		loaded = 1
	if(istype(W,/obj/item/stack))
		var/obj/item/stack/S = W
		if(istype(S,/obj/item/stack/material/glass/phoronrglass))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*4, user)
		else if(istype(S,/obj/item/stack/material/glass/phoronglass))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*3, user)
		else if(istype(S,/obj/item/stack/material/glass/reinforced))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*2, user)
		else if(istype(S,/obj/item/stack/material/plasteel))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*4, user)
		else if(istype(S,/obj/item/stack/rods))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*0.66, user)
		else if(istype(S,/obj/item/stack/tile/floor))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*0.33, user)
		else if(istype(S,/obj/item/stack/material/steel))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*1.33, user)
		else if(istype(S,/obj/item/stack/material/glass))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*1.33, user)
	if(loaded)
		playsound(src, 'sound/machines/click.ogg', 50, 1)
		update_icon()
		to_chat(user, span_notice("The RCD now holds [stored_matter]/[max_stored_matter] matter-units."))
	return ..()

/obj/item/rcd/proc/loadwithsheets(obj/item/stack/S, value, mob/user)
	var/maxsheets = round((max_stored_matter-stored_matter)/value)    //calculate the max number of sheets that will fit in RCD
	if(maxsheets > 0)
		var/amount_to_use = min(S.amount, maxsheets)
		S.use(amount_to_use)
		stored_matter += value*amount_to_use
		to_chat(user, span_notice("You insert [amount_to_use] [S.name] sheets into [src]. "))
		return 1
	to_chat(user, span_warning("You can't insert any more [S.name] sheets into [src]!"))
	return 0

/obj/item/rcd/attack_self(mob/living/user)
	..()
	var/list/choices = list(
		"Floors & Walls" = radial_image_floorwall,
		"Airlock" = radial_image_airlock,
		"Windoor" = radial_image_windoor,
		"Firelock" = radial_image_firelock,
		"Deconstruct" = radial_image_decon,
		"Grilles & Windows" = radial_image_grillewind,
		"Frames" = radial_image_frame,
		"WallFrames" = radial_image_wallframe,
		"Change Access" = radial_image_access,
		"Change Airlock Type" = radial_image_airlock_type,
		"Conveyors" = radial_image_conveyor
		)
	if(emagged)
		choices["Turrets"] = radial_image_turret
	var/choice = show_radial_menu(user, user, choices, radius = 42, custom_check = CALLBACK(src, PROC_REF(check_menu), user), tooltips = TRUE)
	if(!check_menu(user))
		return
	switch(choice)
		if("Floors & Walls")
			var/list/wall_types = list(
			"DEFAULT" = image(icon = 'icons/mob/radial.dmi', icon_state = "default"),
			"BAY" = image(icon = 'icons/mob/radial.dmi', icon_state = "bay"),
			"ERIS" = image(icon = 'icons/mob/radial.dmi', icon_state = "eris")
			)
			var/selected_girder_type = show_radial_menu(user, src, wall_types, custom_check = CALLBACK(src, PROC_REF(check_menu), user), require_near = TRUE, tooltips = TRUE)
			if(!check_menu(user))
				return
			switch(selected_girder_type)
				if("DEFAULT")
					girder_type = /obj/structure/girder
				if("BAY")
					girder_type = /obj/structure/girder/bay
				if("ERIS")
					girder_type = /obj/structure/girder/eris
			mode_index = modes.Find(RCD_FLOORWALL)
		if("Airlock")
			mode_index = modes.Find(RCD_AIRLOCK)
		if("Windoor")
			mode_index = modes.Find(RCD_WINDOOR)
		if("Firelock")
			mode_index = modes.Find(RCD_FIRELOCK)
		if("Deconstruct")
			mode_index = modes.Find(RCD_DECONSTRUCT)
		if("Grilles & Windows")
			mode_index = modes.Find(RCD_WINDOWGRILLE)
		if("Frames")
			mode_index = modes.Find(RCD_FRAME)
		if("WallFrames")
			var/list/wall_frame_types = list(
			"Air Alarm" = image(icon = 'icons/mob/radial.dmi', icon_state = "wallframe"),
			"Light Bulb" = image(icon = 'icons/mob/radial.dmi', icon_state = "lightbulb"),
			"Light Tube" = image(icon = 'icons/mob/radial.dmi', icon_state = "lighttube"),
			"Doorbell Chime" = image(icon = 'icons/mob/radial.dmi', icon_state = "doorbell"),
			"Doorbell Button" = image(icon = 'icons/mob/radial.dmi', icon_state = "doorbellbutton"),
			"Status Display" = image(icon = 'icons/mob/radial.dmi', icon_state = "status"),
			"Supply Requests Console" = image(icon = 'icons/mob/radial.dmi', icon_state = "supply"),
			"ATM" = image(icon = 'icons/mob/radial.dmi', icon_state = "atm"),
			"Newscaster" = image(icon = 'icons/mob/radial.dmi', icon_state = "newscaster"),
			"Wall Charger" = image(icon = 'icons/mob/radial.dmi', icon_state = "wallcharger"),
			"Fire Alarm" = image(icon = 'icons/mob/radial.dmi', icon_state = "firealarm"),
			"Guest Pass Terminal" = image(icon = 'icons/mob/radial.dmi', icon_state = "guestpass"),
			"Intercom" = image(icon = 'icons/mob/radial.dmi', icon_state = "intercom"),
			"Keycard Authenticator" = image(icon = 'icons/mob/radial.dmi', icon_state = "keycardauth"),
			"Geiger Counter" = image(icon = 'icons/mob/radial.dmi', icon_state = "geiger"),
			"Electrochromic Window Button" = image(icon = 'icons/mob/radial.dmi', icon_state = "windowtint"),
			"ID Restoration Terminal" = image(icon = 'icons/mob/radial.dmi', icon_state = "idrestore"),
			"Timeclock Terminal" = image(icon = 'icons/mob/radial.dmi', icon_state = "timeclock"),
			"Station Map" = image(icon = 'icons/mob/radial.dmi', icon_state = "stationmap"),
			"AI Status Display" = image(icon = 'icons/mob/radial.dmi', icon_state = "status"),
			"Light Switch" = image(icon = 'icons/mob/radial.dmi', icon_state = "lightswitch"),
			"Entertainment Monitor" = image(icon = 'icons/mob/radial.dmi', icon_state = "entertainment")
			)
			var/selected_wall_frame_type = show_radial_menu(user, src, wall_frame_types, custom_check = CALLBACK(src, PROC_REF(check_menu), user), require_near = TRUE, tooltips = TRUE)
			if(!check_menu(user))
				return
			switch(selected_wall_frame_type)
				if("Air Alarm")
					wall_frame_type = /obj/machinery/alarm
				if("Light Bulb")
					wall_frame_type = /obj/machinery/light/small
				if("Light Tube")
					wall_frame_type = /obj/machinery/light
				if("Doorbell Chime")
					wall_frame_type = /obj/machinery/doorbell_chime
				if("Doorbell Button")
					wall_frame_type = /obj/machinery/button/doorbell
				if("Status Display")
					wall_frame_type = /obj/machinery/status_display
				if("Supply Requests Console")
					wall_frame_type = /obj/machinery/requests_console
				if("ATM")
					wall_frame_type = /obj/machinery/atm
				if("Newscaster")
					wall_frame_type = /obj/machinery/newscaster
				if("Wall Charger")
					wall_frame_type = /obj/machinery/recharger/wallcharger
				if("Fire Alarm")
					wall_frame_type = /obj/machinery/firealarm
				if("Guest Pass Terminal")
					wall_frame_type = /obj/machinery/computer/guestpass
				if("Intercom")
					wall_frame_type = /obj/item/radio/intercom
				if("Keycard Authenticator")
					wall_frame_type = /obj/machinery/keycard_auth
				if("Geiger Counter")
					wall_frame_type = /obj/item/geiger/wall
				if("Electrochromic Window Button")
					wall_frame_type = /obj/machinery/button/windowtint
				if("ID Restoration Terminal")
					wall_frame_type = /obj/machinery/computer/id_restorer
				if("Timeclock Terminal")
					wall_frame_type = /obj/machinery/computer/timeclock
				if("Station Map")
					wall_frame_type = /obj/machinery/station_map
				if("AI Status Display")
					wall_frame_type = /obj/machinery/ai_status_display
				if("Light Switch")
					wall_frame_type = /obj/machinery/light_switch
				if("Entertainment Monitor")
					wall_frame_type = /obj/machinery/computer/security/telescreen/entertainment

			mode_index = modes.Find(RCD_WALLFRAME)
		if("Change Access")
			change_airlock_access(user)
			return
		if("Change Airlock Type")
			change_airlock_setting(user)
			return
		if("Conveyors")
			mode_index = modes.Find(RCD_CONVEYOR)
		if("Turrets")
			var/list/turret_factions = list(
			"HOSTILE TO ALL" = image(icon = 'icons/mob/radial.dmi', icon_state = "turret1"),
			"HOSTILE TO ENEMIES" = image(icon = 'icons/mob/radial.dmi', icon_state = "turret2")
			)
			var/selected_turret_faction = show_radial_menu(user, src, turret_factions, custom_check = CALLBACK(src, PROC_REF(check_menu), user), require_near = ranged?FALSE:TRUE, tooltips = TRUE)
			if(!check_menu(user))
				return
			switch(selected_turret_faction)
				if("HOSTILE TO ALL")
					turret_faction = null
				if("HOSTILE TO ENEMIES")
					turret_faction = user.faction
			mode_index = modes.Find(RCD_TURRET)
		else
			return
	playsound(src, 'sound/effects/pop.ogg', 50, FALSE)
	to_chat(user, span_notice("You change RCD's mode to '[choice]'."))

/obj/item/rcd/proc/get_airlock_image(airlock_type)
	var/obj/machinery/door/airlock/proto = airlock_type
	var/ic = initial(proto.icon)
	var/mutable_appearance/MA = mutable_appearance(ic, "door_closed")
	if(!initial(proto.glass))
		MA.overlays += "fill_closed"
	//Not scaling these down to button size because they look horrible then, instead just bumping up radius.
	return MA

/obj/item/rcd/proc/change_airlock_setting(mob/user)
	if(!user)
		return

	var/list/solid_or_glass_choices = list(
		"Solid" = get_airlock_image(/obj/machinery/door/airlock),
		"Glass" = get_airlock_image(/obj/machinery/door/airlock/glass)
	)

	var/list/solid_choices = list(
		"Standard" = get_airlock_image(/obj/machinery/door/airlock),
		"Engineering" = get_airlock_image(/obj/machinery/door/airlock/engineering),
		"Atmospherics" = get_airlock_image(/obj/machinery/door/airlock/atmos),
		"Security" = get_airlock_image(/obj/machinery/door/airlock/security),
		"Command" = get_airlock_image(/obj/machinery/door/airlock/command),
		"Medical" = get_airlock_image(/obj/machinery/door/airlock/medical),
		"Research" = get_airlock_image(/obj/machinery/door/airlock/research),
		"Freezer" = get_airlock_image(/obj/machinery/door/airlock/freezer),
		"Science" = get_airlock_image(/obj/machinery/door/airlock/science),
		"Mining" = get_airlock_image(/obj/machinery/door/airlock/mining),
		"Maintenance" = get_airlock_image(/obj/machinery/door/airlock/maintenance),
		"External" = get_airlock_image(/obj/machinery/door/airlock/external),
		"Airtight Hatch" = get_airlock_image(/obj/machinery/door/airlock/hatch),
		"Maintenance Hatch" = get_airlock_image(/obj/machinery/door/airlock/maintenance_hatch)
	)

	var/list/glass_choices = list(
		"Standard" = get_airlock_image(/obj/machinery/door/airlock/glass),
		"Engineering" = get_airlock_image(/obj/machinery/door/airlock/glass_engineering),
		"Atmospherics" = get_airlock_image(/obj/machinery/door/airlock/glass_atmos),
		"Security" = get_airlock_image(/obj/machinery/door/airlock/glass_security),
		"Command" = get_airlock_image(/obj/machinery/door/airlock/glass_command),
		"Medical" = get_airlock_image(/obj/machinery/door/airlock/glass_medical),
		"Research" = get_airlock_image(/obj/machinery/door/airlock/glass_research),
		"Science" = get_airlock_image(/obj/machinery/door/airlock/glass_science),
		"Mining" = get_airlock_image(/obj/machinery/door/airlock/glass_mining),
		"External" = get_airlock_image(/obj/machinery/door/airlock/glass_external),
	)

	var/airlockcat = show_radial_menu(user, src, solid_or_glass_choices, custom_check = CALLBACK(src, PROC_REF(check_menu), user), require_near = TRUE)
	if(!check_menu(user))
		return
	switch(airlockcat)
		if("Solid")
			if(advanced_airlock_setting == 1)
				var/airlockpaint = show_radial_menu(user, src, solid_choices, radius = 42, custom_check = CALLBACK(src, PROC_REF(check_menu), user), require_near = TRUE)
				if(!check_menu(user))
					return
				switch(airlockpaint)
					if("Standard")
						airlock_type = /obj/machinery/door/airlock
					if("Engineering")
						airlock_type = /obj/machinery/door/airlock/engineering
					if("Atmospherics")
						airlock_type = /obj/machinery/door/airlock/atmos
					if("Security")
						airlock_type = /obj/machinery/door/airlock/security
					if("Command")
						airlock_type = /obj/machinery/door/airlock/command
					if("Medical")
						airlock_type = /obj/machinery/door/airlock/medical
					if("Research")
						airlock_type = /obj/machinery/door/airlock/research
					if("Freezer")
						airlock_type = /obj/machinery/door/airlock/freezer
					if("Science")
						airlock_type = /obj/machinery/door/airlock/science
					if("Mining")
						airlock_type = /obj/machinery/door/airlock/mining
					if("Maintenance")
						airlock_type = /obj/machinery/door/airlock/maintenance
					if("External")
						airlock_type = /obj/machinery/door/airlock/external
					if("Airtight Hatch")
						airlock_type = /obj/machinery/door/airlock/hatch
					if("Maintenance Hatch")
						airlock_type = /obj/machinery/door/airlock/maintenance_hatch
				airlock_glass = FALSE
			else
				airlock_type = /obj/machinery/door/airlock
				airlock_glass = FALSE

		if("Glass")
			if(advanced_airlock_setting == 1)
				var/airlockpaint = show_radial_menu(user, src , glass_choices, radius = 42, custom_check = CALLBACK(src, PROC_REF(check_menu), user), require_near = TRUE)
				if(!check_menu(user))
					return
				switch(airlockpaint)
					if("Standard")
						airlock_type = /obj/machinery/door/airlock/glass
					if("Engineering")
						airlock_type = /obj/machinery/door/airlock/glass_engineering
					if("Atmospherics")
						airlock_type = /obj/machinery/door/airlock/glass_atmos
					if("Security")
						airlock_type = /obj/machinery/door/airlock/glass_security
					if("Command")
						airlock_type = /obj/machinery/door/airlock/glass_command
					if("Medical")
						airlock_type = /obj/machinery/door/airlock/glass_medical
					if("Research")
						airlock_type = /obj/machinery/door/airlock/glass_research
					if("Science")
						airlock_type = /obj/machinery/door/airlock/glass_science
					if("Mining")
						airlock_type = /obj/machinery/door/airlock/glass_mining
					if("External")
						airlock_type = /obj/machinery/door/airlock/glass_external
				airlock_glass = TRUE
			else
				airlock_type = /obj/machinery/door/airlock/glass
				airlock_glass = TRUE
		else
			airlock_type = /obj/machinery/door/airlock
			airlock_glass = FALSE

/obj/item/rcd/proc/change_airlock_access(mob/user)

	if (!ishuman(user) && !istype(user,/mob/living/silicon/robot))
		return

	var/t1 = ""


	if(use_one_access)
		t1 += "Restriction Type: <a href='byond://?src=[REF(src)];access=one'>At least one access required</a><br>"
	else
		t1 += "Restriction Type: <a href='byond://?src=[REF(src)];access=one'>All accesses required</a><br>"

	t1 += "<a href='byond://?src=[REF(src)];access=all'>Remove All</a><br>"

	var/accesses = ""
	accesses += "<div align='center'>" + span_bold("Access") + "</div>"
	accesses += "<table style='width:100%'>"
	accesses += "<tr>"
	for(var/i = 1; i <= 7; i++)
		accesses += "<td style='width:14%'>" + span_bold("[SSaccess.get_region_accesses_name(i)]:") + "</td>"
	accesses += "</tr><tr>"
	for(var/i = 1; i <= 7; i++)
		accesses += "<td style='width:14%' valign='top'>"
		for(var/A in SSaccess.get_region_accesses(i))
			if(A in conf_access)
				accesses += "<a href='byond://?src=[REF(src)];access=[A]'>" + span_red("[replacetext(SSaccess.get_access_desc(A), " ", "&nbsp")]") + "</a> "
			else
				accesses += "<a href='byond://?src=[REF(src)];access=[A]'>[replacetext(SSaccess.get_access_desc(A), " ", "&nbsp")]</a> "
			accesses += "<br>"
		accesses += "</td>"
	accesses += "</tr></table>"
	t1 += "<tt>[accesses]</tt>"

	t1 += "<p><a href='byond://?src=[REF(src)];close=1'>Close</a></p>\n"

	// DQEdit — structured TGUI AdminReport; byond:// links forwarded to host.
	dq_admin_report_html(user, "Access Control", t1, src)

/obj/item/rcd/Topic(href, href_list)
	..()
	if (usr.stat || usr.restrained())
		return
	if (href_list["close"])
		// DQEdit Start — close TGUI window
		SStgui.close_uis(src)
		return
		// DQEdit End

	if (href_list["access"])
		toggle_access(href_list["access"])
		change_airlock_access(usr)

/obj/item/rcd/proc/toggle_access(acc)
	if (acc == "all")
		conf_access = null
	else if(acc == "one")
		use_one_access = !use_one_access
	else
		var/req = text2num(acc)

		if (conf_access == null)
			conf_access = list()

		if (!(req in conf_access))
			conf_access += req
		else
			conf_access -= req
			if (!conf_access.len)
				conf_access = null



//Storing all the RCD acts and values here for ease of navigation
//////////////////////////////////////
///////////////TURF///////////////////
//////////////////////////////////////
/turf/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(density || !can_build_into_floor)
		return FALSE
	if(passed_mode == RCD_FLOORWALL)
		var/obj/structure/lattice/L = locate() in src
		// A lattice costs one rod to make. A sheet can make two rods, meaning a lattice costs half of a sheet.
		// A sheet also makes four floor tiles, meaning it costs 1/4th of a sheet to place a floor tile on a lattice.
		// Therefore it should cost 3/4ths of a sheet if a lattice is not present, or 1/4th of a sheet if it does.
		return list(
			RCD_VALUE_MODE = RCD_FLOORWALL,
			RCD_VALUE_DELAY = 0,
			RCD_VALUE_COST = L ? RCD_SHEETS_PER_MATTER_UNIT * 0.25 : RCD_SHEETS_PER_MATTER_UNIT * 0.75
			)
	return FALSE

/turf/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_FLOORWALL)
		to_chat(user, span_notice("You build a floor."))
		ChangeTurf(/turf/simulated/floor/airless, preserve_outdoors = TRUE)
		return TRUE
	return FALSE

//////////////////////////////////////
///////////////FLOOR//////////////////
//////////////////////////////////////
/turf/simulated/floor/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_FLOORWALL)
			var/obj/structure/girder/G = locate() in src
			if(G)
				the_rcd.use_rcd(G, user)
				return 1
			// A wall costs four sheets to build (two for the grider and two for finishing it).
			var/cost = RCD_SHEETS_PER_MATTER_UNIT * 2
			return list(
				RCD_VALUE_MODE = RCD_FLOORWALL,
				RCD_VALUE_DELAY = 0.5 SECONDS,
				RCD_VALUE_COST = cost
			)
		if(RCD_AIRLOCK)
			// Airlock assemblies cost four sheets. Let's just add another for the electronics/wires/etc.
			return list(
				RCD_VALUE_MODE = RCD_AIRLOCK,
				RCD_VALUE_DELAY = 5 SECONDS,
				RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 5
			)
		if(RCD_WINDOOR)
			return list(
				RCD_VALUE_MODE = RCD_WINDOOR,
				RCD_VALUE_DELAY = 3 SECONDS,
				RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 3
			)
		if(RCD_FIRELOCK)
			return list(
				RCD_VALUE_MODE = RCD_FIRELOCK,
				RCD_VALUE_DELAY = 3 SECONDS,
				RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 5
			)
		if(RCD_WINDOWGRILLE)
			var/obj/structure/grille/G = locate() in src
			if(G)
				the_rcd.use_rcd(G, user)
				return 1
			return list(
				RCD_VALUE_MODE = RCD_WINDOWGRILLE,
				RCD_VALUE_DELAY = 1 SECOND,
				RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
			)
		if(RCD_DECONSTRUCT)
			//12 floor deconstructions per full RCD
			return list(
				RCD_VALUE_MODE = RCD_DECONSTRUCT,
				RCD_VALUE_DELAY = 3 SECONDS,
				RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 2.5
			)
		if(RCD_FRAME)
			return list(
				RCD_VALUE_MODE = RCD_FRAME,
				RCD_VALUE_DELAY = 1.5 SECONDS,
				RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 5
			)
		if(RCD_CONVEYOR)
			return list(
				RCD_VALUE_MODE = RCD_CONVEYOR,
				RCD_VALUE_DELAY = 1.5 SECONDS,
				RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 6
			)
		if(RCD_TURRET)
			return list(
				RCD_VALUE_MODE = RCD_TURRET,
				RCD_VALUE_DELAY = 6 SECONDS,
				RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 10
			)
	return FALSE


/turf/simulated/floor/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_FLOORWALL)
			to_chat(user, span_notice("You build a girder."))
			new the_rcd.girder_type(src)
			return TRUE
		if(RCD_AIRLOCK)
			if(locate(/obj/machinery/door/airlock) in src)
				return FALSE // No more airlock stacking.
			to_chat(user, span_notice("You build an airlock."))
			var/obj/machinery/door/airlock/A = new the_rcd.airlock_type(src)
			A.electronics = new/obj/item/airlock_electronics(A)
			A.electronics.req_access = null
			A.electronics.req_one_access = null
			A.electronics.one_access = null
			if(the_rcd.conf_access)
				if(the_rcd.use_one_access)
					A.electronics.one_access = the_rcd.use_one_access
					A.electronics.req_one_access = the_rcd.conf_access.Copy()
					A.req_one_access = the_rcd.conf_access.Copy()
				else
					A.electronics.conf_access = the_rcd.conf_access.Copy()
					A.req_access = the_rcd.conf_access.Copy()
			A.autoclose = TRUE
			return TRUE
		if(RCD_WINDOOR)
			var/list/windoor_types = list(
			"default" = image(icon = 'icons/mob/radial.dmi', icon_state = "windoor"),
			"secure" = image(icon = 'icons/mob/radial.dmi', icon_state = "swindoor")
			)
			var/selected_windoor_type = show_radial_menu(user, src, windoor_types, require_near = the_rcd.ranged?FALSE:TRUE, tooltips = TRUE)
			if(!the_rcd.check_menu(user) || !selected_windoor_type)
				return FALSE
			var/list/windoor_dirs = list(
			"NORTH" = image(icon = 'icons/mob/radial.dmi', icon_state = (selected_windoor_type=="default"?"windoorn":"swindoorn")),
			"EAST" = image(icon = 'icons/mob/radial.dmi', icon_state = (selected_windoor_type=="default"?"windoore":"swindoore")),
			"SOUTH" = image(icon = 'icons/mob/radial.dmi', icon_state = (selected_windoor_type=="default"?"windoors":"swindoors")),
			"WEST" = image(icon = 'icons/mob/radial.dmi', icon_state = (selected_windoor_type=="default"?"windoorw":"swindoorw"))
			)
			var/selected_windoor_dir = show_radial_menu(user, src, windoor_dirs, require_near = the_rcd.ranged?FALSE:TRUE, tooltips = TRUE)
			if(!the_rcd.check_menu(user) || !selected_windoor_dir)
				return FALSE
			var/list/windoor_open_dirs = list(
			"left" = image(icon = 'icons/mob/radial.dmi', icon_state = (selected_windoor_type=="default"?"left":"leftsecure")),
			"right" = image(icon = 'icons/mob/radial.dmi', icon_state = (selected_windoor_type=="default"?"right":"rightsecure"))
			)
			var/selected_windoor_open_dir = show_radial_menu(user, src, windoor_open_dirs, require_near = the_rcd.ranged?FALSE:TRUE, tooltips = TRUE)
			if(!the_rcd.check_menu(user) || !selected_windoor_open_dir)
				return FALSE
			var/obj/machinery/door/window/A = new(src)
			if(selected_windoor_type == "default")
				selected_windoor_type = ""
			A.icon_state = selected_windoor_open_dir+selected_windoor_type
			A.base_state = selected_windoor_open_dir+selected_windoor_type
			switch(selected_windoor_dir)
				if("NORTH")
					A.dir = NORTH
				if("SOUTH")
					A.dir = SOUTH
				if("EAST")
					A.dir = EAST
				if("WEST")
					A.dir = WEST
			if(selected_windoor_type == "secure")
				A.health = 300.0
				A.maxhealth =300
			A.electronics = new/obj/item/airlock_electronics(A)
			A.electronics.req_access = null
			A.electronics.req_one_access = null
			A.electronics.one_access = null
			if(the_rcd.conf_access)
				if(the_rcd.use_one_access)
					A.electronics.one_access = the_rcd.use_one_access
					A.electronics.req_one_access = the_rcd.conf_access.Copy()
					A.req_one_access = the_rcd.conf_access.Copy()
				else
					A.electronics.conf_access = the_rcd.conf_access.Copy()
					A.req_access = the_rcd.conf_access.Copy()
			A.autoclose = TRUE
			return TRUE
		if(RCD_FIRELOCK)
			if(locate(/obj/machinery/door/firedoor) in src)
				return FALSE
			to_chat(user, span_notice("You build a firelock."))
			new /obj/machinery/door/firedoor/glass(src)
			return TRUE
		if(RCD_WINDOWGRILLE)
			if(locate(/obj/structure/grille) in src)
				return FALSE
			to_chat(user, span_notice("You construct the grille."))
			var/obj/structure/grille/G = new(src)
			G.anchored = TRUE
			return TRUE
		if(RCD_DECONSTRUCT)
			to_chat(user, span_notice("You deconstruct \the [src]."))
			ChangeTurf(get_base_turf_by_area(src), preserve_outdoors = TRUE)
			return TRUE
		if(RCD_FRAME)
			var/list/frame_types = list(
			"Machine" = image(icon = 'icons/mob/radial.dmi', icon_state = "machine"),
			"Computer" = image(icon = 'icons/mob/radial.dmi', icon_state = "computer_dir")
			)
			var/selected_frame_type = show_radial_menu(user, src, frame_types, require_near = the_rcd.ranged?FALSE:TRUE, tooltips = TRUE)
			if(!the_rcd.check_menu(user) || !selected_frame_type)
				return FALSE
			var/list/frame_dirs = list(
			"NORTH" = image(icon = 'icons/mob/radial.dmi', icon_state = "cnorth"),
			"EAST" = image(icon = 'icons/mob/radial.dmi', icon_state = "ceast"),
			"SOUTH" = image(icon = 'icons/mob/radial.dmi', icon_state = "csouth"),
			"WEST" = image(icon = 'icons/mob/radial.dmi', icon_state = "cwest")
			)
			var/selected_frame_dir = show_radial_menu(user, src, frame_dirs, require_near = the_rcd.ranged?FALSE:TRUE, tooltips = TRUE)
			if(!the_rcd.check_menu(user) || !selected_frame_dir)
				return FALSE
			var/obj/structure/frame
			if(selected_frame_type == "Machine")
				frame = new/obj/structure/frame(src)
			else
				frame = new/obj/structure/frame/computer(src)
			switch(selected_frame_dir)
				if("NORTH")
					frame.dir = NORTH
				if("SOUTH")
					frame.dir = SOUTH
				if("EAST")
					frame.dir = EAST
				if("WEST")
					frame.dir = WEST
			frame.anchored = 1
			to_chat(user, span_notice("You build a frame"))
			return TRUE
		if(RCD_CONVEYOR)
			var/list/conveyor_dirs = list(
			"NORTH" = image(icon = 'icons/mob/radial.dmi', icon_state = "conveyorn"),
			"EAST" = image(icon = 'icons/mob/radial.dmi', icon_state = "conveyore"),
			"SOUTH" = image(icon = 'icons/mob/radial.dmi', icon_state = "conveyors"),
			"WEST" = image(icon = 'icons/mob/radial.dmi', icon_state = "conveyorw")
			)
			var/selected_conveyor_dir = show_radial_menu(user, src, conveyor_dirs, require_near = the_rcd.ranged?FALSE:TRUE, tooltips = TRUE)
			if(!the_rcd.check_menu(user) || !selected_conveyor_dir)
				return FALSE
			var/obj/machinery/conveyor/C = new(src)
			switch(selected_conveyor_dir)
				if("NORTH")
					C.set_dir(NORTH)
				if("SOUTH")
					C.set_dir(SOUTH)
				if("EAST")
					C.set_dir(EAST)
				if("WEST")
					C.set_dir(WEST)
			to_chat(user, span_notice("You build a conveyor"))
			return TRUE
		if(RCD_TURRET)
			if(locate(/obj/machinery/porta_turret) in src)
				return FALSE
			var/obj/machinery/porta_turret/T = new /obj/machinery/porta_turret/rcd(src)
			T.faction = the_rcd.turret_faction
			return TRUE

//////////////////////////////////////
//////////////WALL////////////////////
//////////////////////////////////////
/turf/simulated/wall/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			if(material.integrity > 1000) // Don't decon things like elevatorium.
				return FALSE
			if(reinf_material && !the_rcd.can_remove_rwalls) // Gotta do it the old fashioned way if your RCD can't.
				return FALSE
			var/delay_to_use = material.integrity / 3 // Steel has 150 integrity, so it'll take five seconds to down a regular wall.
			if(reinf_material)
				delay_to_use += reinf_material.integrity / 3
			return list(
				RCD_VALUE_MODE = RCD_DECONSTRUCT,
				RCD_VALUE_DELAY = delay_to_use,
				RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 2.5
				)
		if(RCD_WALLFRAME)
			return list(
				RCD_VALUE_MODE = RCD_WALLFRAME,
				RCD_VALUE_DELAY = 1,
				RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 3
				)
	return FALSE

/turf/simulated/wall/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			to_chat(user, span_notice("You deconstruct \the [src]."))
			ChangeTurf(/turf/simulated/floor/airless, preserve_outdoors = TRUE)
			return TRUE
		if(RCD_WALLFRAME)
			if(!user || !x || !y || !user.x || !user.y) return
			var/dx = user.x - x
			var/dy = user.y - y
			if(!dx && !dy) return

			var/direction
			if(abs(dx) < abs(dy))
				if(dy > 0)	direction = NORTH
				else		direction = SOUTH
			else
				if(dx > 0)	direction = EAST
				else		direction = WEST
			if(gotwallitem(get_step(src,direction), direction))
				to_chat(user, span_warning("There is already a wall item there!"))
				return FALSE
			var/obj/O = new the_rcd.wall_frame_type(get_step(src,direction))
			O.dir = direction
			if(istype(O,/obj/machinery/light))
				O.dir = GLOB.reverse_dir[O.dir]
				return TRUE
			var/list/adjusts = list(
			/obj/machinery/computer/security/telescreen/entertainment,
			/obj/machinery/ai_status_display,
			/obj/machinery/station_map,
			/obj/machinery/recharger/wallcharger,
			/obj/machinery/status_display
			)
			var/adjust_val = 0
			for(var/A in adjusts)
				if(istype(O,A))
					adjust_val = 6
					break
			switch(direction)
				if(NORTH)
					O.pixel_x = 0
					O.pixel_y = -26 - adjust_val
				if(SOUTH)
					O.pixel_x = 0
					O.pixel_y = 26 + adjust_val
				if(EAST)
					O.pixel_x = -26 - adjust_val
					O.pixel_y = 0
				if(WEST)
					O.pixel_x = 26 + adjust_val
					O.pixel_y = 0
			return TRUE
	return FALSE

//////////////////////////////////////
//////////////GIRDER//////////////////
//////////////////////////////////////
/obj/structure/girder/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	var/turf/simulated/T = get_turf(src)
	if(!istype(T) || T.density)
		return FALSE

	switch(passed_mode)
		if(RCD_FLOORWALL)
			// Finishing a wall costs two sheets.
			var/cost = RCD_SHEETS_PER_MATTER_UNIT * 2
			// Rwalls cost three to finish.
			if(the_rcd.make_rwalls)
				cost += RCD_SHEETS_PER_MATTER_UNIT * 1
			return list(
				RCD_VALUE_MODE = RCD_FLOORWALL,
				RCD_VALUE_DELAY = 0.5 SECONDS,
				RCD_VALUE_COST = cost
			)
		if(RCD_DECONSTRUCT)
			return list(
				RCD_VALUE_MODE = RCD_DECONSTRUCT,
				RCD_VALUE_DELAY = 0.5 SECONDS,
				RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
			)
	return FALSE

/obj/structure/girder/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	var/turf/simulated/T = get_turf(src)
	if(!istype(T) || T.density) // Should stop future bugs of people bringing girders to centcom and RCDing them, or somehow putting a girder on a durasteel wall and deconning it.
		return FALSE

	switch(passed_mode)
		if(RCD_FLOORWALL)
			to_chat(user, span_notice("You finish a wall."))
			// This is mostly the same as using on a floor. The girder's material is preserved, however.
			T.ChangeTurf(wall_type)
			var/turf/simulated/wall/new_T = get_turf(src) // Ref to the wall we just built.
			// Apparently set_material(...) for walls requires refs to the material singletons and not strings.
			// This is different from how other material objects with their own set_material(...) do it, but whatever.
			var/datum/material/M = GLOB.name_to_material[the_rcd.material_to_use]
			new_T.set_material(M, the_rcd.make_rwalls ? M : null, girder_material)
			new_T.add_hiddenprint(user)
			qdel(src)
			return TRUE

		if(RCD_DECONSTRUCT)
			to_chat(user, span_notice("You deconstruct \the [src]."))
			qdel(src)
			return TRUE

//////////////////////////////////////
/////////////WINDOW///////////////////
//////////////////////////////////////
/obj/structure/window/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			return list(
				RCD_VALUE_MODE = RCD_DECONSTRUCT,
				RCD_VALUE_DELAY = 2 SECONDS,
				RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
			)
		if(RCD_WINDOWGRILLE)
			the_rcd.use_rcd(get_turf(src), user)
			return 1

/obj/structure/window/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			to_chat(user, span_notice("You deconstruct \the [src]."))
			qdel(src)
			return TRUE
	return FALSE

//////////////////////////////////////
//////////////GRILLE//////////////////
//////////////////////////////////////
/obj/structure/grille/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_WINDOWGRILLE)
			var/construct_cost = 4
			if(destroyed)
				construct_cost = 1
			else
				var/list/window_dirs = list(
				"NORTH" = image(icon = 'icons/mob/radial.dmi', icon_state = "wnorth"),
				"EAST" = image(icon = 'icons/mob/radial.dmi', icon_state = "weast"),
				"SOUTH" = image(icon = 'icons/mob/radial.dmi', icon_state = "wsouth"),
				"WEST" = image(icon = 'icons/mob/radial.dmi', icon_state = "wwest"),
				"FULL" = image(icon = 'icons/mob/radial.dmi', icon_state = "wfull"),
				)
				var/selected_window_dir = show_radial_menu(user, src, window_dirs, require_near = the_rcd.ranged?FALSE:TRUE, tooltips = TRUE)
				if(!the_rcd.check_menu(user) || !selected_window_dir)
					return FALSE
				the_rcd.window_dir = selected_window_dir
				if(selected_window_dir != "FULL")
					construct_cost = 1
			// A full tile window costs 4 glass sheets.
			return list(
				RCD_VALUE_MODE = RCD_WINDOWGRILLE,
				RCD_VALUE_DELAY = 1 SECONDS,
				RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * construct_cost
			)
		//Honestly shouldn't cost anything to deconstruct a grille
		if(RCD_DECONSTRUCT)
			return list(
				RCD_VALUE_MODE = RCD_DECONSTRUCT,
				RCD_VALUE_DELAY = 0.5 SECONDS,
				RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 0
			)
	return FALSE

/obj/structure/grille/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			to_chat(user, span_notice("You deconstruct \the [src]."))
			qdel(src)
			return TRUE
		if(RCD_WINDOWGRILLE)
			if(destroyed)
				destroyed = 0
				health = initial(health)
				update_icon()
				density = 1
				to_chat(user, span_notice("You repair \the [src]."))
				return TRUE
			var/temp_dir
			switch(the_rcd.window_dir)
				if("NORTH")
					temp_dir = NORTH
				if("SOUTH")
					temp_dir = SOUTH
				if("EAST")
					temp_dir = EAST
				if("WEST")
					temp_dir = WEST
				if("FULL")
					temp_dir = 10
			for(var/obj/structure/window/W in src.loc)
				if(W && W.dir == temp_dir)
					to_chat(user, span_warning("There is already a window there."))
					return FALSE

			to_chat(user, span_notice("You construct a window."))
			var/window_to_spawn = /obj/structure/window/basic
			switch(the_rcd.window_type)
				if("glass")
					window_to_spawn = (temp_dir==10?"/obj/structure/window/basic/full":"/obj/structure/window/basic")
				if("rglass")
					window_to_spawn = (temp_dir==10?"/obj/structure/window/reinforced/full":"/obj/structure/window/reinforced")
				if("phoron")
					window_to_spawn = (temp_dir==10?"/obj/structure/window/phoronbasic/full":"/obj/structure/window/phoronbasic")
				if("rphoron")
					window_to_spawn = (temp_dir==10?"/obj/structure/window/phoronreinforced/full":"/obj/structure/window/phoronreinforced")
				if("titanium")
					window_to_spawn = (temp_dir==10?"/obj/structure/window/titanium/full":"/obj/structure/window/titanium")
				if("plastitanium")
					window_to_spawn = (temp_dir==10?"/obj/structure/window/plastitanium/full":"/obj/structure/window/plastitanium")
			var/obj/structure/window/WD = new window_to_spawn(loc)
			WD.anchored = TRUE
			WD.dir = temp_dir
			return TRUE
	return FALSE

//////////////////////////////////////
////////////AIRLOCK///////////////////
//////////////////////////////////////
/obj/machinery/door/airlock/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			//6 deconstructs per full RCD
			return list(
				RCD_VALUE_MODE = RCD_DECONSTRUCT,
				RCD_VALUE_DELAY = 4 SECONDS,
				RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 4
			)
		if(RCD_FIRELOCK)
			the_rcd.use_rcd(get_turf(src), user)
			return 1
	return FALSE

/obj/machinery/door/airlock/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			to_chat(user, span_notice("You deconstruct \the [src]."))
			qdel(src)
			return TRUE
	return FALSE

//////////////////////////////////////
/////////////FIRELOCK/////////////////
//////////////////////////////////////
/obj/machinery/door/firedoor/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 3
		)
	return FALSE

/obj/machinery/door/firedoor/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE
//////////////////////////////////////
////////////WALL FRAMES///////////////
//////////////////////////////////////
/obj/machinery/computer/security/telescreen/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/computer/security/telescreen/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/doorbell_chime/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/doorbell_chime/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/status_display/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/status_display/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/requests_console/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/requests_console/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/atm/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/atm/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/newscaster/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/newscaster/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/recharger/wallcharger/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/recharger/wallcharger/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/firealarm/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/firealarm/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/alarm/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/alarm/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/computer/guestpass/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/computer/guestpass/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/item/radio/intercom/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/item/radio/intercom/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/keycard_auth/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/keycard_auth/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/item/geiger/wall/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/item/geiger/wall/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/button/windowtint/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/button/windowtint/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/computer/id_restorer/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/computer/id_restorer/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/computer/timeclock/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/computer/timeclock/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/station_map/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/station_map/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/structure/trash_pile/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 8 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/structure/trash_pile/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/structure/loot_pile/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 8 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/structure/loot_pile/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/structure/frame/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/structure/frame/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/ai_status_display/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/ai_status_display/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/light/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/light/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/hologram/holopad/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/hologram/holopad/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/light_switch/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/light_switch/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/structure/table/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/structure/table/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/conveyor/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 2 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/conveyor/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/door/window/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 3 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 3
		)
	return FALSE

/obj/machinery/door/window/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/structure/firedoor_assembly/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 1 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/structure/firedoor_assembly/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/structure/door_assembly/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 1 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/structure/door_assembly/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE

/obj/machinery/button/doorbell/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return list(
			RCD_VALUE_MODE = RCD_DECONSTRUCT,
			RCD_VALUE_DELAY = 1 SECONDS,
			RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 1
		)
	return FALSE

/obj/machinery/button/doorbell/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		to_chat(user, span_notice("You deconstruct \the [src]."))
		qdel(src)
		return TRUE
	return FALSE
