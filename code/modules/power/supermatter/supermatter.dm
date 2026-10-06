#define NITROGEN_RETARDATION_FACTOR 0.15	//Higher == N2 slows reaction more
#define PHORON_RELEASE_MODIFIER 1500		//Higher == less phoron released by reaction
#define OXYGEN_RELEASE_MODIFIER 15000		//Higher == less oxygen released at high temperature/power
#define REACTION_POWER_MODIFIER 1.1			//Higher == more overall power

/*
	How to tweak the SM

	POWER_FACTOR		directly controls how much power the SM puts out at a given level of excitation (power var). Making this lower means you have to work the SM harder to get the same amount of power.
	CRITICAL_TEMPERATURE	The temperature at which the SM starts taking damage.

	CHARGING_FACTOR		Controls how much emitter shots excite the SM.
	DAMAGE_RATE_LIMIT	Controls the maximum rate at which the SM will take damage due to high temperatures.
*/

//Controls how much power is produced by each collector in range - this is the main parameter for tweaking SM balance, as it basically controls how the power variable relates to the rest of the game.
#define POWER_FACTOR 1.0
#define DECAY_FACTOR 700			//Affects how fast the supermatter power decays
#define CRITICAL_TEMPERATURE 5000	//K
#define CHARGING_FACTOR 0.05
#define DAMAGE_RATE_LIMIT 3			//damage rate cap at power = 300, scales linearly with power

// Base variants are applied to everyone on the same Z level
// Range variants are applied on per-range basis: numbers here are on point blank, it scales with the map size (assumes square shaped Z levels)
#define DETONATION_RADS 40
#define DETONATION_MOB_CONCUSSION 4			// Weaken amount (status units) for mobs.

// Base amount of ticks for which a specific type of machine will be offline for. +- 20% added by RNG.
// This does pretty much the same thing as an electrical storm, it just affects the whole Z level instantly.
#define DETONATION_APC_OVERLOAD_PROB 10		// prob() of overloading an APC's lights.
#define DETONATION_SHUTDOWN_APC 120			// Regular APC.
#define DETONATION_SHUTDOWN_CRITAPC 10		// Critical APC. AI core and such. Considerably shorter as we don't want to kill the AI with a single blast. Still a nuisance.
#define DETONATION_SHUTDOWN_SMES 60			// SMES
#define DETONATION_SHUTDOWN_RNG_FACTOR 20	// RNG factor. Above shutdown times can be +- X%, where this setting is the percent. Do not set to 100 or more.
#define DETONATION_SOLAR_BREAK_CHANCE 60	// prob() of breaking solar arrays (this is per-panel, and only affects the Z level SM is on)

// If power level is between these two, explosion strength will be scaled accordingly between min_explosion_power and max_explosion_power
#define DETONATION_EXPLODE_MIN_POWER 200	// If power level is this or lower, minimal detonation strength will be used
#define DETONATION_EXPLODE_MAX_POWER 2000	// If power level is this or higher maximal detonation strength will be used

#define WARNING_DELAY 20			//seconds between warnings.

#define SUPERMATTER_COUNTDOWN_TIME 30 SECONDS // Causality destabilzation field will last this long, giving engineers a last-ditch chance to prevent boom, or get out.
// Keeps Accent sounds from layering, increase or decrease as preferred.
#define SUPERMATTER_ACCENT_SOUND_COOLDOWN 2 SECONDS

/obj/machinery/power/supermatter
	name = "Supermatter"
	desc = "A strangely translucent and iridescent crystal. " + span_red("You get headaches just from looking at it.")
	icon = 'icons/obj/supermatter.dmi'
	icon_state = "darkmatter"
	plane = MOB_PLANE // So people can walk behind the top part
	layer = ABOVE_MOB_LAYER // So people can walk behind the top part
	density = TRUE
	anchored = FALSE
	unacidable = TRUE
	// The crystal has its own delamination damage model. Generic obj_integrity
	// damage (projectiles, hotspots, explosions, machinery fall-apart) must never
	// destroy it as though it were an ordinary machine.
	resistance_flags = INDESTRUCTIBLE | LAVA_PROOF | FIRE_PROOF | ACID_PROOF
	light_range = 4

	var/gasefficency = 0.25

	var/base_icon_state = "darkmatter"

	var/damage = 0
	var/damage_archived = 0
	var/safe_alert = "Crystaline hyperstructure returning to safe operating levels."
	var/safe_warned = TRUE
	var/public_alert = FALSE //Stick to Engineering frequency except for big warnings when integrity bad
	var/warning_point = 100
	var/warning_alert = "Danger! Crystal hyperstructure instability!"
	var/emergency_point = 500
	var/emergency_alert = "CRYSTAL DELAMINATION IMMINENT."
	var/explosion_point = 1000

	///Are we exploding? (Chompers Edit)
	var/final_countdown = FALSE

	light_color = "#8A8A00"
	var/warning_color = "#B8B800"
	var/emergency_color = "#D9D900"

	var/grav_pulling = 0
	var/pull_radius = 14
	// Time in ticks between delamination ('exploding') and exploding (as in the actual boom)
	var/pull_time = 100
	var/min_explosion_power = 12 // some more damage was 8
	var/max_explosion_power = 24 // some more damage was 16

	var/emergency_issued = 0

	// Time in 1/10th of seconds since the last sent warning
	var/lastwarning = 0

	// This stops spawning redundand explosions. Also incidentally makes supermatter unexplodable if set to 1.
	var/exploded = 0
	/// Set only by the completed delamination path immediately before deletion.
	var/delamination_delete = FALSE

	var/power = 0
	var/oxygen = 0

	//Temporary values so that we can optimize this
	//How much the bullets damage should be multiplied by when it is added to the internal variables
	var/config_bullet_energy = 2
	//How much of the power is left after processing is finished?
