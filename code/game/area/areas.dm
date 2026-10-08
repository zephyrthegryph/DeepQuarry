// Areas.dm

GLOBAL_LIST_EMPTY(areas_by_type)

/area
	var/fire = null
	var/atmos = 1
	var/atmosalm = 0
	var/poweralm = 1
	var/party = null
	level = null
	name = "Unknown"
	icon = 'icons/turf/areas.dmi'
	icon_state = "unknown"
	plane = PLANE_LIGHTING_ABOVE //In case we color them
	luminosity = 0
	mouse_opacity = 0
	var/lightswitch = 1

	var/eject = null

	var/debug = 0
	var/requires_power = 1
	var/always_unpowered = 0	//this gets overriden to 1 for space in area/New()

	// Power channel status - Is it currently energized?
	var/power_equip = TRUE
	var/power_light = TRUE
	var/power_environ = TRUE

	// Oneoff power usage - Used once and cleared each power cycle
	var/oneoff_equip = 0
	var/oneoff_light = 0
	var/oneoff_environ = 0

	var/music = null
	var/has_gravity = TRUE // Don't check this var directly; use get_gravity() instead
	var/obj/machinery/power/apc/apc = null
	/// The APC runs night-shift lighting (derived from it; the lights read it).
	var/lights_nightshift = FALSE
	/// The APC switched emergency lighting off (derived from it; the lights read it).
	var/lights_emergency_off = FALSE
	var/no_air = null
	var/list/all_doors = null		//Added by Strumpetplaya - Alarm Change - Contains a list of doors adjacent to this area
	var/list/all_arfgs = null		//Similar, but a list of all arfgs adjacent to this area
	var/firedoors_closed = 0
	var/arfgs_active = 0
	var/list/ambience
	var/list/forced_ambience = null
	var/sound_env = STANDARD_STATION
	var/base_turf //The base turf type of the area, which can be used to override the z-level's base turf
	VAR_PROTECTED/color_grading = null // Color blending for clients that enter this area
TRACKED(/area, eject)
TRACKED(/area, fire)
TRACKED(/area, party)

/area/New()
	// Used by the maploader, this must be done in New, not init
	GLOB.areas_by_type[type] = src // ALLOW(registry): areas are immortal plain refs (never relation targets); the maploader looks them up by type in New(), before any registry join
	return ..()

/area/lifecycle_dematerialize()
	..()
	// Dynamically created areas must not remain pinned by the type lookup after
	// their turfs have been reassigned during map teardown.
	if(GLOB.areas_by_type[type] == src)
		GLOB.areas_by_type -= type

// ALLOW(init/FRAMEWORK): the area base of the init chain sets its ceiling and lighting
/area/Initialize(mapload)
	apply_ceiling()
	. = ..()
	luminosity = !(dynamic_lighting)
	icon_state = ""

/// An area's pass after the map load: its power state and spoiler cover, once its machines exist (area_after_init() is extended by the
/// away-mission spawns and the turf initializers).
/area/proc/area_after_init(datum/act/timer/A)
	if(!requires_power || !apc)
		set_channels(FALSE, FALSE, FALSE, notify = FALSE)
	power_change()		// all machines set to current power level, also updates lighting icon
	if(flag_check(AREA_NO_SPOILERS))
		set_spoiler_obfuscation(TRUE)

/// The one place a turf is moved between areas. Areas aren't ledger holders:
/// a turf's area is the engine's own area membership, so this is a raw
/// contents write by design. Callers still run their own lighting/power
/// follow-up (ChangeArea(), or turf.change_area()).
/turf/proc/assign_area(area/A)
	A.contents += src // ALLOW(containment): area membership of a turf, not containment

// Changes the area of T to A. Do not do this manually.
// Area is expected to be a non-null instance.
/proc/ChangeArea(turf/T, area/A)
	if(!istype(A))
		CRASH("Area change attempt failed: invalid area supplied.")
	var/area/old_area = get_area(T)
	if(old_area == A)
		return
	// NOTE: BayStation calles area.Exited/Entered for the TURF T.  So far we don't do that.s
	// NOTE: There probably won't be any atoms in these turfs, but just in case we should call these procs.
	T.assign_area(A)
	T.reactor_area_changed()
	if(old_area)
		// Handle dynamic lighting update if
		if(SSlighting.initialized && T.dynamic_lighting && old_area.dynamic_lighting != A.dynamic_lighting)
			if(A.dynamic_lighting)
				T.lighting_build_overlay()
			else
				T.lighting_clear_overlay()
		for(var/atom/movable/AM in turf_contents_of_type(T, /atom/movable))
			old_area.Exited(AM, A)
	for(var/atom/movable/AM in turf_contents_of_type(T, /atom/movable))
		A.Entered(AM, old_area)
	for(var/obj/machinery/M in turf_contents_of_type(T, /obj/machinery))
		M.area_changed(old_area, A)

