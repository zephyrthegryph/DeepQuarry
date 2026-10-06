#define TANK_IDEAL_PRESSURE 1015 //Arbitrary.

DECLARE_SHARED_CACHE(tank_gauge_overlays, GLOBAL_PROC_REF(build_tank_gauge_overlay), SC_NEVER)

/// Builder for tank_gauge_overlays.
/proc/build_tank_gauge_overlay(icon, indicator)
	return image(icon, indicator)

/obj/item/tank
	material_template = /datum/material_template/pressure
	material_total = SHEET_MATERIAL_AMOUNT
	name = "tank"
	icon = 'icons/obj/tank.dmi'
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/back/mob_teshari.dmi'
		)
	drop_sound = SFX_ITEMS_DROP_GASCAN
	pickup_sound = SFX_ITEMS_PICKUP_GASCAN

	var/gauge_icon = "indicator_tank"
	var/last_gauge_pressure
	var/gauge_cap = 6

	slot_flags = SLOT_BACK
	w_class = ITEMSIZE_NORMAL

	force = 5.0
	throwforce = 10.0
	throw_speed = 1
	throw_range = 4

	var/datum/gas_mixture/air_contents = null
	var/distribute_pressure = ONE_ATMOSPHERE
	// The tank's integrity is its pressure seal: over-pressure and heat wear it
	// down (tank_stress) and it recovers while the tank is at rest. At zero the
	// seal has failed; the tank ruptures if it is still over-pressured.
	max_integrity = 200
	var/valve_welded = 0
	var/obj/item/tankassemblyproxy/proxyassembly

	var/volume = 70
	var/manipulated_by = null		//Used by _onclick/hud/screen_objects.dm internals to determine if someone has messed with our tank or not.
						//If they have and we haven't scanned it with the PDA or gas analyzer then we might just breath whatever they put in it.

	var/failure_temp = 173 //173 deg C Borate seal (yes it should be 153 F, but that's annoying)
	var/wired = 0


	description_antag = "Each tank may be incited to burn by attaching wires and an igniter assembly, though the igniter can only be used once and the mixture only burn if the igniter pushes a flammable gas mixture above the minimum burn temperature (126ºC). \
	Wired and assembled tanks may be disarmed with a set of wirecutters. Any exploding or rupturing tank will generate shrapnel, assuming their relief valves have been welded beforehand. Even if not, they can be incited to expel hot gas on ignition if pushed above 173ºC. \
	Relatively easy to make, the single tank bomb requries no tank transfer valve, and is still a fairly formidable weapon that can be manufactured from any tank."

CAPABILITIES(/obj/item/tank)
	owns_one(nameof(air_contents), /datum/gas_mixture)
	owns_one(nameof(proxyassembly), /obj/item/tankassemblyproxy)
	interface("Tank", state = nameof(GLOB.tgui_deep_inventory_state))
	without("ui_open")
	op("pressure", ui_act("pressure", arg("pressure")), then(PROC_REF(ui_act_pressure)))
	op("toggle", ui_act("toggle"), then(PROC_REF(ui_act_toggle)))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), wait(0), then(PROC_REF(wirecutter_used)))
	op("use_welder", tool(TOOL_WELDER), wait(0), costs(RES_FUEL, 0), then(PROC_REF(welder_used)))
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("tank_item", item(/obj/item), label("Tank item"), then(PROC_REF(tank_item)))

/obj/item/tank/proc/init_proxy()
	var/obj/item/tankassemblyproxy/proxy = new /obj/item/tankassemblyproxy(src)
	rel_set(proxy, nameof(proxy.tank), src)
	rel_set(src, nameof(proxyassembly), proxy)

/obj/item/tank/Initialize(mapload)
	. = ..()
	apply_blueprint_effects()

	src.init_proxy()
	update_gauge()

DECLARE_GAS(/obj/item/tank, "air_contents", "volume", T20C, null)