//        var/config_power_reduction_per_tick = 0.5
	//How much hallucination should it produce per unit of power?
	var/config_hallucination_power = 0.1

	var/debug = 0

	/// Cooldown tracker for accent sounds,
	var/last_accent_sound = 0

	var/datum/looping_sound/supermatter/soundloop

	var/engwarn = FALSE
	var/critwarn = FALSE
	var/causalitywarn = FALSE
	var/stationcrystal = FALSE

// The crystal (doc/rewrite/final_api.html section 16): its reaction runs every machine service interval while it sits on a turf (sm_step(); in a
// crate or an exosuit it waits), whatever touches it is consumed (the touch ops and the bump), and silicons read its monitor window from afar. Its
// exhaust is a gas reaction (GAS_REACTION_SUPERMATTER, verdigris/domains/gas/src/reaction_energy.rs): DM decides how much phoron and oxygen it
// exhales and its device energy, Rust settles the heat.
CAPABILITIES(/obj/machinery/power/supermatter)
	owns_one(nameof(soundloop), /datum/looping_sound/supermatter, starts = PROC_REF(make_soundloop))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(sm_step)))
	interface("AiSupermatter", input = remote())
	ui_shape(detonating = num(), integrity_percentage = num(), ambient_temp = num(), ambient_pressure = num())
	op("touch", hand(), label("Touch"), ungated(), wait(0), then(PROC_REF(touched)))
	op("touch_item", item(/obj/item), label("Touch"), ungated(), wait(0), then(PROC_REF(touched_with)))
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))

/obj/machinery/power/supermatter/Initialize(mapload)
	uid = gl_uid++
	if(src.z in using_map.station_levels) // Looping Alarms
		stationcrystal = TRUE // Looping Alarms
	return ..()


/// Its hum: the calm loop, playing from the start.
/obj/machinery/power/supermatter/proc/make_soundloop(datum/act/A)
	return new /datum/looping_sound/supermatter(list(src), TRUE)

// an undelaminated deletion is reported; contract telemetry ends.
/obj/machinery/power/supermatter/on_destroy(force)
	if(!delamination_delete)
		log_game("SUPERMATTER([x],[y],[z]) deleted outside its delamination path. Power:[power], Oxygen:[oxygen], Damage:[damage], Integrity:[get_integrity()], QDEL source:[datum_flags]")
		message_admins("WARNING: A supermatter at ([x],[y],[z]) was deleted without completing its delamination path. Check game and runtime logs.")
	if(SScontracts?.has_event_subscribers(CONTRACT_EVENT_MACHINE_RESULT))
		emit_contract_event(CONTRACT_EVENT_MACHINE_RESULT, list(
			"department" = DEPARTMENT_ENGINEERING,
			"machine_kind" = "supermatter",
			"station_machine" = stationcrystal && (z in using_map.station_levels),
			"machine_id" = REF(src),
			"metrics" = list("eer" = -1, "integrity" = 0),
			"detail" = "Supermatter telemetry ended",
		), "supermatter-destroyed:[REF(src)]:[world.time]", src)
	..()

/obj/machinery/power/supermatter/proc/get_status()
	var/turf/T = get_turf(src)
	if(!T)
		return SUPERMATTER_ERROR
	var/datum/gas_mixture/air = T.return_air()
	if(!air)
		return SUPERMATTER_ERROR

	if(grav_pulling || exploded)
		return SUPERMATTER_DELAMINATING

	if(get_integrity() < 25)
		return SUPERMATTER_EMERGENCY

	if(get_integrity() < 50)
		return SUPERMATTER_DANGER

	var/air_temperature = air.return_temperature()
	if((get_integrity() < 100) || (air_temperature > CRITICAL_TEMPERATURE))
		return SUPERMATTER_WARNING

	if(air_temperature > (CRITICAL_TEMPERATURE * 0.8))
		return SUPERMATTER_NOTIFY

	if(power > 5)
		return SUPERMATTER_NORMAL
	return SUPERMATTER_INACTIVE

