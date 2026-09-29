//
/*
- Specific department maintenance doors
- Named doors properly according to type
- Gave them default access levels with the access constants
- Improper'd all of the names in the new()
*/

// Airlock-local entry key: the stance-declared ctrl-click entries (hammer on the door in combat mode,
// hold it open with Grab) run from click_ctrl().
#define AIRLOCK_ENTRY_CTRL "airlock_ctrl"

/obj/machinery/door/airlock
	name = "Airlock"
	icon = 'icons/obj/doors/doorint.dmi'
	icon_state = "door_closed"
	power_channel = ENVIRON

	explosion_resistance = 10

	// Doors do their own stuff

	blocks_emissive = EMISSIVE_BLOCK_GENERIC // Not quite as nice as /tg/'s custom masks. We should make those sometime

	tgui_id = "AiAirlock"
	var/aiControlDisabled = 0 //If 1, AI control is disabled until the AI hacks back in and disables the lock. If 2, the AI has bypassed the lock. If -1, the control is enabled but the AI had bypassed it earlier, so if it is disabled again the AI would have no trouble getting back in.
	var/hackProof = 0 // if 1, this door can't be hacked by the AI
	/// 0: not electrified. 1: electrified for a while (timed_set() reverts it: time_left()). -1: until someone fixes it.
	var/electrified_until = 0
	/// 0: main power on. 1: lost for a while (timed_set() restores it). -1: lost until the cables are mended.
	var/main_power_lost_until = 0
	/// 0: backup power carrying the door. 1: out for a while (timed_set()). -1: standing by, or cut.
	var/backup_power_lost_until = -1
	var/has_beeped = 0					//If 1, will not beep on failed closing attempt. Resets when door closes.
	var/lights = 1 // bolt lights show by default
	var/aiDisabledIdScanner = 0
	var/aiHacking = FALSE
	var/obj/machinery/door/airlock/closeOther
	var/closeOtherId = null
	var/lockdownbyai = 0
	autoclose = 1
	var/assembly_type = /obj/structure/door_assembly
	var/mineral = null
	/// A second between shocks from bumping it.
	COOLDOWN_DECLARE(bump_zap_cooldown)
	var/safe = 1
	normalspeed = 1
	silicon_use = SILICON_USE_UI
	var/obj/item/airlock_electronics/electronics = null
	COOLDOWN_DECLARE(hasShocked) //Prevents multiple shocks from happening
	var/secured_wires = 0
	var/security_level = 1 //Acts as a multiplier on the time required to hack an airlock with a hacktool

	var/open_sound_powered = 'sound/machines/door/covert1o.ogg'
	var/open_sound_unpowered = 'sound/machines/door/airlockforced.ogg'
	var/close_sound_powered = 'sound/machines/door/covert1c.ogg'
	var/legacy_open_powered = 'sound/machines/door/old_airlock.ogg'
	var/legacy_close_powered = 'sound/machines/door/old_airlockclose.ogg'
	var/department_open_powered = null
	var/department_close_powered = null
	var/denied_sound = SFX_MACHINES_DENIEDBEEP
	var/bolt_up_sound = SFX_MACHINES_DOOR_BOLTSUP
	var/bolt_down_sound = SFX_MACHINES_DOOR_BOLTSDOWN
	var/knock_sound = SFX_MACHINES_2BEEPLOW
	var/knock_hammer_sound = SFX_WEAPONS_SONIC_JACKHAMMER
	var/knock_unpowered_sound = SFX_MACHINES_DOOR_KNOCK_GLASS
	var/mob/hold_open
	rad_insulation = RAD_MEDIUM_INSULATION
	rad_shield_material = MAT_STEEL
	rad_shield_thickness_mm = RAD_AIRLOCK_THICKNESS_MM

	// Frozen airlocks and how to deice them
	var/frozen = FALSE
	var/next_weather_check = 0
	var/static/list/deicing_tools = list(
		/obj/item/ice_pick = 3,
		/obj/item/tool/crowbar = 5,
		/obj/item/pen = 30,
		/obj/item/card = 35,
		/obj/item/tool = 10,
		/obj/item = 12,
	)

/obj/machinery/door/airlock/attack_generic(mob/living/user, damage)
	if(!operable())
		if(damage >= STRUCTURE_MIN_DAMAGE_THRESHOLD)
			if(is_bolted(src) || is_welded(src))
				act_message(user, src, others = span_danger("%U% begins breaking into %T% internals!"))
				om_task_timed(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_generic_timed_done), done_args = list(user), busy = user)
			else if(density)
				act_message(user, src, others = span_danger("%U% forces %T% open!"))
				open(TRUE)
			else
				act_message(user, src, others = span_danger("%U% forces %T% closed!"))
				close(1)
		else
			act_message(user, src, others = span_notice("%U% strains fruitlessly to force %T% [density ? "open" : "closed"]."))
		return
	..()

/obj/machinery/door/airlock/proc/attack_generic_timed_done(mob/living/user)
	cap_set(src, CAP_BOLTED | CAP_WELDED, FALSE)
	open(TRUE)
	if(prob(25))
		shock(user, 100)

/obj/machinery/door/airlock/attack_alien(mob/user) //Familiar, right? Doors. -Mechoid
	if(!ishuman(user))
		return ..()
	var/mob/living/carbon/human/X = user
	if(istype(X.species, /datum/species/xenos))
		if(is_bolted(src) || is_welded(src))
			act_message(user, src, others = span_alium("%U% begins tearing into %T% internals!"))
			do_animate("deny")
			om_task_timed(user, 15 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_alien_timed_done), done_args = list(user), busy = user)
		else if(density)
			act_message(user, src, others = span_alium("%U% begins forcing %T% open!"))
			om_task_timed(user, 5 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_alien_timed_done2), done_args = list(user), busy = user)
		else
			act_message(user, src, others = span_danger("%U% forces %T% closed!"))
			close(1)
	else
		do_animate("deny")
		act_message(user, src, others = span_notice("%U% strains fruitlessly to force %T% [density ? "open" : "closed"]."))
		return

/obj/machinery/door/airlock/proc/attack_alien_timed_done(mob/user)
	act_message(user, src, others = span_danger("%U% tears %T% open, sparks flying from its electronics!"))
	do_animate("spark")
	play_sfx(src, SFX_MACHINES_DOOR_AIRLOCK_TEAR_APART, volume_channel = VOLUME_CHANNEL_DOORS)
	cap_set(src, CAP_BOLTED | CAP_WELDED, FALSE)
	open(TRUE)
	atom_break() //These aren't emags, these be CLAWS
/obj/machinery/door/airlock/proc/attack_alien_timed_done2(mob/user)
	play_sfx(src, SFX_MACHINES_DOOR_AIRLOCK_CREAKING, volume_channel = VOLUME_CHANNEL_DOORS)
	act_message(user, src, others = span_danger("%U% forces %T% open!"))
	open(TRUE)

/obj/machinery/door/airlock/get_material()
	if(mineral)
		return get_material_by_name(mineral)
	return get_material_by_name(MAT_STEEL)

// Power loss and electrification are timed_set() values (they restore themselves through their
// setters); the door's own deadline timer only keeps autoclose.
/obj/machinery/door/airlock/door_deadlines_due()
	if(close_door_at && !density && !operating && (is_bolted(src) || is_welded(src) || !arePowerSystemsOn() || wire_cut(WIRE_OPEN_DOOR)))
		close_door_at = 0
	return ..()

/// Raises CHANGE_MACHINE_MODE for whatever watches this door (bolts, power, electrification).
/obj/machinery/door/airlock/proc/publish_door_mode()
	om_changed(src, CHANGE_MACHINE_MODE)