/// TRUE while the relief valve or a failed seal is venting.
OM_FIELD(/obj/item/tank, leaking, FALSE, CHANGE_EXPLICIT)
/// TRUE while the seal is below max integrity. Kept by on_update_integrity(), the hook every
/// integrity write (take_damage, repair_damage, update_integrity) goes through.
OM_FIELD(/obj/item/tank, seal_damaged, FALSE, CHANGE_EXPLICIT)
/// The tank reacts its gas and checks its seal every 2 s while it is leaking, damaged, or held or
/// worn by a mob (moving raises CHANGE_ITEM_LOC). MANY tanks during rounds are never touched, and
/// an intact, sealed tank lying about has no reason to explode spontaneously.
OM_DERIVE_FIELD(/obj/item/tank, pressure_watched, list("leaking", "seal_damaged", CHANGE_ITEM_LOC))
DECLARE_PERIODIC_WHILE(/obj/item/tank, PERIODIC_SLOW, "pressure_watched")

/obj/item/tank/proc/pressure_watched()
	return leaking || seal_damaged || ismob(loc)

/obj/item/tank/on_update_integrity(old_value, new_value)
	. = ..()
	set_seal_damaged(new_value < max_integrity)

// a tank in a transfer valve leaves the valve.
/obj/item/tank/on_destroy(force)
	if(istype(loc, /obj/item/transfer_valve))
		var/obj/item/transfer_valve/TTV = loc
		TTV.remove_tank(src)
	..()

/obj/item/tank/material_environment_begin_leak()
	set_leaking(TRUE)
	return ..()

/obj/item/tank/material_environment_repaired()
	set_leaking(FALSE)
	repair_damage(max_integrity)
	return ..()

/obj/item/tank/material_environment_owns_leak()
	return TRUE

/obj/item/tank/material_environment_rupture()
	// The established tank rupture path supplies fragments, gas release, and
	// explosion strength. Drive it by state instead of bypassing it with qdel.
	update_integrity(0)
	set_leaking(TRUE)
	check_status()

/obj/item/tank/equipped() // Note that even grabbing into a hand calls this, so it should be fine as a 'has a player touched this'
	. = ..()
	// An attempt at optimization. There are MANY tanks during rounds that will never get touched.
	// Don't see why any of those would explode spontaneously. So only tanks that players touch get processed.
	// Held or worn, it is watched (pressure_watched(); the move raised CHANGE_ITEM_LOC).

/obj/item/tank/examine(mob/user)
	. = ..()
	if(loc == user)
		var/celsius_temperature = air_contents.return_temperature() - T0C
		var/descriptive
		switch(celsius_temperature)
			if(300 to INFINITY)
				descriptive = "furiously hot"
			if(100 to 300)
				descriptive = "hot"
			if(80 to 100)
				descriptive = "warm"
			if(40 to 80)
				descriptive = "lukewarm"
			if(20 to 40)
				descriptive = "room temperature"
			if(-20 to 20)
				descriptive = "cold"
			else
				descriptive = "bitterly cold"
		. += span_notice("\The [src] feels [descriptive].")

	if(src.proxyassembly.assembly || wired)
		. += span_warning("It seems to have [wired? "some wires ": ""][wired && src.proxyassembly.assembly? "and ":""][src.proxyassembly.assembly ? "some sort of assembly ":""]attached to it.")
	if(src.valve_welded)
		. += span_warning("\The [src] emergency relief valve has been welded shut!")

/// Old attackby (its ..() ran first; the base item handling now follows the pass).
/obj/item/tank/proc/tank_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if (istype(src.loc, /obj/item/assembly))
		icon = src.loc

	else if (istype(W,/obj/item/latexballon))
		var/obj/item/latexballon/LB = W
		LB.blow(src)
		src.add_fingerprint(user)

	if(istype(W, /obj/item/stack/cable_coil))
		var/obj/item/stack/cable_coil/C = W
		if(C.use(1))
			wired = 1
			to_chat(user, span_notice("You attach the wires to the tank."))
			src.add_bomb_overlay()

	if(istype(W, /obj/item/assembly_holder))
		if(wired)
			to_chat(user, span_notice("You begin attaching the assembly to \the [src]."))
			om_task_start(/datum/om/task/timed/tank_attackby, user, src, receiver = src, W = W)
		else
			to_chat(user, span_notice("You need to wire the device up first."))
	return OP_PASS