/obj/machinery/power/supermatter/proc/get_epr()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	var/datum/gas_mixture/air = T.return_air()
	if(!air)
		return 0
	// group_multiplier was XGM-only (zones contained multiple tiles
	// scaled by count). LINDA mixtures are per-tile so divide by 1.
	return round(xgm_total_moles(air) / 23.1, 0.01)

/// Starts the delamination: the pull, then the effects after `pull_time` (explode_effects()).
/obj/machinery/power/supermatter/proc/explode()
	message_admins("Supermatter exploded at ([x],[y],[z] - <A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)")
	log_game("SUPERMATTER([x],[y],[z]) Exploded. Power:[power], Oxygen:[oxygen], Damage:[damage], Integrity:[get_integrity()]")
	set_anchored(TRUE)
	grav_pulling = 1
	exploded = 1
	// Looping Alarms. We want to stop the alarm here.
	if(stationcrystal) // Are we an on-station crystal?
		after(null, 10 SECONDS, GLOBAL_PROC_REF(reset_sm_alarms))

	after(src, pull_time, PROC_REF(explode_effects))

/obj/machinery/power/supermatter/proc/explode_effects()
	var/turf/TS = get_turf(src)		// The turf supermatter is on. SM being in a locker, exosuit, or other container shouldn't block it's effects that way.
	if(!istype(TS))
		return
	radiation_pulse(
		TS,
		max_range = 255,
		threshold = RAD_HEAVY_INSULATION,
		chance = DETONATION_RADS,
		strength = DETONATION_RADS * 5
	)

	var/list/affected_z = GetConnectedZlevels(TS.z)

	// Effect 1: Radiation, weakening to all mobs on Z level
	for(var/z_to_affect in affected_z)
		var/turf/turf_to_hit = locate(TS.x, TS.y, z_to_affect)
		if(turf_to_hit)
			radiation_pulse(
				turf_to_hit,
				max_range = 255,
				threshold = RAD_HEAVY_INSULATION,
				chance = DETONATION_RADS,
				strength = DETONATION_RADS * 5
			)

	for(var/mob/living/mob in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS))
		var/turf/TM = get_turf(mob)
		if(!TM)
			continue
		if(!(TM.z in affected_z))
			continue

		mob.status_at_least(STAT_WEAKENED, DETONATION_MOB_CONCUSSION)
		to_chat(mob, span_danger("An invisible force slams you against the ground!"))

	// Effect 2: Z-level wide electrical pulse
	for(var/obj/machinery/power/apc/A in REGISTRY_MEMBERS(REGISTRY_APCS))
		if(!(A.z in affected_z))
			continue

		// Overloads lights
		if(prob(DETONATION_APC_OVERLOAD_PROB))
			A.overload_lighting()
		// Causes the APCs to go into system failure mode.
		var/random_change = rand(100 - DETONATION_SHUTDOWN_RNG_FACTOR, 100 + DETONATION_SHUTDOWN_RNG_FACTOR) / 100
		if(A.is_critical)
			A.energy_fail(round(DETONATION_SHUTDOWN_CRITAPC * random_change))
		else
			A.energy_fail(round(DETONATION_SHUTDOWN_APC * random_change))

	// Effect 3: Break solar arrays
	for(var/obj/machinery/power/solar/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(!(S.z in affected_z))
			continue
		if(prob(DETONATION_SOLAR_BREAK_CHANCE))
			S.broken()

	// Effect 4: Medium scale explosion
	var/explosion_power = min_explosion_power
	if(power > 0)
		// 0-100% where 0% is at DETONATION_EXPLODE_MIN_POWER or lower and 100% is at DETONATION_EXPLODE_MAX_POWER or higher
		var/strength_percentage = between(0, (power - DETONATION_EXPLODE_MIN_POWER) / ((DETONATION_EXPLODE_MAX_POWER - DETONATION_EXPLODE_MIN_POWER) / 100), 100)
		explosion_power = between(min_explosion_power, (((max_explosion_power - min_explosion_power) * (strength_percentage / 100)) + min_explosion_power), max_explosion_power)

	explosion(TS, explosion_power/2, explosion_power, max_explosion_power, explosion_power * 4, 1)
	delamination_delete = TRUE
	// Allow the explosion to finish. The global owner: the crystal is deleted below and the
	// explosion may replace the turf.
	after(null, 5, /proc/leave_broken_supermatter, with = list(TS))
	destroyed(src)

/proc/leave_broken_supermatter(turf/TS)
	new /obj/item/broken_sm(TS)

//Changes color and luminosity of the light to these values if they were not already set
/obj/machinery/power/supermatter/proc/shift_light(lum, clr)
	if(lum != light_range || clr != light_color)
		set_light(lum, l_color = clr)

// Supermatter reports integrity as 0-100% of its meltdown threshold; this overrides the
// atom get_integrity() (the SM is not damaged through the atom_integrity system).
/obj/machinery/power/supermatter/get_integrity()
	var/integrity = damage / explosion_point
	integrity = round(100 - integrity * 100)
	integrity = integrity < 0 ? 0 : integrity
	return integrity

/obj/machinery/power/supermatter/proc/announce_warning()
	var/integrity = get_integrity()
	var/alert_msg = " Integrity at [integrity]%"
	var/message_sound = 'sound/ambience/matteralarm.ogg'

	if(!(src.z in using_map.station_levels)) // SM Global Warn Fix; Is our location the same as the station? If no, then we're not going to warn.
		return // SM Global Warn Fix; No need to announce if we're outside the station's Z, at a POI, etc.

	if(final_countdown) // Chompers additon
		return
	if(damage > emergency_point)
		alert_msg = emergency_alert + alert_msg
		lastwarning = world.timeofday - WARNING_DELAY * 4
		// /obj/machinery/firealarm was deleted with ZAS fire_alarm.dm;
		// the critalarm/engalarm sound loops are gone. Just track the warn flag
		// so subsequent ticks don't re-trigger; alarm audio comes back if a LINDA
		// equivalent is wired later.
		if(!critwarn)
			critwarn = TRUE
		safe_warned = FALSE
	else if(damage > 0 && damage >= damage_archived) // The damage is still going up
		// firealarm machinery deleted; preserve the engineering light
		// alert but skip the alarm sound loop.
		if(!engwarn)
			if(src.z in using_map.station_levels)
				for(var/area/our_area in world)
					if(istype(our_area, /area/engineering))
						for(var/obj/machinery/light/L in our_area)
							L.set_alert_engineering()
			engwarn = TRUE
		safe_warned = FALSE
		alert_msg = warning_alert + alert_msg
		lastwarning = world.timeofday

	else if(!safe_warned)
		safe_warned = TRUE // We are safe, warn only once
		alert_msg = safe_alert
		lastwarning = world.timeofday
		reset_alarms() // Looping Alarms
	else
		alert_msg = null
	if(alert_msg)
		GLOB.global_announcer.autosay(alert_msg, "Supermatter Monitor", "Engineering")
		log_game("SUPERMATTER([x],[y],[z]) Emergency engineering announcement. Power:[power], Oxygen:[oxygen], Damage:[damage], Integrity:[get_integrity()]")
		//Public alerts
		if((damage > emergency_point) && !public_alert)
			GLOB.global_announcer.autosay("WARNING: SUPERMATTER CRYSTAL DELAMINATION IMMINENT!", "Supermatter Monitor")
			for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS)) // Rykka adds SM Delam alarm
				if(!isnewplayer(M) && !isdeaf(M)) // Rykka adds SM Delam alarm
					M << message_sound // Rykka adds SM Delam alarm
			admin_chat_message(message = "SUPERMATTER DELAMINATING!", color = "#FF2222")
			public_alert = TRUE
			log_game("SUPERMATTER([x],[y],[z]) Emergency PUBLIC announcement. Power:[power], Oxygen:[oxygen], Damage:[damage], Integrity:[get_integrity()]")
		else if(safe_warned && public_alert)
			GLOB.global_announcer.autosay(alert_msg, "Supermatter Monitor")
			public_alert = FALSE