/area/proc/get_contents()
	return contents

/area/proc/get_cameras()
	var/list/cameras = list()
	for (var/obj/machinery/camera/C in area_contents_of_type(src, /obj/machinery/camera))
		cameras += C
	return cameras

/area/proc/atmosalert(danger_level, alarm_source)
	// original used /obj/machinery/alarm (ZAS air alarm). LINDA's
	// air alarm is /tg/-vendored in code/atmospherics/machinery/air_alarm/
	// but not yet wired into the build. Until that lands, the proc behaves as a
	// pure-danger-level tracker without per-machine alarm-source aggregation.
	if (danger_level == 0)
		GLOB.atmosphere_alarm.clearAlarm(src, alarm_source)
	else
		GLOB.atmosphere_alarm.triggerAlarm(src, alarm_source, severity = danger_level)

	if(danger_level != atmosalm)
		atmosalm = danger_level
		//closing the doors on red and opening on green provides a bit of hysteresis that will hopefully prevent fire doors from opening and closing repeatedly due to noise
		if (danger_level < 1 || danger_level >= 2)
			firedoors_update()

		air_alarms_refresh()

		return 1
	return 0

// Either close or open firedoors and arfgs depending on current alert statuses
/area/proc/firedoors_update()
	if(fire || party || atmosalm)
		firedoors_close()
		arfgs_activate()
		if(fire)
			for(var/obj/machinery/light/L in area_contents_of_type(src, /obj/machinery/light))
				L.set_alert_fire()
		else if(atmosalm)
			for(var/obj/machinery/light/L in area_contents_of_type(src, /obj/machinery/light))
				L.set_alert_atmos()
	else
		firedoors_open()
		arfgs_deactivate()
		for(var/obj/machinery/light/L in area_contents_of_type(src, /obj/machinery/light))
			L.reset_alert()

// Close all firedoors in the area
/area/proc/firedoors_close()
	if(!firedoors_closed)
		firedoors_closed = TRUE
		if(!all_doors)
			return
		for(var/obj/machinery/door/firedoor/E in all_doors)
			if(!E.blocked)
				if(E.operating)
					E.nextstate = FIREDOOR_CLOSED
				else if(!E.density)
					E.close()

// Open all firedoors in the area
/area/proc/firedoors_open()
	if(firedoors_closed)
		firedoors_closed = FALSE
		if(!all_doors)
			return
		for(var/obj/machinery/door/firedoor/E in all_doors)
			if(!E.blocked)
				if(E.operating)
					E.nextstate = FIREDOOR_OPEN
				else if(E.density)
					E.open()

// atmospheric_field_generator (atm_ret_field.dm) was a ZAS-only machine.
// Without LINDA replacement these procs neutered; the area-level toggle still
// runs but with no machinery to drive. Re-implement against LINDA's air alarm
// system once that's wired.
/area/proc/arfgs_activate()
	arfgs_active = TRUE

/area/proc/arfgs_deactivate()
	arfgs_active = FALSE

/area/proc/fire_alert()
	if(!fire)
		set_fire(1)	//used for firedoor checks
		firedoors_update()

/area/proc/fire_reset()
	if (fire)
		set_fire(0)	//used for firedoor checks
		firedoors_update()

/area/proc/readyalert()
	if(!eject)
		set_eject(1)
	return

/area/proc/readyreset()
	if(eject)
		set_eject(0)
	return

/area/proc/partyalert()
	if (!( party ))
		set_party(1)
		firedoors_update()
	return

/area/proc/partyreset()
	if (party)
		set_party(0)
		firedoors_update()
	return

/area/draw(datum/look/look)
	..()
	if ((fire || eject || party) && (!requires_power||power_environ) && !istype(src, /area/space))//If it doesn't require power, can still activate this proc.
		if(fire && !eject && !party)
			look.state(null) // Let lights take care of it
		/*else if(atmosalm && !fire && !eject && !party)
			look.state("bluenew")*/
		else if(!fire && eject && !party)
			look.state("red")
		else if(party && !fire && !eject)
			look.state("party")
		else
			look.state("blue-red")
	else
	//	new lighting behaviour with obj lights
		look.state(null)