/datum/om/task/timed/tank_attackby
	duration = 5 SECONDS
	complete_proc = /obj/item/tank/proc/attackby_timed_done
	cancel_proc = /obj/item/tank/proc/attackby_timed_failed
	var/obj/item/W

/obj/item/tank/proc/attackby_timed_done(datum/om/task/timed/tank_attackby/task)
	var/obj/item/W = task.W
	var/mob/user = task.actor
	to_chat(user, span_notice("You finish attaching the assembly to \the [src]."))
	GLOB.bombers += "[key_name(user)] attached an assembly to a wired [src]. Temp: [src.air_contents.return_temperature()-T0C]"
	message_admins("[key_name_admin(user)] attached an assembly to a wired [src]. Temp: [src.air_contents.return_temperature()-T0C]")
	assemble_bomb(W,user)

/obj/item/tank/proc/attackby_timed_failed(datum/om/task/timed/tank_attackby/task)
	var/mob/user = task.actor
	to_chat(user, span_notice("You stop attaching the assembly."))

/obj/item/tank/proc/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	if(wired && src.proxyassembly.assembly)

		to_chat(user, span_notice("You carefully begin clipping the wires that attach to the tank."))
		om_task_timed(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(wirecutter_act_timed_done), done_args = list(user), on_fail = PROC_REF(wire_clip_slipped), fail_args = list(user))

	else if(wired)
		om_task_timed(user, 1 SECOND, target = src, receiver = src, on_done = PROC_REF(wirecutter_act_timed_done2), done_args = list(user))

	else
		to_chat(user, span_notice("There are no wires to cut!"))
	return OP_OK

/obj/item/tank/proc/wire_clip_slipped(mob/user)
	to_chat(user, span_danger("You slip and bump the igniter!"))
	if(prob(85))
		src.proxyassembly?.receive_signal()

/obj/item/tank/proc/wirecutter_act_timed_done(mob/user)
	wired = 0
	cut_overlay("bomb_assembly")
	to_chat(user, span_notice("You cut the wire and remove the device."))

	var/obj/item/assembly_holder/assy = src.proxyassembly.assembly
	if(assy.a_left && assy.a_right)
		assy.dropInto(user.loc)
		rel_clear(assy, nameof(assy.master))
		rel_clear(src.proxyassembly, nameof(/obj/item/integrated_circuit::assembly))
	else
		if(!src.proxyassembly.assembly.a_left)
			assy.a_right.dropInto(user.loc)
			rel_clear(assy.a_right, nameof(/client::holder))
			own_take(assy, nameof(assy.a_right))
			rel_clear(src.proxyassembly, nameof(/obj/item/integrated_circuit::assembly))
			destroyed(assy, user)
	cut_overlays()
	last_gauge_pressure = 0
	update_gauge()
/obj/item/tank/proc/wirecutter_act_timed_done2(mob/user)
	to_chat(user, span_notice("You quickly clip the wire from the tank."))
	wired = 0
	cut_overlay("bomb_assembly")

/obj/item/tank/proc/welder_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	var/obj/item/weldingtool/WT = tool.get_welder()
	if(WT?.remove_fuel(1,user))
		if(!valve_welded)
			to_chat(user, span_notice("You begin welding the \the [src] emergency pressure relief valve."))
			om_task_start(/datum/om/task/timed/tank_welder_act, user, src, receiver = src, tool = tool, WT = WT)
			WT.eyecheck(user)
		else
			to_chat(user, span_notice("The emergency pressure relief valve has already been welded."))
	add_fingerprint(user)
	return OP_OK

/datum/om/task/timed/tank_welder_act
	duration = 4 SECONDS
	complete_proc = /obj/item/tank/proc/welder_act_timed_done
	cancel_proc = /obj/item/tank/proc/welder_act_timed_failed
	var/obj/item/tool
	var/obj/item/weldingtool/WT

/obj/item/tank/proc/welder_act_timed_done(datum/om/task/timed/tank_welder_act/task)
	var/mob/user = task.actor
	to_chat(user, span_notice("You carefully weld \the [src] emergency pressure relief valve shut.") + " " + span_warning("\The [src] may now rupture under pressure!"))
	src.valve_welded = 1
	set_leaking(FALSE)