/// One step of the crystal (every MACHINE_SERVICE_INTERVAL): warnings and the countdown, the anomalies, its sound, then the reaction with a share
/// of the air around it (power, damage and exhaust), the hallucinations and the radiation, and the radiation loss. Off a turf (a crate, an
/// exosuit) it does nothing until it is back on one.
/obj/machinery/power/supermatter/proc/sm_step(datum/act/timer/A)
	var/turf/L = loc
	if(!istype(L))
		return

	if(damage > explosion_point)
		if(!exploded)
			if(!istype(L, /turf/space))
				announce_warning()
			countdown() // Chompers Edit
	else if(damage > warning_point) // while the core is still damaged and it's still worth noting its status
		shift_light(5, warning_color)
		if(damage > emergency_point)
			shift_light(7, emergency_color)
		if(!istype(L, /turf/space) && (world.timeofday - lastwarning) >= WARNING_DELAY * 10)
			announce_warning()
	else
		shift_light(4,initial(light_color))

	if(damage < warning_point && !safe_warned && (world.timeofday - lastwarning) >= WARNING_DELAY * 10) // In case our safe announcement was not sent, we send it latest now
		announce_warning()

	if(grav_pulling)
		supermatter_pull(src)

	if(damage) // Start fucking things up
		if(get_integrity() < 85 && prob(5))
			generate_anomaly(get_ranged_target_turf(src, pick(GLOB.cardinal), rand(5, 10)), FLUX_ANOMALY)
		if(get_integrity() < 75 && prob(5))
			generate_anomaly(get_ranged_target_turf(src, pick(GLOB.cardinal), rand(5, 10)), HALLUCINATION_ANOMALY)
		if(get_integrity() < 50 && prob(2))
			generate_anomaly(get_ranged_target_turf(src, pick(GLOB.cardinal), rand(5, 10)), GRAVITATIONAL_ANOMALY)
		if(get_integrity() < 25 && prob(0.3))
			generate_anomaly(get_ranged_target_turf(src, pick(GLOB.cardinal), rand(5, 10)), PYRO_ANOMALY)

	// Vary volume by power produced.
	if(power)
		// Volume will be 1 at no power, ~12.5 at ENERGY_NITROGEN, and 20+ at ENERGY_PHORON.
		// Capped to 20 volume since higher volumes get annoying and it sounds worse.
		// Formula previously was min(round(power/10)+1, 20)
		soundloop.volume = CLAMP((50 + (power / 50)), 50, 100)

	// Swap loops between calm and delamming.
	if(damage >= 300)
		soundloop.mid_sounds = list('sound/machines/sm/loops/delamming.ogg' = 1)
	else
		soundloop.mid_sounds = list('sound/machines/sm/loops/calm.ogg' = 1)

	// Play Delam/Neutral sounds at rate determined by power and damage.
	if(COOLDOWN_FINISHED(src, last_accent_sound) && prob(20))
		var/aggression = min(((damage / 800) * (power / 2500)), 1.0) * 100
		if(damage >= 300)
			play_sfx(src, SFX_SMDELAM, volume = max(50, aggression))
		else
			play_sfx(src, SFX_SMCALM, volume = max(50, aggression))
		var/next_sound = round((100 - aggression) * 5)
		COOLDOWN_START(src, last_accent_sound, max(SUPERMATTER_ACCENT_SOUND_COOLDOWN, next_sound))

	//Ok, get the air from the turf
	var/datum/gas_mixture/removed = null
	var/datum/gas_mixture/env = null

	//ensure that damage doesn't increase too quickly due to super high temperatures resulting from no coolant, for example. We dont want the SM exploding before anyone can react.
	//We want the cap to scale linearly with power (and explosion_point). Let's aim for a cap of 5 at power = 300 (based on testing, equals roughly 5% per SM alert announcement).
	var/damage_inc_limit = (power/300)*(explosion_point/1000)*DAMAGE_RATE_LIMIT

	if(!istype(L, /turf/space))
		env = L.return_air()
		removed = env.remove(gasefficency * xgm_total_moles(env)) // Remove gas from surrounding area // total_moles is a proc in LINDA, use xgm_total_moles helper

	if(!env || !removed || !xgm_total_moles(removed)) // total_moles is a proc in LINDA, use xgm_total_moles helper
		damage += max((power - 15*POWER_FACTOR)/10, 0)
	else if (grav_pulling) //If supermatter is detonating, remove all air from the zone
		var/datum/gas_mixture/drained = env.remove(xgm_total_moles(env)) // total_moles is a proc in LINDA, use xgm_total_moles helper
		spent(drained)
	else
		damage_archived = damage

		damage = max( damage + min( ( (removed.return_temperature() - CRITICAL_TEMPERATURE) / 150 ), damage_inc_limit ) , 0 )
		//Ok, 100% oxygen atmosphere = best reaction
		//Maxes out at 100% oxygen pressure
		oxygen = max(min((LINDA_GAS_AMT(removed, GAS_O2) - (LINDA_GAS_AMT(removed, GAS_N2) * NITROGEN_RETARDATION_FACTOR)) / xgm_total_moles(removed), 1), 0) // XGM mix.gas[id] dict read → LINDA_GAS_AMT macro; total_moles var → xgm_total_moles helper

		//calculate power gain for oxygen reaction
		var/temp_factor
		var/equilibrium_power
		if (oxygen > 0.8)
			//If chain reacting at oxygen == 1, we want the power at 800 K to stabilize at a power level of 400
			equilibrium_power = 400
			icon_state = "[base_icon_state]_glow"
		else
			//If chain reacting at oxygen == 1, we want the power at 800 K to stabilize at a power level of 250
			equilibrium_power = 250
			icon_state = base_icon_state

		temp_factor = ( (equilibrium_power/DECAY_FACTOR)**3 )/800
		power = max( (removed.return_temperature() * temp_factor) * oxygen + power, 0)

		//We've generated power, now let's transfer it to the collectors for storing/usage
		//transfer_energy()

		var/device_energy = power * REACTION_POWER_MODIFIER

		// The exhaust: phoron and oxygen, and SUPERMATTER_THERMAL_RELEASE J per unit of device energy (Rust settles the temperature), capped at
		// 10000 K.
		var/released = gas_react(removed, GAS_REACTION_SUPERMATTER, max(device_energy, 0), list(
			/datum/gas/plasma = max(device_energy / PHORON_RELEASE_MODIFIER, 0),
			/datum/gas/oxygen = max((device_energy + removed.return_temperature() - T0C) / OXYGEN_RELEASE_MODIFIER, 0)))
		if(debug)
			visible_message("[src]: Releasing [round(released)] J.")
		if(removed.return_temperature() > 10000)
			heat_set(removed, 10000, HEAT_SOURCE_REACTION)

		env.merge(removed)

	spent(removed)

	for(var/mob/living/carbon/human/l in view(src, min(7, round(sqrt(power/6))))) // If they can see it without mesons on.  Bad on them.
		if(!istype(l.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/meson) || l.is_incorporeal()) //Only mesons can protect you! OR if they're not in the same plane of existence
			l.status_set(STAT_HALLUCINATING, max(0, min(200, l.status_units(STAT_HALLUCINATING) + power * config_hallucination_power * sqrt( 1 / max(1,get_dist(l, src)) ) ) ))

	// At a power mult of 0.025 for range, this means a 1000power SM (about normal) will reach 25 tiles and be putting off rad pulses of 500. With 0 protection, you have a 10% chance of getting hit.
	radiation_pulse(
		src,
		max_range = CLAMP(round(power * 0.025), 5, 50),
		threshold = CLAMP(RAD_MEDIUM_INSULATION - (power * 0.00025), 0.1, RAD_MEDIUM_INSULATION),
		chance = max(round(power * 0.01), DEFAULT_RADIATION_CHANCE),
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = max(round(power * 0.5), 50)
	)

	power -= (power/DECAY_FACTOR)**3		//energy losses due to radiation
	if(SScontracts?.has_event_subscribers(CONTRACT_EVENT_MACHINE_RESULT))
		var/list/telemetry_metrics = list(
			"eer" = power,
			"epr" = get_epr(),
			"integrity" = get_integrity(),
		)
		if(env)
			telemetry_metrics["temperature"] = env.return_temperature()
			telemetry_metrics["pressure"] = env.return_pressure()
			var/total_environment_moles = env.total_moles()
			telemetry_metrics["gas_count"] = length(env.get_gases())
			telemetry_metrics["plasma_fraction"] = total_environment_moles > 0 ? env.get_moles(/datum/gas/plasma) / total_environment_moles : 0
			telemetry_metrics["oxygen_fraction"] = total_environment_moles > 0 ? env.get_moles(/datum/gas/oxygen) / total_environment_moles : 0
		emit_contract_event(CONTRACT_EVENT_MACHINE_RESULT, list(
			"department" = DEPARTMENT_ENGINEERING,
			"machine_kind" = "supermatter",
			"station_machine" = stationcrystal && (z in using_map.station_levels),
			"machine_id" = REF(src),
			"metrics" = telemetry_metrics,
			"detail" = "Supermatter telemetry reported [round(power)] Relative EER at [round(get_integrity())]% integrity",
		), "supermatter-telemetry:[REF(src)]:[world.time]", src)