TRACKED(/area, power_equip)
TRACKED(/area, power_light)
TRACKED(/area, power_environ)
TRACKED(/area, requires_power)
TRACKED(/area, always_unpowered)

/// The one writer of the area's channel state (is each channel energized): its APC, an event that darkens the area, the area's own setup. The
/// machines in the area learn of a flip through power_change() (unless `notify` is FALSE: the caller runs it itself); the vars are tracked, so
/// what reads them as a stat input hears the write. Returns TRUE when a channel flipped.
/area/proc/set_channels(equip_on, light_on, environ_on, notify = TRUE)
	var/flipped = FALSE
	if(set_power_equip(!!equip_on))
		flipped = TRUE
	if(set_power_light(!!light_on))
		flipped = TRUE
	if(set_power_environ(!!environ_on))
		flipped = TRUE
	if(flipped && notify)
		power_change()
	return flipped

/area/proc/powered(chan)		// return true if the area has power to given channel

	if(!requires_power)
		return 1
	if(always_unpowered)
		return 0
	switch(chan)
		if(EQUIP)
			return power_equip
		if(LIGHT)
			return power_light
		if(ENVIRON)
			return power_environ

	return 0

/// The machines standing in this area: the other end of their power_area relation. Each contributes its draw to the demand stats and is told
/// about the channel changes (power_subscriber).
/area/var/list/power_machines

// Called once per area channel change (the APC's Rust power event). Lights and
// other reactor subscribers hear the key; subscribed machines re-check their
// power, and the base power_change() emits machinery_power_lost or
// machinery_power_restored when it flips.
/area/proc/power_change()
	changed(src, CHANGE_AREA_POWER)
	// The machines' has_power is a read of this area's channels (area_gives_power()): settle it now, whatever wrote the channel vars (the tracked
	// writer marks the same stat for a later drain, which then finds it unchanged), so power_change() below acts on a current reading.
	var/datum/stat_def/power_def = stat_def_of(STAT_HAS_POWER)
	for(var/obj/machinery/M as anything in power_machines)
		if(M.power_subscriber)
			stat_settle_def(M, power_def)
	for(var/obj/machinery/M as anything in power_machines)
		if(M.power_subscriber)
			M.power_change()

/// Watts the area's machines ask of `chan` (the standing draw, the sum of their contributions) plus the one-off draws booked since the last
/// power step. `include_static` FALSE leaves the standing draw out.
/area/proc/usage(chan, include_static = TRUE)
	var/used = 0
	switch(chan)
		if(LIGHT)
			used += oneoff_light + (include_static ? demand(LIGHT) : 0)
		if(EQUIP)
			used += oneoff_equip + (include_static ? demand(EQUIP) : 0)
		if(ENVIRON)
			used += oneoff_environ + (include_static ? demand(ENVIRON) : 0)
		if(TOTAL)
			used += usage(LIGHT, include_static) + usage(EQUIP, include_static) + usage(ENVIRON, include_static)
	return used

/// The standing draw of the area's machines on `chan`: the area's demand stat, the sum of every machine's contribution.
/area/proc/demand(chan)
	switch(chan)
		if(LIGHT)
			return stat_value(src, STAT_DEMAND_LIGHT)
		if(EQUIP)
			return stat_value(src, STAT_DEMAND_EQUIP)
		if(ENVIRON)
			return stat_value(src, STAT_DEMAND_ENVIRON)
	return 0

// Helper for APCs; will generally be called every tick.
/area/proc/clear_usage()
	oneoff_equip = 0
	oneoff_light = 0
	oneoff_environ = 0

// Use this for a one-time power draw from the area, typically for non-machines.
/area/proc/use_power_oneoff(amount, chan)
	switch(chan)
		if(EQUIP)
			oneoff_equip += amount
		if(LIGHT)
			oneoff_light += amount
		if(ENVIRON)
			oneoff_environ += amount
	if(amount)
		power_loads_changed()
		changed(src, CHANGE_AREA_POWER)
	return amount

/// The lights standing in the area (a copy; the fixtures are among the machines that name it as their power_area).
/area/proc/lights_here()
	var/list/found = list()
	for(var/obj/machinery/light/L in power_machines)
		found += L
	return found