// Runs in a seperate timer loop, because making every airlock process every tick just to check for unfreezing is a bad idea.
// Only the airlocks that can freeze (can_freeze()) declare it.
DECLARE_REPEAT(/obj/machinery/door/airlock/external, "freeze_check_delay", check_for_freeze, null)
DECLARE_REPEAT(/obj/machinery/door/airlock/glass_external, "freeze_check_delay", check_for_freeze, null)

/obj/machinery/door/airlock/proc/freeze_check_delay()
	return rand(10, 20) SECONDS

/obj/machinery/door/airlock/proc/check_for_freeze()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	// We don't freeze so none of this matters
	if(!can_freeze())
		return REPEAT_STOP

	// If we are not on a planet don't bother checking again. We physically cannot be outdoors. Except shuttles...
	var/area/our_area = get_area(src)
	var/turf/our_turf = get_turf(src)
	if(!our_turf || (!istype(our_area, /area/shuttle) && (our_turf.z > length(GLOB.planet_service.z_to_planet) || !GLOB.planet_service.z_to_planet[our_turf.z])))
		return REPEAT_STOP

	// Don't do anything if we are changing states
	if(!operating)
		// Door must be facing the outdoors and the temp of the air must be low enough
		var/planet_temp = T20C
		for(var/check_dir in GLOB.cardinal)
			var/turf/ground = get_step(our_turf, check_dir)
			if(ground.density || !ground.is_outdoors() || isspace(ground))
				continue
			var/datum/gas_mixture/gas_mix = ground.return_air()
			if(gas_mix.return_temperature() < planet_temp)
				planet_temp = gas_mix.return_temperature()

		// Check if we're in freezing weather, if above 0 start melting instead
		if(planet_temp < (T0C - 15))
			if(!frozen && density && prob(planet_temp < (T0C - 25) ? 20 : 5)) // Higher chance of freezing if temp is super low
				freeze()
		// Above 0 to have any chance at unfreezing
		else if(planet_temp > T0C)
			if(frozen && prob(20))
				unFreeze()

/*
About the new airlock wires panel:
*	An airlock wire dialog can be accessed by the normal way or by using wirecutters or a multitool on the door while the wire-panel is open. This would show the following wires, which you can either wirecut/mend or send a multitool pulse through. There are 9 wires.
*		one wire from the ID scanner. Sending a pulse through this flashes the red light on the door (if the door has power). If you cut this wire, the door will stop recognizing valid IDs. (If the door has 0000 access, it still opens and closes, though)
*		two wires for power. Sending a pulse through either one causes a breaker to trip, disabling the door for 10 seconds if backup power is connected, or 1 minute if not (or until backup power comes back on, whichever is shorter). Cutting either one disables the main door power, but unless backup power is also cut, the backup power re-powers the door in 10 seconds. While unpowered, the door may be open, but bolts-raising will not work. Cutting these wires may electrocute the user.
*		one wire for door bolts. Sending a pulse through this drops door bolts (whether the door is powered or not) or raises them (if it is). Cutting this wire also drops the door bolts, and mending it does not raise them. If the wire is cut, trying to raise the door bolts will not work.
*		two wires for backup power. Sending a pulse through either one causes a breaker to trip, but this does not disable it unless main power is down too (in which case it is disabled for 1 minute or however long it takes main power to come back, whichever is shorter). Cutting either one disables the backup door power (allowing it to be crowbarred open, but disabling bolts-raising), but may electocute the user.
*		one wire for opening the door. Sending a pulse through this while the door has power makes it open the door if no access is required.
*		one wire for AI control. Sending a pulse through this blocks AI control for a second or so (which is enough to see the AI control light on the panel dialog go off and back on again). Cutting this prevents the AI from controlling the door unless it has hacked the door through the power connection (which takes about a minute). If both main and backup power are cut, as well as this wire, then the AI cannot operate or hack the door at all.
*		one wire for electrifying the door. Sending a pulse through this electrifies the door for 30 seconds. Cutting this wire electrifies the door, so that the next person to touch the door without insulated gloves gets electrocuted. (Currently it is also STAYING electrified until someone mends the wire)
*		one wire for controling door safetys.  When active, door does not close on someone.  When cut, door will ruin someone's shit.  When pulsed, door will immedately ruin someone's shit.
*		one wire for controlling door speed.  When active, dor closes at normal rate.  When cut, door does not close manually.  When pulsed, door attempts to close every tick.
*/

/obj/machinery/door/airlock/bumpopen(mob/living/user) //Airlocks now zap you when you 'bump' them open when they're electrified. --NeoFite
	if(!issilicon(user))
		if(isElectrified())
			if(COOLDOWN_FINISHED(src, bump_zap_cooldown))
				if(shock(user, 100))
					COOLDOWN_START(src, bump_zap_cooldown, 1 SECOND)
					return
			else
				return
		else if(user.status_units(EFFECT_HALLUCINATING) > 50 && prob(10) && operating == 0)
			to_chat(user, span_danger("You feel a powerful shock course through your body!"))
			user.playsound_local(get_turf(user), get_sfx(SFX_SPARKS), vol = 75)
			user.injure(INJURY_PAIN, 10, null, src)
			user.status_adjust(EFFECT_STUNNED, 10)
			return
	..(user)

/obj/machinery/door/airlock/proc/isElectrified()
	if(electrified_until != 0)
		return TRUE
	return FALSE

// cap_electrify() (code/datums/capabilities/library/doors.dm) reads these.
/obj/machinery/door/airlock/is_electrified()
	return isElectrified()

/obj/machinery/door/airlock/electrified_left()
	if(electrified_until <= 0)
		return electrified_until
	return round(time_left(src, nameof(electrified_until)) / 10, 1)

/obj/machinery/door/airlock/proc/canAIControl()
	return ((aiControlDisabled!=1) && (!isAllPowerLoss()));

/obj/machinery/door/airlock/proc/canAIHack()
	return ((aiControlDisabled==1) && (!hackProof) && (!isAllPowerLoss()));

/obj/machinery/door/airlock/proc/arePowerSystemsOn()
	if (!operable())
		return FALSE
	return (main_power_lost_until==0 || backup_power_lost_until==0)

/obj/machinery/door/airlock/requiresID()
	return !(wire_cut(WIRE_IDSCAN) || aiDisabledIdScanner)

/obj/machinery/door/airlock/proc/isAllPowerLoss()
	if(!operable())
		return TRUE
	if(mainPowerCablesCut() && backupPowerCablesCut())
		return TRUE
	return FALSE

/// Whether `wire` is cut. A door whose wires were never touched has none cut (the wires capability
/// makes its datum on first use, under its type key).
/obj/machinery/door/airlock/proc/wire_cut(wire)
	var/datum/wires/W = cap_data?[/datum/capability/wires]
	return W ? W.is_cut(wire) : FALSE

/obj/machinery/door/airlock/wires_type_for(default_type)
	return secured_wires ? /datum/wires/airlock/secure : default_type

/obj/machinery/door/airlock/proc/mainPowerCablesCut()
	return wire_cut(WIRE_MAIN_POWER1) || wire_cut(WIRE_MAIN_POWER2)

/obj/machinery/door/airlock/proc/backupPowerCablesCut()
	return wire_cut(WIRE_BACKUP_POWER1) || wire_cut(WIRE_BACKUP_POWER2)

/// The main power setter (timed_set() restores through it): restoring with a cut cable stays lost
/// until the cable is mended, and backup power stands down once main power is back.
/obj/machinery/door/airlock/proc/set_main_power_lost_until(value)
	if(!value && mainPowerCablesCut())
		value = -1
	if(main_power_lost_until == value)
		return FALSE
	main_power_lost_until = value
	if(!value && !backup_power_lost_until)
		set_backup_power_lost_until(-1)
	resume_autoclose_if_possible()
	changed(src)
	publish_door_mode()
	return TRUE