/obj/item/tank/proc/welder_act_timed_failed(datum/om/task/timed/tank_welder_act/task)
	var/mob/user = task.actor
	var/obj/item/tool = task.tool
	var/obj/item/weldingtool/WT = task.WT
	GLOB.bombers += "[key_name(user)] attempted to weld a [src]. [src.air_contents.return_temperature()-T0C]"
	message_admins("[key_name_admin(user)] attempted to weld a [src]. [src.air_contents.return_temperature()-T0C]")
	if(WT.welding)
		to_chat(user, span_danger("You accidentally rake \the [tool] across \the [src]!"))
		max_integrity -= rand(20,60)
		if(get_integrity() > max_integrity)
			update_integrity(max_integrity)
		heat_add(src.air_contents, rand(2000,50000), HEAT_SOURCE_OTHER)

/// Old attack_self.
/obj/item/tank/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	if (!(src.air_contents))
		return TRUE
	tgui_interact(user)

	// There's GOT to be a better way to do this
	if (src.proxyassembly.assembly)
		src.proxyassembly.assembly.attack_self(user)
	return TRUE

/// /obj/item/tank's window data.
/obj/item/tank/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	data["tankPressure"] = round(air_contents.return_pressure() ? air_contents.return_pressure() : 0)
	data["releasePressure"] = round(distribute_pressure ? distribute_pressure : 0)
	data["defaultReleasePressure"] = round(TANK_DEFAULT_RELEASE_PRESSURE)
	data["minReleasePressure"] = 0
	data["maxReleasePressure"] = round(TANK_MAX_RELEASE_PRESSURE)

	var/mob/living/carbon/C = user
	if(!istype(C))
		C = loc.loc
	if(!istype(C))
		return data

	if(C.internal == src)
		data["connected"] = TRUE
	else
		data["connected"] = FALSE

	data["maskConnected"] = FALSE
	if(C.get_equipped_item(SLOT_ID_MASK) && (C.get_equipped_item(SLOT_ID_MASK).item_flags & AIRTIGHT))
		data["maskConnected"] = TRUE
	else if(ishuman(C))
		var/mob/living/carbon/human/H = C
		if(H.get_equipped_item(SLOT_ID_HEAD) && (H.get_equipped_item(SLOT_ID_HEAD).item_flags & AIRTIGHT))
			data["maskConnected"] = TRUE

	return data

/obj/item/tank/proc/ui_act_pressure(datum/act/op/A, pressure_arg)
	var/mob/user = A.actor
	var/pressure = pressure_arg
	if(pressure == "reset")
		pressure = TANK_DEFAULT_RELEASE_PRESSURE
		. = TRUE
	else if(pressure == "min")
		pressure = 0
		. = TRUE
	else if(pressure == "max")
		pressure = TANK_MAX_RELEASE_PRESSURE
		. = TRUE
	else if(isnum(pressure))
		. = TRUE
	if(.)
		distribute_pressure = clamp(round(pressure), 0, TANK_MAX_RELEASE_PRESSURE)
	add_fingerprint(user)

/obj/item/tank/proc/ui_act_toggle(datum/act/op/A)
	var/mob/user = A.actor
	toggle_valve(user)
	. = TRUE
	add_fingerprint(user)

/obj/item/tank/proc/toggle_valve(mob/user)
	if(istype(loc,/mob/living/carbon))
		var/mob/living/carbon/location = loc
		if(location.internal == src)
			rel_clear(location, nameof(location.internal))
			location.internals.icon_state = "internal0"
			to_chat(user, span_notice("You close the tank release valve."))
			if (location.internals)
				location.internals.icon_state = "internal0"
		else
			var/can_open_valve
			if(location.get_equipped_item(SLOT_ID_MASK) && (location.get_equipped_item(SLOT_ID_MASK).item_flags & AIRTIGHT))
				can_open_valve = 1
			else if(ishuman(location))
				var/mob/living/carbon/human/H = location
				if(H.get_equipped_item(SLOT_ID_HEAD) && (H.get_equipped_item(SLOT_ID_HEAD).item_flags & AIRTIGHT))
					can_open_valve = 1

			if(can_open_valve)
				rel_set(location, nameof(location.internal), src)
				to_chat(user, span_notice("You open \the [src] valve."))
				if (location.internals)
					location.internals.icon_state = "internal1"
			else
				to_chat(user, span_warning("You need something to connect to \the [src]."))