/// The look (the draw sweep: from its layers).
/obj/machinery/power/supermatter/draw(datum/look/look)
	..()
	if(final_countdown == 1)
		look.overlay("causality_field")

/obj/machinery/power/supermatter/proc/countdown()
	if(!final_countdown)
		// firealarm machinery deleted; flag the warning state without
		// triggering the deleted alarm sound loop.
		if(!causalitywarn)
			causalitywarn = TRUE

	if(!(src.z in using_map.station_levels)) // SM Global Warn Fix; Is our location the same as the station? If no, then we're not going to use a stabilization field.
		explode() // SM Global Warn Fix; Just exploding, because we're not on the station's Z. No safety countdown.
		return // SM Global Warn Fix; Stops the code here.

	if(final_countdown) // We're already doing it go away
		return
	final_countdown = TRUE
	changed(src)

	var/speaking = "[emergency_alert] The supermatter has reached critical integrity failure. Emergency causality destabilization field has been activated."
	GLOB.global_announcer.autosay(speaking, "Supermatter Monitor")
	countdown_tick(SUPERMATTER_COUNTDOWN_TIME)

/// One second of the final countdown (`i` deciseconds left); explodes when it runs out.
/obj/machinery/power/supermatter/proc/countdown_tick(i)
	if(i < 0)
		explode()
		return
	if(damage < explosion_point) // Cutting it a bit close there engineers
		GLOB.global_announcer.autosay("[safe_alert] Failsafe has been disengaged.", "Supermatter Monitor")
		final_countdown = FALSE
		changed(src)
		return
	// A message once every 5 seconds until the final 5 seconds which count down individualy
	if((i % 50) == 0 || i <= 50)
		var/speaking = i > 50 ? "[DisplayTimeText(i, TRUE)] remain before causality stabilization." : "[i*0.1]..."
		GLOB.global_announcer.autosay(speaking, "Supermatter Monitor")
	after(src, 1 SECOND, PROC_REF(countdown_tick), with = list(i - 10))