/// The backup power setter: restoring it carries the door only while main power is out; with a cut
/// cable, or main power back, it stands by (-1).
/obj/machinery/door/airlock/proc/set_backup_power_lost_until(value)
	if(!value && (backupPowerCablesCut() || !main_power_lost_until))
		value = -1
	if(backup_power_lost_until == value)
		return FALSE
	backup_power_lost_until = value
	resume_autoclose_if_possible()
	changed(src)
	publish_door_mode()
	return TRUE

/// The electrification setter: a timed electrification that runs out on a door whose electrify wire
/// is cut stays electrified.
/obj/machinery/door/airlock/proc/set_electrified_until(value)
	if(!value && wire_cut(WIRE_ELECTRIFY) && arePowerSystemsOn())
		value = -1
	if(electrified_until == value)
		return FALSE
	electrified_until = value
	changed(src)
	publish_door_mode()
	return TRUE

/obj/machinery/door/airlock/proc/loseMainPower()
	if(mainPowerCablesCut())
		timed_cancel(src, nameof(main_power_lost_until))
		set_main_power_lost_until(-1)
	else
		timed_set(src, nameof(main_power_lost_until), 1, for_time = 1 MINUTE, clock = CLOCK_WORLD, revert_to = 0)

	// If backup power is permanently disabled then activate in 10 seconds if possible, otherwise it's already enabled or a timer is already running
	if(backup_power_lost_until == -1 && !backupPowerCablesCut())
		timed_set(src, nameof(backup_power_lost_until), 1, for_time = 10 SECONDS, clock = CLOCK_WORLD, revert_to = 0)

	// Disable electricity if required
	if(electrified_until && isAllPowerLoss())
		electrify(0)

/obj/machinery/door/airlock/proc/loseBackupPower()
	if(backupPowerCablesCut())
		timed_cancel(src, nameof(backup_power_lost_until))
		set_backup_power_lost_until(-1)
	else
		timed_set(src, nameof(backup_power_lost_until), 1, for_time = 1 MINUTE, clock = CLOCK_WORLD, revert_to = 0)

	// Disable electricity if required
	if(electrified_until && isAllPowerLoss())
		electrify(0)

/obj/machinery/door/airlock/proc/regainMainPower()
	timed_cancel(src, nameof(main_power_lost_until))
	set_main_power_lost_until(0)

/obj/machinery/door/airlock/proc/regainBackupPower()
	timed_cancel(src, nameof(backup_power_lost_until))
	set_backup_power_lost_until(0)

/obj/machinery/door/airlock/proc/resume_autoclose_if_possible()
	if(autoclose && !density && !operating && !is_bolted(src) && !is_welded(src) && arePowerSystemsOn() && !wire_cut(WIRE_OPEN_DOOR))
		autoclose_in(next_close_wait())

/// Electrifies the door for `duration` seconds (-1: until fixed, 0: stops). feedback tells `user`.
/obj/machinery/door/airlock/proc/electrify(duration, feedback = FALSE, mob/user)
	var/message = ""
	var/mob/actor = user || usr // the wires window still calls this without a user
	if(wire_cut(WIRE_ELECTRIFY) && arePowerSystemsOn())
		message = "The electrification wire is cut - Door permanently electrified."
		timed_cancel(src, nameof(electrified_until))
		set_electrified_until(-1)
	else if(duration && !arePowerSystemsOn())
		message = "The door is unpowered - Cannot electrify the door."
		timed_cancel(src, nameof(electrified_until))
		set_electrified_until(0)
	else if(!duration && electrified_until != 0)
		message = "The door is now un-electrified."
		timed_cancel(src, nameof(electrified_until))
		set_electrified_until(0)
	else if(duration)	//electrify door for the given duration seconds
		if(actor)
			shockedby += "\[[time_stamp()]\] - [actor](ckey:[actor.ckey])"
			add_attack_logs(actor, src, "Electrified a door")
		else
			shockedby += "\[[time_stamp()]\] - EMP)"
		message = "The door is now electrified [duration == -1 ? "permanently" : "for [duration] second\s"]."
		if(duration == -1)
			timed_cancel(src, nameof(electrified_until))
			set_electrified_until(-1)
		else
			timed_set(src, nameof(electrified_until), 1, for_time = duration SECONDS, clock = CLOCK_WORLD, revert_to = 0)

	if(feedback && message && actor)
		to_chat(actor, message)

/obj/machinery/door/airlock/proc/set_idscan(activate, feedback = FALSE, mob/user)
	var/message = ""
	if(wire_cut(WIRE_IDSCAN))
		message = "The IdScan wire is cut - IdScan feature permanently disabled."
	else if(activate && aiDisabledIdScanner)
		aiDisabledIdScanner = 0
		message = "IdScan feature has been enabled."
	else if(!activate && !aiDisabledIdScanner)
		aiDisabledIdScanner = 1
		message = "IdScan feature has been disabled."

	if(feedback && message && user)
		to_chat(user, message)

/obj/machinery/door/airlock/proc/set_safeties(activate, feedback = FALSE, mob/user)
	var/message = ""
	// Safeties!  We don't need no stinking safeties!
	if (wire_cut(WIRE_SAFETY))
		message = "The safety wire is cut - Cannot enable safeties."
	else if (!activate && safe)
		safe = 0
	else if (activate && !safe)
		safe = 1

	if(feedback && message && user)
		to_chat(user, message)

// shock user with probability prb (if all connections & power are working)
// returns 1 if shocked, 0 otherwise
// The preceding comment was borrowed from the grille's shock script
/obj/machinery/door/airlock/shock(mob/user, prb)
	if(!arePowerSystemsOn())
		return FALSE
	if(!COOLDOWN_FINISHED(src, hasShocked))
		return FALSE	//Already shocked someone recently?
	if(..())
		COOLDOWN_START(src, hasShocked, 1 SECOND)
		return TRUE
	else
		return FALSE

// The door template the base door declares (door.dm) doesn't apply: draw() below is the look.
APPEARANCE_NONE(/obj/machinery/door/airlock)

/// Bridge while door.dm's other doors still draw through update_icon(): its shared procs (and the
/// declared appearance watch on stat and density) call update_icon(), which marks the airlock changed
/// so draw() runs.
// ALLOW(sys_update_icon, sys_old_appearance): bridge only; it draws nothing, it marks the airlock so draw() runs
/obj/machinery/door/airlock/update_icon()
	changed(src)

/obj/machinery/door/airlock/capabilities()
	. = ..()
	// draw() shows door_locked while the bolt lights are on, so the bolts and emergency access draw no
	// layer of their own; the door's own welder repair (door.dm) mends it.
	. += door(wires = /datum/wires/airlock, electrify = TRUE, ai_control = TRUE, emag_effect = PROC_REF(emag_effect), weld_applies = PROC_REF(can_weld_now), weld_help_applies = PROC_REF(can_weld_without_repair))
	. += cap_frozen_shut()
	. += cap_hand("Use", PROC_REF(touch_airlock), needs = PROC_REF(can_touch_by_hand))
	. += cap_use_on("Use", /obj/item, PROC_REF(use_item_on_airlock), works_broken = TRUE, works_unpowered = TRUE)
	. += airlock_ctrl_entry(cap_hand("Hammer on the door", PROC_REF(hammer_on_door), works_broken = TRUE, works_unpowered = TRUE, stance = I_HURT), insulated = TRUE)
	. += airlock_ctrl_entry(cap_hand("Hold the door open", PROC_REF(hold_door_open), works_broken = TRUE, works_unpowered = TRUE, stance = I_GRAB))