//////////////////////////////////////////////////////////////////

/area/Entered(atom/movable/AM, oldLoc)
	. = ..()
	if(enter_message && isliving(AM))
		to_chat(AM, enter_message)

	var/mob/M = AM
	if(!ismob(M) || !M.ckey)
		return

	if(!isliving(M))
		M.lastarea = src
		return

	var/mob/living/L = M
	if(!L.lastarea)
		L.lastarea = src
	var/area/oldarea = L.lastarea
	if((oldarea.get_gravity() == 0) && (get_gravity() == 1) && (L.m_intent == I_RUN)) // Being ready when you change areas gives you a chance to avoid falling all together.
		thunk(L)
		L.update_floating( L.Check_Dense_Object() )

	L.lastarea = src
	EXPIRY_STAMP(L, lastareachange, CLOCK_WORLD)
	play_ambience(L, initial = TRUE)
	if(flag_check(AREA_NO_SPOILERS))
		L.disable_spoiler_vision()
	check_phase_shift(M)

	// Update the area's color grading
	if(L.client && L.client.color != get_color_tint()) // Try to check if we should bother changing before doing blending
		L.update_client_color()

/area/proc/play_ambience(mob/living/L, initial = TRUE)
	// Ambience goes down here -- make sure to list each area seperately for ease of adding things in later, thanks! Note: areas adjacent to each other should have the same sounds to prevent cutoff when possible.- LastyScratch
	if(!L?.read_preference(/datum/preference/toggle/play_ambience))
		return

	var/volume_mod = L.get_preference_volume_channel(VOLUME_CHANNEL_AMBIENCE)

	// If we previously were in an area with force-played ambiance, stop it.
	if((L in REGISTRY_MEMBERS(REGISTRY_FORCED_AMBIANCE)) && initial)
		L << sound(null, channel = CHANNEL_AMBIENCE_FORCED)
		registry_leave(REGISTRY_FORCED_AMBIANCE, L)

	if(forced_ambience)
		if(L in REGISTRY_MEMBERS(REGISTRY_FORCED_AMBIANCE))
			return
		if(forced_ambience.len)
			registry_join(REGISTRY_FORCED_AMBIANCE, L)
			var/sound/chosen_ambiance = pick(forced_ambience)
			if(!istype(chosen_ambiance))
				chosen_ambiance = sound(chosen_ambiance, repeat = 1, wait = 0, volume = 25, channel = CHANNEL_AMBIENCE_FORCED)
			chosen_ambiance.volume *= volume_mod
			L << chosen_ambiance
		else
			L << sound(null, channel = CHANNEL_AMBIENCE_FORCED)
	else if(src.ambience && length(src.ambience))
		var/ambience_odds = L.read_preference(/datum/preference/numeric/ambience_chance)
		if(prob(ambience_odds) && (COOLDOWN_FINISHED(L.client, ambience_cooldown)))
			var/sound = DEFAULTPICK(ambience, null)
			L << sound(sound, repeat = 0, wait = 0, volume = 50 * volume_mod, channel = CHANNEL_AMBIENCE)
			COOLDOWN_START(L.client, ambience_cooldown, 1 MINUTE)

/area/proc/gravitychange(gravitystate = 0)
	src.has_gravity = gravitystate

	for(var/mob/M in area_contents_of_type(src, /mob))
		if(get_gravity())
			thunk(M)
		M.update_floating( M.Check_Dense_Object() )
		M.update_gravity(get_gravity())

/area/proc/thunk(mob)
	if(istype(get_turf(mob), /turf/space)) // Can't fall onto nothing.
		return

	if(ishuman(mob))
		var/mob/living/carbon/human/H = mob
		if(H?.buckled_to())
			return // Being buckled to something solid keeps you in place.
		if(istype(H.get_equipped_item(SLOT_ID_SHOES), /obj/item/clothing/shoes/magboots) && (H.get_equipped_item(SLOT_ID_SHOES).item_flags & NOSLIP))
			return
		if(H.is_incorporeal()) // Phaseshifted beings should not be affected by gravity
			return
		if(H.species.can_zero_g_move || H.species.can_space_freemove)
			return

		if(H.m_intent == I_RUN)
			H.status_adjust(STAT_STUNNED, 1) // No longer a supermassive long stun.