/obj/machinery/power/supermatter/bullet_act(obj/item/projectile/Proj)
	var/turf/L = loc
	if(!istype(L))		// We don't run process() when we are in space
		return 0	// This stops people from being able to really power up the supermatter
				// Then bring it inside to explode instantly upon landing on a valid turf.

	var/added_energy
	var/added_damage
	var/proj_damage = Proj.get_structure_damage()
	if(istype(Proj, /obj/item/projectile/beam))
		added_energy = proj_damage * config_bullet_energy	* CHARGING_FACTOR / POWER_FACTOR
		power += added_energy
	else
		added_damage = proj_damage * config_bullet_energy
		damage += added_damage
	if(added_energy || added_damage)
		log_game("SUPERMATTER([x],[y],[z]) Hit by \"[Proj.name]\". +[added_energy] Energy, +[added_damage] Damage.")
	return 0

/// A hand (or a cyborg's empty touch) on the crystal: whoever touched it is consumed.
/obj/machinery/power/supermatter/proc/touched(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, MSG_SELF(span_danger("You reach out and touch %T%. Everything starts burning and all you can hear is ringing. Your last thought is \"That was not a wise decision.\"")), \
		MSG_OTHERS(span_warning("%U% reaches out and touches %T%, inducing a resonance... %Their% body starts to glow and bursts into flames before flashing into ash.")), \
		MSG_BLIND(span_warning("You hear an uneartly ringing, then what sounds like a shrilling kettle as you are washed with a wave of heat.")))

	Consume(user)
	return OP_OK