/// A ctrl-click entry: run from click_ctrl() for the stance it declares.
/proc/airlock_ctrl_entry(datum/capability/entry/C, insulated = FALSE)
	cap_entry_setup(C.entry, insulated = insulated, legacy_entry = AIRLOCK_ENTRY_CTRL)
	return C

/obj/machinery/door/airlock/draw(datum/look/look)
	..()
	// doorint.dmi and its kin have no wires, broken or dark states: the sparks below show damage.
	look.hide("wires")
	look.hide("broken")
	look.hide("dark")
	var/powered = !has_stat(NOPOWER)
	var/damaged = get_integrity() < max_integrity * 3/4
	if(density)
		look.state((is_bolted(src) && lights && arePowerSystemsOn()) ? "door_locked" : "door_closed")
		if(panel_is_open(src) || is_welded(src))
			if(powered)
				if(has_stat(BROKEN))
					look.overlay("sparks_broken")
				else if(damaged)
					look.overlay("sparks_damaged")
		else if(damaged && powered)
			look.overlay("sparks_damaged")
	else
		look.hide("panel_open")
		look.hide("welded")
		look.state(open_state())
		look.overlay("sparks_open", when = has_stat(BROKEN) && powered)
	look.overlay("snowairlock", when = frozen, icon = 'icons/turf/overlays.dmi')

/// The icon_state of the open door (a subtype shows its bolts on an open door).
/obj/machinery/door/airlock/proc/open_state()
	return "door_open"

/obj/machinery/door/airlock/do_animate(animation)
	switch(animation)
		if("opening")
			flick(panel_is_open(src) ? "o_door_opening" : "door_opening", src)
		if("closing")
			flick(panel_is_open(src) ? "o_door_closing" : "door_closing", src)
		if("spark")
			if(density)
				flick("door_spark", src)
		if("deny")
			if(density && arePowerSystemsOn())
				flick("door_deny", src)
				playsound(src, denied_sound, 50, 0, 3)
	return

/obj/machinery/door/airlock/proc/hack(mob/user as mob)
	if(aiHacking)
		return
	aiHacking = TRUE
	om_task_start(/datum/om/task/airlock_ai_hack, src, null, receiver = src, user = user)

/// An AI hacking an airlock whose AI control is blocked: fault detection, the hack, the
/// upload and the transfer, each re-checking that the hack is still needed and possible.
/datum/om/task/airlock_ai_hack
	name = "airlock ai hack"
	steps = list(
		/obj/machinery/door/airlock/proc/hack_detect = 2 SECONDS,
		/obj/machinery/door/airlock/proc/hack_fault_confirmed = 5 SECONDS,
		/obj/machinery/door/airlock/proc/hack_attempt = 2 SECONDS,
		/obj/machinery/door/airlock/proc/hack_upload = 20 SECONDS,
		/obj/machinery/door/airlock/proc/hack_transfer = 17 SECONDS,
		/obj/machinery/door/airlock/proc/hack_receive = 5 SECONDS,
		/obj/machinery/door/airlock/proc/hack_finish = 1 SECOND)
	cancel_proc = /obj/machinery/door/airlock/proc/hack_stopped
	/// The hacking AI.
	var/mob/user

/obj/machinery/door/airlock/proc/hack_stopped(datum/om/task/T)
	aiHacking = FALSE

/// Stops the hack if control came back on its own or the AI lost its link. Null if it goes on.
/obj/machinery/door/airlock/proc/hack_check(mob/user)
	if(canAIControl())
		to_chat(user, "Alert cancelled. Airlock control has been restored without our assistance.")
		return STEP_FAIL("restored")
	if(!canAIHack(user))
		to_chat(user, "We've lost our connection! Unable to hack airlock.")
		return STEP_FAIL("lost connection")
	return null

/obj/machinery/door/airlock/proc/hack_detect(datum/om/task/airlock_ai_hack/T)
	//TODO: Make this take a minute
	to_chat(T.user, "Airlock AI control has been blocked. Beginning fault-detection.")
	return STEP_NEXT

/obj/machinery/door/airlock/proc/hack_fault_confirmed(datum/om/task/airlock_ai_hack/T)
	var/mob/user = T.user
	. = hack_check(user)
	if(.)
		return
	to_chat(user, "Fault confirmed: airlock control wire disabled or cut.")
	return STEP_NEXT

/obj/machinery/door/airlock/proc/hack_attempt(datum/om/task/airlock_ai_hack/T)
	to_chat(T.user, "Attempting to hack into airlock. This may take some time.")
	return STEP_NEXT

/obj/machinery/door/airlock/proc/hack_upload(datum/om/task/airlock_ai_hack/T)
	var/mob/user = T.user
	. = hack_check(user)
	if(.)
		return
	to_chat(user, "Upload access confirmed. Loading control program into airlock software.")
	return STEP_NEXT

/obj/machinery/door/airlock/proc/hack_transfer(datum/om/task/airlock_ai_hack/T)
	var/mob/user = T.user
	. = hack_check(user)
	if(.)
		return
	to_chat(user, "Transfer complete. Forcing airlock to execute program.")
	return STEP_NEXT

/obj/machinery/door/airlock/proc/hack_receive(datum/om/task/airlock_ai_hack/T)
	//disable blocked control
	aiControlDisabled = 2
	to_chat(T.user, "Receiving control information from airlock.")
	return STEP_NEXT

/obj/machinery/door/airlock/proc/hack_finish(datum/om/task/airlock_ai_hack/T)
	//bring up airlock dialog
	aiHacking = 0
	actor_use(/datum/input_adapter/ai, T.user, src)
	return STEP_DONE

/obj/machinery/door/airlock/CanPass(atom/movable/mover, turf/target)
	if (isElectrified())
		if (istype(mover, /obj/item))
			var/obj/item/i = mover
			var/list/item_matter = i.material_totals()
			if (item_matter && (MAT_STEEL in item_matter) && item_matter[MAT_STEEL] > 0)
				fx_sparks(src, 5)
	. = ..()

// ---- entries (capabilities() above lists them) ----

/// The Use touch needs what the machinery hand gate needs: power, posture and dexterity.
/obj/machinery/door/airlock/proc/can_touch_by_hand(mob/user, obj/item/held)
	return can_operate_by_hand(user, src, held)

/// A bare hand on the airlock (cap_electrify() has already zapped): let go of a door someone holds,
/// xenos tear at it, an open panel shows the wires. Otherwise declines, and the door's own Use opens it.
/obj/machinery/door/airlock/proc/touch_airlock(mob/user, obj/item/held)
	if(!Adjacent(hold_open()))
		rel_clear(src, "hold_open")

	if(hold_open() && !density)
		if(hold_open() == user)
			rel_clear(src, "hold_open")
		else
			to_chat(user, span_warning("[hold_open()] is holding \the [src] open!"))

	if(ishuman(user))
		var/mob/living/carbon/human/X = user
		if(istype(X.species, /datum/species/xenos))
			attack_alien(user)
			return TRUE

	if(panel_is_open(src))
		wires_of(src).Interact(user)
		return TRUE

	return FALSE

/// Anything held against the airlock (after cap_electrify()): tape, a signaler, a pAI cable, or a
/// prying weapon on an unpowered door. Otherwise declines, and the door's own item use follows.
/obj/machinery/door/airlock/proc/use_item_on_airlock(mob/user, obj/item/held)
	touched_with(user, held)

	if(istype(held, /obj/item/taperoll))
		return TRUE

	if(istype(held, /obj/item/assembly/signaler))
		attack_hand(user)
		return TRUE

	if(istype(held, /obj/item/pai_cable))	// -- TLE
		var/obj/item/pai_cable/cable = held
		cable.plugin(src, user)
		return TRUE

	// Non-crowbar prying weapons retain their special unpowered-door behavior.
	if(held.pry && !held.has_tool_quality(TOOL_CROWBAR) && !arePowerSystemsOn())
		if(is_bolted(src))
			to_chat(user, span_notice("The airlock's bolts prevent it from being forced."))
			return TRUE
		if(!is_welded(src) && !operating)
			if(istype(held, /obj/item/material/twohanded/fireaxe))
				var/obj/item/material/twohanded/fireaxe/F = held
				if(!F.wielded)
					to_chat(user, span_warning("You need to be wielding \the [F] to do that."))
					return TRUE
			if(density)
				open(TRUE)
			else
				close(1)
			return TRUE
	return FALSE