/obj/item/tank/remove_air(amount)
	return air_contents.remove(amount)

/obj/item/tank/proc/remove_air_by_flag(flag, amount)
	return air_contents.remove_by_flag(flag, amount)

/obj/item/tank/return_air()
	return air_contents

/obj/item/tank/assume_air(datum/gas_mixture/giver)
	air_contents.merge(giver)

	check_status()
	return 1

/obj/item/tank/proc/remove_air_volume(volume_to_return)
	if(!air_contents)
		return null

	var/tank_pressure = air_contents.return_pressure()
	if(tank_pressure < distribute_pressure)
		distribute_pressure = tank_pressure

	var/moles_needed = distribute_pressure*volume_to_return/(R_IDEAL_GAS_EQUATION*air_contents.return_temperature())

	return remove_air(moles_needed)

/obj/item/tank/periodic_step()
	if(!air_contents)
		return
	//Allow for reactions
	air_contents.react() //cooking up air tanks - add phoron and oxygen, then heat above PLASMA_MINIMUM_BURN_TEMPERATURE
	if(gauge_icon)
		update_gauge()
	check_status()

/obj/item/tank/proc/add_bomb_overlay()
	if(src.wired)
		add_overlay("bomb_assembly")
		if(src.proxyassembly.assembly)
			var/icon/test = getFlatIcon(src.proxyassembly.assembly)
			test.Shift(SOUTH,1)
			test.Shift(WEST,3)
			add_overlay(test)

/obj/item/tank/proc/update_gauge()
	var/gauge_pressure = 0
	if(air_contents)
		gauge_pressure = air_contents.return_pressure()
		if(gauge_pressure > TANK_IDEAL_PRESSURE)
			gauge_pressure = -1
		else
			gauge_pressure = round((gauge_pressure/TANK_IDEAL_PRESSURE)*gauge_cap)

	if(gauge_pressure == last_gauge_pressure)
		return

	last_gauge_pressure = gauge_pressure
	cut_overlays()
	add_bomb_overlay()
	var/indicator = "[gauge_icon][(gauge_pressure == -1) ? "overload" : gauge_pressure]"
	add_overlay(CACHED_KEY(tank_gauge_overlays, indicator, icon, indicator))