// H.AdjustWeakened(6) // No longer weakens.
		else
			H.status_adjust(STAT_STUNNED, 1) // No longer a supermassive long stun.
// H.AdjustWeakened(3) // No longer weakens.
		to_chat(mob, span_notice("The sudden appearance of gravity makes you fall to the floor!"))
		if(has_trait(H, TRAIT_UNLUCKY) && prob(50) && H.get_bodypart_name(BP_HEAD))
			act_message(H, null, MSG_SELF(span_warning("You smash your head into the ground as gravity appears!")), \
				MSG_OTHERS(span_warning("%U% falls to the ground from the sudden appearance of gravity, smashing %THEIR% head against the ground!")))
			H.injure(INJURY_BLUNT, 14, BP_HEAD, src)
			play_sfx(H, SFX_EFFECTS_TABLEHEADSMASH)
		play_sfx(mob, SFX_BODYFALL)

/area/proc/prison_break(break_lights = TRUE, open_doors = TRUE, open_blast_doors = FALSE) //set blast doors to FALSE
	var/obj/machinery/power/apc/theAPC = get_apc()
	if(theAPC && theAPC.operating)
		if(break_lights)
			for(var/obj/machinery/power/apc/temp_apc in area_contents_of_type(src, /obj/machinery/power/apc))
				temp_apc.overload_lighting(70)
		if(open_doors)
			for(var/obj/machinery/door/airlock/temp_airlock in area_contents_of_type(src, /obj/machinery/door/airlock))
				temp_airlock.prison_open()
			for(var/obj/machinery/door/window/temp_windoor in area_contents_of_type(src, /obj/machinery/door/window))
				temp_windoor.open()
		if(open_blast_doors)
			for(var/obj/machinery/door/blast/temp_blast in area_contents_of_type(src, /obj/machinery/door/blast))
				temp_blast.open()

/area/get_gravity()
	return has_gravity

/area/space/get_gravity()
	return 0

/proc/get_gravity(atom/AT, turf/T)
	if(!T)
		T = get_turf(AT)
	var/area/A = get_area(T)
	if(A && A.get_gravity())
		return 1
	return 0

/area/proc/shuttle_arrived()
	return TRUE

/area/proc/shuttle_departed()
	return TRUE

/area/AllowDrop()
	CRASH("Bad op: area/AllowDrop() called")

/area/drop_location()
	CRASH("Bad op: area/drop_location() called")

/*Adding a wizard area teleport list because motherfucking lag -- Urist*/
/*I am far too lazy to make it a proper list of areas so I'll just make it run the usual telepot routine at the start of the game*/
GLOBAL_LIST_EMPTY(teleportlocs)

/hook/startup/proc/setupTeleportLocs()
	for(var/area/AR in world)
		if(istype(AR, /area/shuttle) || istype(AR, /area/syndicate_station) || istype(AR, /area/wizard_station)) continue
		if(GLOB.teleportlocs.Find(AR.name)) continue
		var/turf/picked = pick(get_area_turfs(AR.type))
		if (picked.z in using_map.station_levels)
			GLOB.teleportlocs += AR.name
			GLOB.teleportlocs[AR.name] = AR

	GLOB.teleportlocs = sortAssoc(GLOB.teleportlocs)

	return 1

GLOBAL_LIST_EMPTY(ghostteleportlocs)

/hook/startup/proc/setupGhostTeleportLocs()
	for(var/area/AR in world)
		if(GLOB.ghostteleportlocs.Find(AR.name)) continue
		if(istype(AR, /area/aisat) || istype(AR, /area/derelict) || istype(AR, /area/tdome) || istype(AR, /area/shuttle/specops/centcom))
			GLOB.ghostteleportlocs += AR.name
			GLOB.ghostteleportlocs[AR.name] = AR
		var/turf/picked = pick(get_area_turfs(AR.type))
		if (picked.z in using_map.player_levels)
			GLOB.ghostteleportlocs += AR.name
			GLOB.ghostteleportlocs[AR.name] = AR

	GLOB.ghostteleportlocs = sortAssoc(GLOB.ghostteleportlocs)

	return 1

/area/proc/get_name()
	if(flag_check(AREA_SECRET_NAME))
		return "Unknown Area"
	return name

GLOBAL_DATUM(spoiler_obfuscation_image, /image)