/// An item touched the airlock (before anything else it does). Subtypes react (phoron ignites).
/obj/machinery/door/airlock/proc/touched_with(mob/user, obj/item/held)
	return

/obj/machinery/door/airlock/proc/hammer_on_door(mob/user, obj/item/held)
	act_message(user, src, others = span_warning("%U% hammers on %T%!"), blind = span_warning("Someone hammers loudly on %T%!"))
	if(icon_state == "door_closed" && arePowerSystemsOn())
		flick("door_deny", src)
	playsound(src, knock_hammer_sound, 50, 0, 3)
	return TRUE

/obj/machinery/door/airlock/proc/hold_door_open(mob/user, obj/item/held)
	rel_set(src, "hold_open", user)
	act_message(user, src, others = span_info("%U% begins holding %T% open."), blind = span_info("Someone has started holding %T% open."))
	if(!touch_airlock(user))
		attack_hand(user)
	return TRUE

/obj/machinery/door/airlock/click_ctrl(mob/user) //Hold door open
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(user.is_incorporeal())
		return CLICK_ACTION_BLOCKING

	if(!Adjacent(user))
		return CLICK_ACTION_BLOCKING

	// Combat mode hammers on the door; Grab holds it open (the stance-declared ctrl entries in capabilities()).
	if(run_interaction_entry(user, src, user.get_active_hand(), AIRLOCK_ENTRY_CTRL))
		return CLICK_ACTION_SUCCESS

	if(arePowerSystemsOn())
		if(isElectrified())
			act_message(user, src, others = span_warning("%U% presses the door bell on %T%, making it violently spark!"), blind = span_warning("%T% sparks!"))
			add_fingerprint(user)
			fx_sparks(src, 5)
		else
			act_message(user, src, others = span_info("%U% presses the door bell on %T%."), blind = span_info("%T%'s bell rings."))
			add_fingerprint(user)
		if(icon_state == "door_closed")
			flick("door_deny", src)
		playsound(src, knock_sound, 50, 0, 3)
		return CLICK_ACTION_SUCCESS

	act_message(user, src, others = span_info("%U% knocks on %T%."), blind = span_info("Someone knocks on %T%."))
	add_fingerprint(user)
	playsound(src, knock_unpowered_sound, 50, 0, 3)
	return CLICK_ACTION_SUCCESS

// ---- cap_weld_shut() and cap_pry() ----

/// Welding shut is offered on a closed, still door with no plasteel being fitted.
/obj/machinery/door/airlock/proc/can_weld_now()
	return density && operating <= 0 && !reinforcing

/// Outside combat mode a damaged airlock is repaired instead (the door's welder use, door.dm).
/obj/machinery/door/airlock/proc/can_weld_without_repair()
	return can_weld_now() && get_integrity() >= max_integrity

/obj/machinery/door/airlock/cap_pry_name(mob/user)
	return can_remove_electronics() ? "Remove electronics" : "Force open or closed"

/// Removing the electronics is always possible; forcing needs no power and no bolts.
/obj/machinery/door/airlock/cap_pry_reason(mob/user, obj/item/held)
	if(can_remove_electronics())
		return TRUE
	if(arePowerSystemsOn())
		return "the airlock's motors resist your efforts to force it"
	if(is_bolted(src))
		return "the airlock's bolts prevent it from being forced"
	return TRUE

/obj/machinery/door/airlock/cap_pry_force(mob/user, obj/item/held)
	if(can_remove_electronics())
		use_tool(user, held, src, delay = 4 SECONDS, quality = TOOL_CROWBAR, volume = 75, start_self = "You start to remove electronics from the airlock assembly.", start_others = "[user] removes the electronics from the airlock assembly.", receiver = src, on_done = PROC_REF(crowbar_act_tool_done), done_args = list(user))
		return TRUE
	return ..()

/obj/machinery/door/airlock/proc/crowbar_act_tool_done(mob/user)
	to_chat(user, span_notice("You removed the airlock electronics!"))

	var/obj/structure/door_assembly/da = new assembly_type(get_turf(src))
	if (istype(da, /obj/structure/door_assembly/multi_tile))
		da.set_dir(dir)
	da.set_anchored(TRUE)
	if(mineral)
		da.glass = mineral
	else if(glass && !da.glass)
		da.glass = 1
	da.state = 1
	da.created_name = name
	da.update_state()

	if(operating == -1 || (has_stat(BROKEN)))
		new /obj/item/circuitboard/broken(get_turf(src))
		operating = 0
	else
		if (!electronics) create_electronics()

		electronics.forceMove(get_turf(src))
		own_take(src, "electronics")
	qdel(src)

/obj/machinery/door/airlock/proc/can_remove_electronics()
	return !frozen && panel_is_open(src) && (operating < 0 || (!operating && is_welded(src) && !arePowerSystemsOn() && density && (!is_bolted(src) || (has_stat(BROKEN)))))

// ---- panel() ----

/// The panel capability's handler, refined: a broken panel won't close, and opening it shows the wires.
/obj/machinery/door/airlock/cap_panel_toggle(mob/user, obj/item/held)
	if(panel_is_open(src) && has_stat(BROKEN))
		return refuse(user, "The panel is broken and cannot be closed.")
	. = ..()
	if(panel_is_open(src))
		wires_of(src).Interact(user)

// ---- emag() ----

/// A cryptographic sequencer sparks a closed, working door open for good. Declines (no use spent) on
/// an open or dead door.
/obj/machinery/door/airlock/proc/emag_effect(mob/user, obj/item/card/emag/card)
	// ALLOW(sys_emag_act): cap_emag()'s effect reuses the door's shared on_emag() mechanism (door.dm)
	if(!on_emag(1, user, card))
		return FALSE // cap_emag(): the effect refuses first, so nothing is set or spent
	return TRUE

// door.dm declares the door's emag for every door; the airlock's is its emag() capability.
TYPE_TABLE(/obj/machinery/door/airlock, emag_decl, null)

// ---- frozen doors ----

/datum/capability/frozen_shut

/// A frozen airlock: every tool and item chips (or melts) the ice before anything else it would do.
/proc/cap_frozen_shut()
	return new /datum/capability/frozen_shut

/datum/capability/frozen_shut/interactions(atom/holder)
	. = list()
	for(var/quality in list(TOOL_CROWBAR, TOOL_SCREWDRIVER, TOOL_WIRECUTTER, TOOL_MULTITOOL, TOOL_WELDER))
		var/datum/capability/entry/wrapper = cap_tool("Clear the ice", quality, TYPE_PROC_REF(/obj/machinery/door/airlock, deice), works_broken = TRUE, works_unpowered = TRUE, priority = 100)
		. += cap_entry_setup(adopt_entry(wrapper, id = "frozen_shut:[quality]"), applies = TYPE_PROC_REF(/obj/machinery/door/airlock, is_frozen), insulated = TRUE, tool_volume = 0)
	// Below the emag (50), above the airlock's other item uses.
	var/datum/capability/entry/by_item = cap_use_on("Clear the ice", /obj/item, TYPE_PROC_REF(/obj/machinery/door/airlock, deice), works_broken = TRUE, works_unpowered = TRUE, priority = 40)
	. += cap_entry_setup(adopt_entry(by_item, id = "frozen_shut:item"), applies = TYPE_PROC_REF(/obj/machinery/door/airlock, is_frozen), insulated = TRUE)