/obj/item/tank/proc/check_status()
	//Handle exploding, leaking, and rupturing of the tank

	if(!air_contents)
		return 0

	var/pressure = air_contents.return_pressure()
	var/datum/gas_mixture/environment = loc?.return_air()
	if(QDELETED(src))
		return 0
	var/material_rupture_pressure = material_environment_pressure_limit(TANK_RUPTURE_PRESSURE, MATERIAL_TANK_REFERENCE_RADIUS, MATERIAL_TANK_REFERENCE_THICKNESS, air_contents.return_temperature())
	var/pressure_scale = material_rupture_pressure / TANK_RUPTURE_PRESSURE
	var/material_leak_pressure = TANK_LEAK_PRESSURE * pressure_scale
	var/material_fragment_pressure = TANK_FRAGMENT_PRESSURE * pressure_scale
	var/material_fragment_scale = TANK_FRAGMENT_SCALE * pressure_scale
	var/datum/material/insulation = material_for_role(MATERIAL_ROLE_INSULATION)
	var/datum/material/plastic = get_material_by_name(MAT_PLASTIC)
	var/material_failure_temperature = T0C + failure_temp
	if(insulation && plastic?.melting_point)
		material_failure_temperature = T0C + failure_temp * insulation.melting_point / plastic.melting_point

	if(pressure > material_fragment_pressure)
		if(get_integrity() <= 70)
			if(!istype(src.loc,/obj/item/transfer_valve))
				message_admins("Explosive tank rupture! last key to touch the tank was [forensic_data?.get_lastprint()].")
				log_game("Explosive tank rupture! last key to touch the tank was [forensic_data?.get_lastprint()].")

			//Give the gas a chance to build up more pressure through reacting
			air_contents.react()
			air_contents.react()
			air_contents.react()

			pressure = air_contents.return_pressure()
			var/strength = ((pressure-material_fragment_pressure)/material_fragment_scale)

			var/mult = ((src.air_contents.return_volume()/140)**(1/2)) * (air_contents.total_moles()**(2/3))/((29*0.64) **(2/3)) //tanks appear to be experiencing a reduction on scale of about 0.64 total moles
			//tanks appear to be experiencing a reduction on scale of about 0.64 total moles

			var/turf/simulated/T = get_turf(src)
			T.hotspot_expose(src.air_contents.return_temperature(), 70, 1)
			if(!T)
				return

			T.assume_air(air_contents)
			explosion(
				get_turf(loc),
				round(min(BOMBCAP_DVSTN_RADIUS, ((mult)*strength)*0.15)),
				round(min(BOMBCAP_HEAVY_RADIUS, ((mult)*strength)*0.35)),
				round(min(BOMBCAP_LIGHT_RADIUS, ((mult)*strength)*0.80)),
				round(min(BOMBCAP_FLASH_RADIUS, ((mult)*strength)*1.20)),
				)

			var/num_fragments = round(rand(8,10) * sqrt(strength * mult))
			src.fragmentate(T, num_fragments, rand(5) + 7, list(/obj/item/projectile/bullet/pellet/fragment/tank/small = 7,/obj/item/projectile/bullet/pellet/fragment/tank = 2,/obj/item/projectile/bullet/pellet/fragment/strong = 1))

			if(istype(loc, /obj/item/transfer_valve))
				var/obj/item/transfer_valve/TTV = loc
				TTV.remove_tank(src)
				spent(TTV)

			if(src)
				destroyed(src)

		else
			tank_stress(70)

	else if(pressure > material_rupture_pressure)
		#ifdef FIREDBG
		log_world(span_warning("[x],[y] tank is rupturing: [pressure] kPa, integrity [get_integrity()]"))
		#endif

		air_contents.react()

		if(get_integrity() <= 0)
			var/turf/simulated/T = get_turf(src)
			if(!T)
				return
			T.assume_air(air_contents)
			play_sfx(src, SFX_WEAPONS_GUNSHOT_SHOTGUN)
			visible_message("[icon2html(src,viewers(src))] " + span_danger("\The [src] flies apart!"), span_warning("You hear a bang!"))
			T.hotspot_expose(air_contents.return_temperature(), 70, 1)

			var/strength = 1+((pressure-material_leak_pressure)/material_fragment_scale)

			var/mult = (air_contents.total_moles()**2/3)/((29*0.64) **2/3) //tanks appear to be experiencing a reduction on scale of about 0.64 total moles

			var/num_fragments = round(rand(6,8) * sqrt(strength * mult)) //Less chunks, but bigger
			src.fragmentate(T, num_fragments, 7, list(/obj/item/projectile/bullet/pellet/fragment/tank/small = 1,/obj/item/projectile/bullet/pellet/fragment/tank = 5,/obj/item/projectile/bullet/pellet/fragment/strong = 4))

			if(istype(loc, /obj/item/transfer_valve))
				var/obj/item/transfer_valve/TTV = loc
				TTV.remove_tank(src)

			spent(src)

		else
			if(!valve_welded)
				tank_stress(30)
				set_leaking(TRUE)
			else
				tank_stress(50)

	else if(leaking || pressure > material_leak_pressure || air_contents.return_temperature() > material_failure_temperature)

		if((get_integrity() <= 170 || src.leaking) && !valve_welded)
			var/turf/simulated/T = get_turf(src)
			if(!T)
				return
			environment = loc.return_air()
			var/env_pressure = environment.return_pressure()
			var/tank_pressure = src.air_contents.return_pressure()

			var/release_ratio = 0.002
			if(tank_pressure)
				release_ratio = CLAMP(sqrt(max(tank_pressure-env_pressure,0)/tank_pressure), 0.002, 1)

			var/datum/gas_mixture/leaked_gas = air_contents.remove_ratio(release_ratio)
			//dynamic air release based on ambient pressure

			T.assume_air(leaked_gas)
			if(!leaking)
				visible_message("[icon2html(src,viewers(src))] " + span_warning("\The [src] relief valve flips open with a hiss!"), "You hear hissing.")
				play_sfx(src, SFX_EFFECTS_SPRAY)
				set_leaking(TRUE)
				#ifdef FIREDBG
				log_world(span_warning("[x],[y] tank is leaking: [pressure] kPa, integrity [get_integrity()]"))
				#endif

		else
			tank_stress(10)

	else
		if(get_integrity() < max_integrity)
			repair_damage(leaking ? 20 : 10)
			if(get_integrity() >= max_integrity)
				set_leaking(FALSE)