// This is purely informational UI that may be accessed by AIs or robots
/obj/machinery/power/supermatter/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["detonating"] = grav_pulling
	data["integrity_percentage"] = round(get_integrity())
	var/datum/gas_mixture/env = null
	if(!istype(src.loc, /turf/space))
		env = src.loc.return_air()

	if(!env)
		data["ambient_temp"] = 0
		data["ambient_pressure"] = 0
	else
		data["ambient_temp"] = round(env.return_temperature())
		data["ambient_pressure"] = round(env.return_pressure())

	return data

/// Anything held to the crystal is consumed, and the hand that held it is irradiated.
/obj/machinery/power/supermatter/proc/touched_with(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	act_message(user, src, MSG_SELF(span_danger("You touch %I% to %T% when everything suddenly goes silent.\"") + "\n" + span_notice("%I% flashes into dust as you flinch away from %T%.")), \
		MSG_OTHERS(span_warning("%U% touches \a [W] to %T% as a silence fills the room...")), \
		MSG_BLIND(span_warning("Everything suddenly goes silent.")), \
		item = W)

	user.drop_from_inventory(W)
	Consume(W)

	if(isliving(user))
		var/mob/living/L = user
		L.apply_effect(150, IRRADIATE)
	return OP_OK

/// Whatever walks or drifts into the crystal is consumed (effects pass through).
/obj/machinery/power/supermatter/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/movable/AM = N.bumper
	if(!AM || QDELETED(AM) || istype(AM, /obj/effect))
		return
	if(isliving(AM))
		var/mob/living/M = AM
		AM.visible_message(span_warning("\The [AM] slams into \the [src] inducing a resonance... [M.p_Their()] body starts to glow and catch flame before flashing into ash."),\
		span_danger("You slam into \the [src] as your ears are filled with unearthly ringing. Your last thought is \"Oh, fuck.\""),\
		span_warning("You hear an uneartly ringing, then what sounds like a shrilling kettle as you are washed with a wave of heat."))
	else if(!grav_pulling) //To prevent spam, detonating supermatter does not indicate non-mobs being destroyed
		AM.visible_message(span_warning("\The [AM] smacks into \the [src] and rapidly flashes to ash."),\
		span_warning("You hear a loud crack as you are washed with a wave of heat."))

	Consume(AM)

/obj/machinery/power/supermatter/proc/Consume(mob/living/user)
	if(istype(user))
		user.dust()
		power += 200
	else
		consumed(user)

	power += 200

		//Some poor sod got eaten, go ahead and irradiate people nearby.
	for(var/mob/living/l in range(10))
		if(l in view())
			l.show_message(span_warning("As \the [src] slowly stops resonating, you find your skin covered in new radiation burns."), 1,\
				span_warning("The unearthly ringing subsides and you notice you have new radiation burns."), 2)
		else
			l.show_message(span_warning("You hear an uneartly ringing and notice your skin is covered in fresh radiation burns."), 2)
	radiation_pulse(
		src,
		max_range = 5,
		threshold = RAD_HEAVY_INSULATION,
		chance = 100,
		strength = 200
	)

/proc/supermatter_pull(atom/target, pull_range = 255, pull_power = STAGE_FIVE)
	for(var/atom/A in range(pull_range, target))
		A.singularity_pull(target, pull_power)

// airflow procs were ZAS-only; LINDA has no whole-zone shoves and the
// underlying procs on /atom/movable were deleted with the migration. These
// supermatter overrides existed to PREVENT the SM from being shoved — under
// LINDA, /atom/movable has no airflow proc to override, so removing them
// preserves the "SM doesn't get shoved" behavior by default (nothing to shove).

/obj/machinery/power/supermatter/shard //Small subtype, less efficient and more sensitive, but less boom.
	name = "Supermatter Shard"
	desc = "A strangely translucent and iridescent crystal that looks like it used to be part of a larger structure. " + span_red("You get headaches just from looking at it.")
	icon_state = "darkmatter_shard"
	base_icon_state = "darkmatter_shard"

	warning_point = 50
	emergency_point = 400
	explosion_point = 600

	gasefficency = 0.125

	pull_radius = 5
	pull_time = 45
	min_explosion_power = 3
	max_explosion_power = 6

/obj/machinery/power/supermatter/shard/announce_warning() //Shards don't get announcements
	return

/obj/item/broken_sm
	name = "shattered supermatter plinth"
	desc = "The shattered remains of a supermatter shard plinth. It doesn't look safe to be around."
	icon = 'icons/obj/supermatter.dmi'
	icon_state = "darkmatter_broken"
	COOLDOWN_DECLARE(event_cooldown)
	/// Mutex to prevent infinite recursion when propagating radiation pulses
	var/active = null

/obj/item/broken_sm/Initialize(mapload)
	. = ..()
	message_admins("Broken SM shard created at ([x],[y],[z] - <A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)")

/obj/item/broken_sm/proc/radiate()
	if(active)
		return
	if(!COOLDOWN_FINISHED(src, event_cooldown))
		return
	active = TRUE
	radiation_pulse(
		src,
		max_range = 5,
		threshold = RAD_MEDIUM_INSULATION,
		chance = URANIUM_IRRADIATION_CHANCE,
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = 25
	)
	COOLDOWN_START(src, event_cooldown, 1.5 SECONDS)
	active = FALSE

/obj/machinery/power/supermatter/station
	stationcrystal = TRUE

/obj/machinery/power/supermatter/proc/reset_alarms()
	reset_sm_alarms()
	engwarn = FALSE
	critwarn = FALSE
	causalitywarn = FALSE

/proc/reset_sm_alarms()
	// /obj/machinery/firealarm was deleted with ZAS fire_alarm.dm; the
	// SM alarm-sound loops have no host. Stub: just reset lights in engineering
	// areas. CHOMP doesn't have GLOB.all_areas; iterate world.
	for(var/area/our_area in world)
		if(istype(our_area, /area/engineering))
			for(var/obj/machinery/light/L in our_area)
				L.reset_alert()

#undef POWER_FACTOR
#undef DECAY_FACTOR
#undef CRITICAL_TEMPERATURE
#undef CHARGING_FACTOR
#undef DAMAGE_RATE_LIMIT

#undef NITROGEN_RETARDATION_FACTOR
#undef PHORON_RELEASE_MODIFIER
#undef OXYGEN_RELEASE_MODIFIER
#undef REACTION_POWER_MODIFIER

#undef DETONATION_RADS
#undef DETONATION_MOB_CONCUSSION

#undef DETONATION_APC_OVERLOAD_PROB
#undef DETONATION_SHUTDOWN_APC
#undef DETONATION_SHUTDOWN_CRITAPC
#undef DETONATION_SHUTDOWN_SMES
#undef DETONATION_SHUTDOWN_RNG_FACTOR
#undef DETONATION_SOLAR_BREAK_CHANCE

#undef DETONATION_EXPLODE_MIN_POWER
#undef DETONATION_EXPLODE_MAX_POWER

#undef WARNING_DELAY

#undef SUPERMATTER_COUNTDOWN_TIME
#undef SUPERMATTER_ACCENT_SOUND_COOLDOWN