/datum/capability/frozen_shut/examine(atom/holder, mob/user)
	var/obj/machinery/door/airlock/A = holder
	if(istype(A) && A.frozen)
		return list(span_danger("it's frozen shut!"))
	return null

/obj/machinery/door/airlock/proc/is_frozen()
	return frozen

/obj/machinery/door/airlock/proc/deice(mob/user, obj/item/held)
	// A lit welder melts it.
	var/obj/item/weldingtool/welder = held.get_welder()
	if(welder)
		if(welder.remove_fuel(0,user) && welder.isOn())
			to_chat(user, span_notice("You start to melt the ice off \the [src]"))
			playsound(src, welder.usesound, 50, 1)
			om_task_timed(user, 5 SECONDS, target = src, receiver = src, on_done = PROC_REF(welder_act_timed_done), done_args = list(user), busy = user)
		return TRUE

	// Melting with hot objects that don't take fuel
	if(held.is_hot())
		om_task_timed(user, 9 SECONDS, target = src, receiver = src, on_done = PROC_REF(interaction_use_item_timed_done), done_args = list(user), busy = user)
		return TRUE

	// This is just funny
	if(istype(held, /obj/item/pen/crayon))
		to_chat(user, span_notice("You try to use \the [held] to clear the ice, but it crumbles away!"))
		consume(held, user)
		return TRUE

	// Check if we have something that can deice properly, and then use it's deice speed
	for(var/IT in deicing_tools)
		if(istype(held, IT))
			handleRemoveIce(held, user, deicing_tools[IT])
			return TRUE

	//if we can't de-ice the door tell them what's wrong.
	to_chat(user, span_notice("\the [src] is frozen shut!"))
	return TRUE

/obj/machinery/door/airlock/proc/interaction_use_item_timed_done(mob/user)
	to_chat(user, span_notice("You finish melting the ice off \the [src]"))
	unFreeze()

/obj/machinery/door/airlock/proc/welder_act_timed_done(mob/user)
	to_chat(user, span_notice("You finish melting the ice off \the [src]"))
	unFreeze()

/obj/machinery/door/airlock/proc/handleRemoveIce(obj/item/W, mob/user as mob, time = 15)
	to_chat(user, span_notice("You start to chip at the ice covering \the [src]"))
	om_task_timed(user, time SECONDS, target = src, receiver = src, on_done = PROC_REF(handleRemoveIce_timed_done), done_args = list(user), busy = user)

/obj/machinery/door/airlock/proc/handleRemoveIce_timed_done(mob/user)
	unFreeze()
	to_chat(user, span_notice("You finish chipping the ice off \the [src]"))

// ---- the remote control panel (cap_ai_control(), the AiAirlock window) ----

/obj/machinery/door/airlock/ui_allowed(mob/user, action)
	return user_allowed(user)

/obj/machinery/door/airlock/door_safeties_on()
	return !!safe

/obj/machinery/door/airlock/proc/user_allowed(mob/user)
	var/mob/living/silicon/robot/R = user
	if(istype(R) && !check_access(R.idcard))
		return FALSE
	var/allowed = (issilicon(user) && canAIControl(user))
	if(!allowed && isobserver(user))
		var/mob/observer/dead/D = user
		if(D.can_admin_interact())
			allowed = TRUE
	return allowed

/obj/machinery/door/airlock/proc/toggle_bolt(mob/user)
	if(!user_allowed(user))
		return
	if(wire_cut(WIRE_DOOR_BOLTS))
		to_chat(user, span_warning("The door bolt drop wire is cut - you can't toggle the door bolts."))
		return
	if(is_bolted(src))
		if(!arePowerSystemsOn())
			to_chat(user, span_warning("The door has no power - you can't raise the door bolts."))
		else
			unlock()
			to_chat(user, span_notice("The door bolts have been raised."))
	else
		lock()
		to_chat(user, span_warning("The door bolts have been dropped."))

/obj/machinery/door/airlock/proc/user_toggle_open(mob/user)
	if(!user_allowed(user))
		return
	if(frozen)
		to_chat(user, span_warning("The airlock is frozen shut!"))
	else if(is_welded(src))
		to_chat(user, span_warning("The airlock has been welded shut!"))
	else if(is_bolted(src))
		to_chat(user, span_warning("The door bolts are down!"))
	else if(!density)
		if(hold_open())
			if(hold_open() == user)
				rel_clear(src, "hold_open")
				close()
			else
				to_chat(user, span_warning("[hold_open()] is holding \the [src] open!"))
				return
		close()
	else
		open()

/obj/machinery/door/airlock/on_broken()
	cap_set(src, CAP_PANEL_OPEN, TRUE)
	if (secured_wires)
		lock()
	for (var/mob/O in viewers(src, null))
		if ((O.client && !( O.blinded )))
			O.show_message("[name]'s control panel bursts open, sparks spewing out!")

	fx_sparks(src, 5)
	return