/// Pressure and heat wear on the seal. Armour doesn't help a seal from the inside.
/obj/item/tank/proc/tank_stress(amount)
	take_damage(amount, BRUTE, null, FALSE)

/// A failed seal is a state, not a wreck: the tank keeps its gas until the next
/// pressure check ruptures or vents it. Fire and acid still destroy it.
/obj/item/tank/atom_destruction(damage_flag)
	if(damage_flag == FIRE || damage_flag == ACID)
		return ..()
	// A failed seal: pressure_watched() holds through seal_damaged (set by the integrity write).

/////////////////////////////////
///Prewelded tanks
/////////////////////////////////

/obj/item/tank/phoron/welded
	valve_welded = 1
/obj/item/tank/oxygen/welded
	valve_welded = 1

/////////////////////////////////
///Onetankbombs (added as actual items)
/////////////////////////////////

/obj/item/tank/proc/onetankbomb(fill = 1)
	var/phoron_amt = 4 + rand(4)
	var/oxygen_amt = 6 + rand(8)

	if(fill == 2)
		phoron_amt = 10
		oxygen_amt = 15
	else if (!fill)
		phoron_amt = 3
		oxygen_amt = 4.5

	src.air_contents.adjust_gas(GAS_PHORON, (phoron_amt) - LINDA_GAS_AMT(src.air_contents, GAS_PHORON))
	src.air_contents.adjust_gas(GAS_O2, (oxygen_amt) - LINDA_GAS_AMT(src.air_contents, GAS_O2))
	// update_values() removed; no-op under LINDA.
	src.valve_welded = 1
	heat_set(src.air_contents, PLASMA_MINIMUM_BURN_TEMPERATURE-1, HEAT_SOURCE_OTHER)

	src.wired = 1

	var/obj/item/assembly_holder/H = new(src)
	rel_set(src.proxyassembly, nameof(/obj/item/integrated_circuit::assembly), H)
	rel_set(H, nameof(H.master), src.proxyassembly)

	H.update_icon()

	add_overlay("bomb_assembly")

TYPE_TABLE_DECLARE(/obj/item/tank/phoron/onetankbomb, phoron_bomb_forced_fill, null)

CAPABILITIES(/obj/item/tank/phoron/onetankbomb)
	param(nameof(bomb_fill), pos = 1)

/// How full the bomb's tank is filled (its constructor param, or the type's forced fill).
/obj/item/tank/phoron/onetankbomb/var/bomb_fill = 1

// ALLOW(init/INSTANCE_STATE): a single-tank bomb is assembled and filled once its parents made its tank
/obj/item/tank/phoron/onetankbomb/Initialize(mapload)
	var/forced_fill = TYPE_TABLE_GET(src, phoron_bomb_forced_fill)
	if(!isnull(forced_fill))
		bomb_fill = forced_fill
	. = ..()
	onetankbomb(bomb_fill)

TYPE_TABLE_DECLARE(/obj/item/tank/oxygen/onetankbomb, oxygen_bomb_forced_fill, null)

CAPABILITIES(/obj/item/tank/oxygen/onetankbomb)
	param(nameof(bomb_fill), pos = 1)

/// How full the bomb's tank is filled (its constructor param, or the type's forced fill).
/obj/item/tank/oxygen/onetankbomb/var/bomb_fill = 1