/area/proc/set_spoiler_obfuscation(should_obfuscate)
	if(!GLOB.spoiler_obfuscation_image)
		GLOB.spoiler_obfuscation_image = image(icon = 'icons/misc/static.dmi')
		GLOB.spoiler_obfuscation_image.plane = PLANE_MESONS

	if(should_obfuscate)
		add_overlay(GLOB.spoiler_obfuscation_image)
	else
		cut_overlay(GLOB.spoiler_obfuscation_image)

/area/proc/flag_check(flag, match_all = FALSE)
	if(match_all)
		return (flags & flag) == flag
	return flags & flag

/area/proc/check_phase_shift(mob/living/ourmob)
	if(!flag_check(AREA_BLOCK_PHASE_SHIFT) || !ourmob.is_incorporeal())
		return
	if(!isliving(ourmob))
		return
	if(check_rights_for(ourmob.client, R_HOLDER)) //If we're an admin, we don't get affected by phase blockers.
		return
	var/datum/shadekin/SK = ourmob.get_shadekin_state()
	if(SK && SK.in_phase)
		SK.attack_dephase(ourmob.loc, src)

/area/proc/isAlwaysIndoors()
	return FALSE

/area/shuttle/isAlwaysIndoors()
	return TRUE

/area/turbolift/isAlwaysIndoors()
	return TRUE

/// Gets a hex color value for blending with a player's client.color. Allows for primitive color grading per area.
/area/proc/get_color_tint()
	SHOULD_CALL_PARENT(TRUE)
	return color_grading


// === merged from areas_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/area
	var/enter_message
	var/exit_message
	var/ceiling_type

	// Size of the area in open turfs, only calculated for indoors areas.
	var/areasize = 0

	var/no_comms = FALSE	//When true, blocks radios from working in the area

/area/Exited(atom/movable/AM, newLoc)
	. = ..()
	if(exit_message && isliving(AM))
		to_chat(AM, exit_message)

/area/proc/apply_ceiling()
	if(!ceiling_type)
		return
	for(var/turf/T in contents)
		if(T.is_outdoors() >= 0)
			continue
		if(HasAbove(T.z))
			var/turf/TA = GetAbove(T)
			if(isopenspace(TA))
				TA.ChangeTurf(ceiling_type, TRUE, TRUE, TRUE)

/**
 * Setup an area (with the given name)
 *
 * Sets the area name, sets all status var's to false and adds the area to the sorted area list
 * //NOTE: Virgo does not have a sorted area list.
 */
/area/proc/setup(a_name)
	name = a_name
	set_channels(FALSE, FALSE, FALSE, notify = FALSE)
	set_always_unpowered(FALSE)
	update_areasize()

/area/proc/update_areasize()
	if(outdoors)
		return FALSE
	areasize = 0
	for(var/turf/simulated/floor/T in contents)
		areasize++

/proc/rename_area(a, new_name)
	var/area/A = get_area(a)
	var/prevname = "[A.name]"
	set_area_machinery(A, new_name, prevname)
	A.name = new_name
	A.update_areasize()
	return TRUE

/area/proc/power_check()
	if(!requires_power || !apc)
		set_channels(FALSE, FALSE, FALSE, notify = FALSE)
	power_change()		// all machines set to current power level, also updates lighting icon
	if(flag_check(AREA_NO_SPOILERS))
		set_spoiler_obfuscation(TRUE)

/// The area's APC is the other end of the APC's `area` link (links() in the APC's CAPABILITIES): rel_set() on either end writes both, and a
/// dying APC lets go. The APC also feeds the area's lights_nightshift and lights_emergency_off (its contributes_to entries).
/// A new APC (or none) serves the area: its Rust node takes the area's static loads.
CAPABILITIES(/area)
	after_init(0, then(PROC_REF(area_after_init)))
	ref_one(nameof(main_air_alarm), /obj/machinery/alarm)
	on_change(nameof(apc), ANY, then(PROC_REF(apc_changed)))
	on_change(STAT_DEMAND_EQUIP, ANY, then(PROC_REF(demand_changed)))
	on_change(STAT_DEMAND_LIGHT, ANY, then(PROC_REF(demand_changed)))
	on_change(STAT_DEMAND_ENVIRON, ANY, then(PROC_REF(demand_changed)))

/area/proc/apc_changed(datum/act/A)
	power_loads_changed()

/// What the area's machines ask of a channel changed: its APC takes the new load at the next power step.
/area/proc/demand_changed(datum/act/A)
	power_loads_changed()
	changed(src, CHANGE_AREA_POWER)