/obj/machinery/door/airlock/open(forced=0)
	if(!can_open(forced))
		return FALSE
	if(frozen && !forced) //Frozen airlocks can't open.
		return FALSE
	if(frozen && forced)
		unFreeze()

	use_power(360)	//360 W seems much more appropriate for an actuator moving an industrial door capable of crushing people

	if(hold_open())
		visible_message("[hold_open()] holds \the [src] open.")

	//if the door is unpowered then it doesn't make sense to hear the woosh of a pneumatic actuator
	for(var/mob/M as anything in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(!M || !M.client)
			continue
		var/old_sounds = M.read_preference(/datum/preference/toggle/old_door_sounds)
		var/department_door_sounds = M.read_preference(/datum/preference/toggle/department_door_sounds)
		var/sound
		var/volume
		if(old_sounds) // Do we have old sounds enabled? Play these even if we have department door sounds enabled.
			if(arePowerSystemsOn())
				sound = legacy_open_powered
				volume = 50
			else
				sound = open_sound_unpowered
				volume = 75
		else if(!old_sounds && department_door_sounds && department_open_powered) // Else, we have old sounds disabled, the door has per-department door sounds, and we have chosen to play department door sounds, use these.
			if(arePowerSystemsOn())
				sound = department_open_powered
				volume = 50
			else
				sound = open_sound_unpowered
				volume = 75
		else // Else, play these.
			if(arePowerSystemsOn())
				sound = open_sound_powered
				volume = 50
			else
				sound = open_sound_unpowered
				volume = 75

		var/turf/T = get_turf(M)
		if(isAI(M)) // AI holograms can listen too
			var/mob/living/silicon/ai/A = M
			if(A.holo && istype(LAZYACCESS(A.holo.masters, A),/obj/effect/overlay/aiholo))
				T = get_turf(A.holo)
		var/distance = get_dist(T, get_turf(src))
		if(distance <= world.view * 2)
			if(T && T.z == get_z(src))
				M.playsound_local(get_turf(src), sound, volume, 1, null, 0, TRUE, sound(sound), volume_channel = VOLUME_CHANNEL_DOORS)

	GLOB.motiontracker_service.ping(src,100)

	if(closeOther() != null && istype(closeOther(), /obj/machinery/door/airlock/) && !closeOther().density)
		closeOther().close()
	. = ..()

/obj/machinery/door/airlock/can_open(forced=0)
	if(!forced)
		if(!arePowerSystemsOn() || wire_cut(WIRE_OPEN_DOOR))
			return FALSE

	if(is_bolted(src) || is_welded(src))
		return FALSE
	. = ..()

/obj/machinery/door/airlock/can_close(forced=0)
	if(is_bolted(src) || is_welded(src))
		return FALSE
	if(!forced)
		//despite the name, this wire is for general door control.
		if(hold_open())
			if(Adjacent(hold_open()) && !hold_open().incapacitated())
				return FALSE
			else
				rel_clear(src, "hold_open")
		if(!arePowerSystemsOn() || wire_cut(WIRE_OPEN_DOOR))
			return	0
	. = ..()

/atom/movable/proc/blocks_airlock()
	return density

/obj/machinery/door/blocks_airlock()
	return FALSE

/obj/machinery/mech_sensor/blocks_airlock()
	return FALSE

/mob/living/blocks_airlock()
	return !is_incorporeal()

/atom/movable/proc/airlock_crush(crush_damage)
	return FALSE

/obj/machinery/portable_atmospherics/canister/airlock_crush(crush_damage)
	. = ..()
	take_damage(crush_damage, BRUTE)

/obj/effect/energy_field/airlock_crush(crush_damage)
	adjust_strength(crush_damage)

/obj/structure/closet/airlock_crush(crush_damage)
	..()
	take_damage(crush_damage, BRUTE)
	latent_materialize_all() // crushing reaches the contents (C5)
	for(var/atom/movable/AM in contents_of(src)) // ALLOW(latent): walk reviewed: reads what is materialized on purpose
		AM.airlock_crush()
	return TRUE

/mob/living/airlock_crush(crush_damage)
	if(is_incorporeal())
		return FALSE
	. = ..()
	var/turf/T = get_turf(src)
	injure(INJURY_BLUNT, crush_damage)
	status_set(EFFECT_STUNNED, 5)
	status_set(EFFECT_WEAKENED, 5)
	if(T)
		T.add_blood(src)
	return TRUE

/mob/living/carbon/airlock_crush(crush_damage)
	. = ..()
	if(. && can_feel_pain()) // Only scream if actually crushed!
		emote("scream")

/mob/living/silicon/robot/airlock_crush(crush_damage)
	injure(INJURY_BLUNT, crush_damage)
	return FALSE

/obj/machinery/door/airlock/close(forced= FALSE, ignore_safties = FALSE, crush_damage)
	if(!can_close(forced))
		return FALSE
	clear_autoclose_blockers()
	if(frozen && !forced)
		return FALSE
	if(frozen && forced) // Unfreeze on forced open
		unFreeze()

	rel_clear(src, "hold_open") //if it passes the can close check, always make sure to clear hold open

	if(safe && !ignore_safties)
		for(var/turf/turf in locs)
			for(var/atom/movable/AM in turf)
				if(AM.blocks_airlock())
					if(!has_beeped)
						play_sfx(src, SFX_MACHINES_BUZZ_TWO)
						has_beeped = 1
					sleep_until_autoclose_blocker_moves(AM)
					return

	door_crush(src, crush_damage) // cap_crush()

	use_power(360)	//360 W seems much more appropriate for an actuator moving an industrial door capable of crushing people
	has_beeped = 0
	for(var/mob/M as anything in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(!M || !M.client)
			continue
		var/old_sounds = M.read_preference(/datum/preference/toggle/old_door_sounds)
		var/department_door_sounds = M.read_preference(/datum/preference/toggle/department_door_sounds)
		var/sound
		var/volume
		if(old_sounds)
			if(arePowerSystemsOn())
				sound = legacy_close_powered
				volume = 50
			else
				sound = open_sound_unpowered
				volume = 75
		else if(!old_sounds && department_door_sounds && department_close_powered) // Else, we have old sounds disabled, the door has per-department door sounds, and we have chosen to play department door sounds, use these.
			if(arePowerSystemsOn())
				sound = department_close_powered
				volume = 50
			else
				sound = open_sound_unpowered
				volume = 75
		else
			if(arePowerSystemsOn())
				sound = close_sound_powered
				volume = 50
			else
				sound = open_sound_unpowered
				volume = 75

		var/turf/T = get_turf(M)
		if(isAI(M)) // AI holograms can listen too
			var/mob/living/silicon/ai/A = M
			if(A.holo && istype(LAZYACCESS(A.holo.masters, A),/obj/effect/overlay/aiholo))
				T = get_turf(A.holo)

		var/distance = get_dist(T, get_turf(src))
		if(distance <= world.view * 2)
			if(T && T.z == get_z(src))
				M.playsound_local(get_turf(src), sound, volume, 1, null, 0, TRUE, sound(sound), volume_channel = VOLUME_CHANNEL_DOORS)

	GLOB.motiontracker_service.ping(src,100)

	for(var/turf/turf in locs)
		var/obj/structure/window/killthis = (locate_within(turf, /obj/structure/window))
		if(killthis)
			killthis.ex_act(2)//Smashin windows
	. = ..()

/// Drops the bolts (cap_bolts(): CAP_BOLTED). forced drops them mid-swing.
/obj/machinery/door/airlock/proc/lock(forced=0)
	if(is_bolted(src))
		return FALSE

	if (operating && !forced) return FALSE

	cap_set(src, CAP_BOLTED, TRUE)
	playsound(src, bolt_down_sound, 30, 0, 3, volume_channel = VOLUME_CHANNEL_DOORS)
	for(var/mob/M in range(1,src))
		M.show_message("You hear a click from the bottom of the door.", 2)
	// A bolted open door cannot autoclose: drop the deadline instead of waking to find that out.
	if(close_door_at && !density)
		close_door_at = 0
		schedule_door_timer()
	publish_door_mode()
	return TRUE

/// Raises the bolts. Unless forced, needs power, a still door and an uncut bolt wire.
/obj/machinery/door/airlock/proc/unlock(forced=0)
	if(!is_bolted(src))
		return

	if (!forced)
		if(operating || !arePowerSystemsOn() || wire_cut(WIRE_DOOR_BOLTS)) return

	cap_set(src, CAP_BOLTED, FALSE)
	playsound(src, bolt_up_sound, 30, 0, 3, volume_channel = VOLUME_CHANNEL_DOORS)
	for(var/mob/M in range(1,src))
		M.show_message("You hear a click from the bottom of the door.", 2)
	resume_autoclose_if_possible()
	publish_door_mode()
	return TRUE

/// cap_bolts() drops and raises through the airlock's own bolt mechanism.
/obj/machinery/door/airlock/set_bolted(on, forced = FALSE)
	return on ? lock(forced) : unlock(forced)

/obj/machinery/door/airlock/allowed(mob/M)
	if(is_bolted(src))
		return FALSE
	. = ..()

/// The access check is the cap_door_access() capability (the door's own req_access, design review H1),
/// and emergency access lets anyone through.
/obj/machinery/door/airlock/check_access_list(list/L)
	if(emergency_access_on(src))
		return TRUE
	var/datum/capability/lock/C = cap_of(src, /datum/capability/lock)
	return C ? C.grants(src, L) : ..()

/obj/machinery/door/airlock/Initialize(mapload, obj/structure/door_assembly/assembly=null)
	//if assembly is given, create the new door from the assembly
	if (assembly && istype(assembly))
		assembly_type = assembly.type

		var/obj/item/airlock_electronics/assembly_electronics = assembly.electronics
		assembly_electronics.forceMove(src)
		own_move(assembly_electronics, src, "electronics") // from the assembly to the door

		//update the door's access to match the electronics'
		secured_wires = electronics.secure
		if(electronics.one_access)
			req_access = null
			req_one_access = electronics.conf_access
		else
			req_one_access = null
			req_access = electronics.conf_access

		//get the name from the assembly
		if(assembly.created_name)
			name = assembly.created_name
		else
			name = "[istext(assembly.glass) ? "[assembly.glass] airlock" : assembly.base_name]"

		//get the dir from the assembly
		set_dir(assembly.dir)

	// Wires: the wires capability makes them on first use, secure ones for secured_wires (wires_type_for()).
	var/turf/T = get_turf(src)
	if(T && (T.z in using_map.admin_levels))
		secured_wires = 1

	. = ..()

	if(closeOtherId != null)
		for (var/obj/machinery/door/airlock/A in REGISTRY_MEMBERS(REGISTRY_MACHINES))
			if(A.closeOtherId == closeOtherId && A != src)
				rel_set(src, "closeOther", A)
				break
	name = "\improper [name]"
	if(frequency)
		set_frequency(frequency)

// Most doors will never be deconstructed over the course of a round,
// so as an optimization defer the creation of electronics until
// the airlock is deconstructed
/obj/machinery/door/airlock/proc/create_electronics()
	//create new electronics
	if (secured_wires)
		own_set(src, "electronics", new/obj/item/airlock_electronics/secure(src))
	else
		own_set(src, "electronics", new/obj/item/airlock_electronics(src))

	//update the electronics to match the door's access
	if(LAZYLEN(req_access))
		electronics.conf_access = req_access
	else if (LAZYLEN(req_one_access))
		electronics.conf_access = req_one_access
		electronics.one_access = 1

DAMAGE_REACTION(/obj/machinery/door/airlock, DAMAGE_EMP, PROC_REF(airlock_emp))
/// An EMP may electrify the airlock for a while.
/obj/machinery/door/airlock/proc/airlock_emp(datum/damage_packet/packet)
	if(prob(40/packet.severity))
		var/seconds = 30 / packet.severity
		// Never shortens a longer (or permanent) electrification.
		if(electrified_until != -1 && time_left(src, nameof(electrified_until)) < seconds SECONDS)
			electrify(seconds)

/obj/machinery/door/airlock/power_change() //putting this is obj/machinery/door itself makes non-airlock doors turn invisible for some reason
	. = ..()
	if(has_stat(NOPOWER))
		// If we lost power, disable electrification
		// Keeping door lights on, runs on internal battery or something.
		timed_cancel(src, nameof(electrified_until))
		set_electrified_until(0)
	resume_autoclose_if_possible()

/obj/machinery/door/airlock/proc/prison_open()
	if(arePowerSystemsOn())
		unlock()
		open()
		lock()
	return

/* moved this block to code\game\objects\items\weapons\rcd.dm
/obj/machinery/door/airlock/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			// Old RCD code made it cost 10 units to decon an airlock.
			// Now the new one costs ten "sheets".
			return rcd_value_entry(RCD_DECONSTRUCT, 5 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 10)
	return FALSE

/obj/machinery/door/airlock/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			to_chat(user, span_notice("You deconstruct \the [src]."))
			qdel(src)
			return TRUE
	return FALSE
*/

/// Most airlocks don't freeze, subtypes set this
/obj/machinery/door/airlock/proc/can_freeze()
	SHOULD_BE_PURE(TRUE) // Don't put logic here, just return if the airlock can freeze or not.
	PROTECTED_PROC(TRUE)
	return FALSE

/obj/machinery/door/airlock/proc/unFreeze()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)

	frozen = FALSE
	changed(src)

/obj/machinery/door/airlock/proc/freeze()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)

	frozen = TRUE
	changed(src)