// ALLOW(init/INSTANCE_STATE): a single-tank bomb is assembled and filled once its parents made its tank
/obj/item/tank/oxygen/onetankbomb/Initialize(mapload)
	var/forced_fill = TYPE_TABLE_GET(src, oxygen_bomb_forced_fill)
	if(!isnull(forced_fill))
		bomb_fill = forced_fill
	. = ..()
	onetankbomb(bomb_fill)

TYPE_TABLE(/obj/item/tank/phoron/onetankbomb/full, phoron_bomb_forced_fill, 2)

TYPE_TABLE(/obj/item/tank/oxygen/onetankbomb/full, oxygen_bomb_forced_fill, 2)

TYPE_TABLE(/obj/item/tank/phoron/onetankbomb/small, phoron_bomb_forced_fill, 0)

TYPE_TABLE(/obj/item/tank/oxygen/onetankbomb/small, oxygen_bomb_forced_fill, 0)

/////////////////////////////////
///Pulled from rewritten bomb.dm
/////////////////////////////////

/obj/item/tankassemblyproxy
	name = "Tank assembly proxy"
	desc = "Used as a stand in to trigger single tank assemblies... but you shouldn't see this."
	var/obj/item/tank/tank = null
	var/obj/item/assembly_holder/assembly = null
	item_flags = ABSTRACT

/obj/item/tankassemblyproxy/receive_signal()	//This is mainly called by the sensor through sense() to the holder, and from the holder to here.
	tank.ignite()	//boom (or not boom if you made shijwtty mix)

/obj/item/tank/proc/assemble_bomb(W,user)	//Bomb assembly proc. This turns assembly+tank into a bomb
	var/obj/item/assembly_holder/S = W
	var/mob/M = user
	if(!S.secured)										//Check if the assembly is secured
		return
	if(isigniter(S.a_left) == isigniter(S.a_right))		//Check if either part of the assembly has an igniter, but if both parts are igniters, then fuck it
		return

	M.drop_item()			//Remove the assembly from your hands
	M.remove_from_mob(src)	//Remove the tank from your character,in case you were holding it
	M.put_in_hands(src)		//Equips the bomb if possible, or puts it on the floor.

	rel_set(src.proxyassembly, nameof(/obj/item/integrated_circuit::assembly), S) //Tell the bomb about its assembly part
	rel_set(S, nameof(S.master), src.proxyassembly) //Tell the assembly about its new owner
	S.forceMove(src)			//Move the assembly

	src.update_icon()

	src.add_bomb_overlay()

	return

/obj/item/tank/proc/ignite()	//This happens when a bomb is told to explode

	var/obj/item/assembly_holder/assy = src.proxyassembly.assembly
	var/ign = assy.a_right
	var/obj/item/other = assy.a_left

	if (isigniter(assy.a_left))
		ign = assy.a_left
		other = assy.a_right

	other.dropInto(get_turf(src))
	destroyed(ign)
	rel_clear(assy, nameof(assy.master))
	rel_clear(src.proxyassembly, nameof(/obj/item/integrated_circuit::assembly))
	destroyed(assy)
	src.update_icon()
	src.update_gauge()

	heat_add(air_contents, 15000, HEAT_SOURCE_OTHER)

DECLARE_APPEARANCE_PROC(/obj/item/tankassemblyproxy, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/tankassemblyproxy/appearance_overlays()
	. = list()
	if(assembly)
		tank.update_icon()
		tank.add_overlay("bomb_assembly")
	else
		tank.update_icon()
		tank.cut_overlay("bomb_assembly")

/obj/item/tankassemblyproxy/HasProximity(turf/T, WF, old_loc)
	if(isnull(WF))
		return
	var/atom/movable/AM = WF
	if(isnull(AM))
		log_runtime("DEBUG: HasProximity called without reference on [src].")
		return
	assembly?.HasProximity(T, WF, old_loc)

/obj/item/tankassemblyproxy/Moved(old_loc, direction, forced)
	if(isturf(old_loc))
		unsense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity), center = old_loc)
	if(isturf(loc))
		sense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))

#undef TANK_IDEAL_PRESSURE

// The tank owns its proxy (implicit OWN); the proxy names the tank back (one-sided REL). The
// assembly holder sits in the tank's contents, so the proxy only names it (REL view).