// === merged from airlock_ch.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/machinery/door/airlock/scp
	name = "SCP Access"
	icon = 'icons/obj/doors/SCPdoor.dmi'
	open_sound_powered = 'sound/machines/scp1o.ogg'
	close_sound_powered = 'sound/machines/scp1c.ogg'

/obj/machinery/door/airlock/can_pathfinding_enter(atom/movable/actor, dir, datum/pathfinding/search)
	return ..() || (has_access(req_access, req_one_access, search.ss13_with_access) && !is_bolted(src) && operable())

// === merged from robot_chomp.dm during hard-fork de-suffix. Placed in this file because it
// is the highest-positioned definer in the override chain for the members it
// sets, so every override stays after its base definition (resolution preserved). ===
/mob/living/silicon/robot
	var/sleeper_resting = FALSE //Enable resting belly sprites for dogborgs that have the sprites
	var/datum/matter_synth/water_res //Enable water for lick clean
	//Multibelly support. We do not want to apply it to any module not supporting it in it's sprites

/mob/living/silicon/robot/proc/ex_reserve_refill()
	set name = "Refill Extinguisher"
	set category = "Object"
	var/datum/matter_synth/water = water_res()
	for(var/obj/item/extinguisher/E in module.modules)
		if(E.reagents.total_volume < E.max_water)
			if(water && water.energy > 0)
				var/amount = E.max_water - E.reagents.total_volume
				if(water.energy < amount)
					amount = water.energy
				water.use_charge(amount)
				E.reagents.add_reagent(REAGENT_ID_WATER, amount)
				to_chat(src, span_filter_notice("You refill the extinguisher using your water reserves."))
			else
				to_chat(src, span_filter_notice("Insufficient water reserves."))

// Old attack_robot overrides: a cyborg with access interfaces remotely as the AI does
// (FALSE: the robot adapter's default); without it, only by hand from next to it.
// atmos_control.dm, robot.dm and turret_control.dm declare these types' other interactions;
// portable_turret.dm lists porta_turret_robot_use in the turret's own declare_interactions().
EXTEND_INTERACTIONS(/obj/machinery/computer/atmoscontrol, INTERACT_ROBOT("Use", PROC_REF(atmoscontrol_robot_use)))
EXTEND_INTERACTIONS(/obj/machinery/computer/robotics, INTERACT_ROBOT("Use", PROC_REF(robotics_console_robot_use)))
EXTEND_INTERACTIONS(/obj/machinery/turretid, INTERACT_ROBOT("Use", PROC_REF(turretid_robot_use)))
EXTEND_INTERACTIONS(/obj/machinery/door/airlock, INTERACT_ROBOT("Use", PROC_REF(airlock_robot_use)))

/obj/machinery/computer/atmoscontrol/proc/atmoscontrol_robot_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(allowed(user))
		return FALSE
	if(Adjacent(user))
		attack_hand(user)
	return TRUE

/obj/machinery/computer/robotics/proc/robotics_console_robot_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(allowed(user))
		return FALSE
	if(Adjacent(user))
		attack_hand(user)
	return TRUE

/obj/machinery/turretid/proc/turretid_robot_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(allowed(user))
		return FALSE
	if(Adjacent(user))
		attack_hand(user)
	return TRUE

/obj/machinery/door/airlock/proc/airlock_robot_use(mob/user, obj/item/held, datum/interaction/interaction)
	var/mob/living/silicon/robot/R = user
	if(!istype(R))
		return TRUE //why are you here
	if(check_access(R.idcard))
		return FALSE
	if(Adjacent(user))
		attack_hand(user)
	return TRUE

/obj/machinery/porta_turret/proc/porta_turret_robot_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(allowed(user))
		return FALSE
	if(Adjacent(user))
		attack_hand(user)
	return TRUE

/obj/machinery/porta_turret/isLocked(mob/user)
	var/mob/living/silicon/robot/R = user
	if(!istype(R))
		return ..()
	if(!locked)
		return FALSE
	if(!check_access(R.idcard))
		return TRUE
	return FALSE

OWN(/obj/machinery/door/airlock, electronics, OWN_CONTAINED)

/// closeOther (a relation view: it reads null once the target is deleted).
/obj/machinery/door/airlock/proc/closeOther() as /obj/machinery/door/airlock
	return closeOther

/// hold open (a relation view: it reads null once the target is deleted).
/obj/machinery/door/airlock/proc/hold_open() as /mob
	return hold_open

/// water res (a relation view: it reads null once the target is deleted).
/mob/living/silicon/robot/proc/water_res() as /datum/matter_synth
	return water_res

#undef AIRLOCK_ENTRY_CTRL
