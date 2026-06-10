// Archetype objective structures.
//
// One small family of placed structures that hazard floors scatter at
// generation. Each represents a thing the crew must resolve to clear the
// floor — seal a gas fissure, cool a lava vent, melt an ice choke, light
// an outpost, energize a power tap, cleanse a blight, or destroy a hive
// core. Resolving one credits the layer's matching `neutralize` goal via
// SSquarry.on_layer_objective(z, tag).
//
// Two resolution modes:
//   - interaction (default): stand adjacent and work for `work_time`
//     (a tool in hand speeds it). Models sealing / cooling / lighting /
//     cleansing — the "engineer/medic does the job, someone covers them".
//   - destruction (resolve_by_destruction): beat it down to 0 health.
//     Models hive cores — a combat objective.
//
// Icons are borrowed from an existing sheet for now; art is a polish pass.

/obj/structure/quarry_objective
	name = "hazard node"
	desc = "Something here needs dealing with."
	icon = 'icons/obj/turbolift.dmi'
	icon_state = "button"
	density = FALSE
	anchored = TRUE
	// No glow by default — an unpowered dark_pylon must stay dark until
	// it's resolved. Subtypes that are inherently bright (molten vent,
	// hive core) opt back in.
	light_range = 0
	light_power = 0
	/// Tag matched against the layer's neutralize goal objective_tag.
	var/objective_tag = "objective"
	/// Set once resolved so it can't be double-counted.
	var/resolved = FALSE
	/// Shown to the room when the node resolves.
	var/resolve_message = "The hazard subsides."
	/// Seconds of adjacent work to resolve (interaction mode).
	var/work_time = 6 SECONDS
	/// When TRUE, resolved by being destroyed, not worked.
	var/resolve_by_destruction = FALSE
	/// Health for destruction-mode nodes.
	var/max_health = 250
	var/health = 250
	/// When TRUE the structure stays after resolving (e.g. a lit pylon)
	/// instead of being removed.
	var/keep_on_resolve = FALSE

/obj/structure/quarry_objective/Initialize(mapload)
	. = ..()
	health = max_health

// Interaction-mode resolve (and a flat unarmed chip for destruction mode).
/obj/structure/quarry_objective/attack_hand(mob/user)
	if(resolved)
		return
	if(!user.Adjacent(src))
		to_chat(user, span_warning("You need to be next to \the [src]."))
		return
	if(user.incapacitated())
		return
	if(resolve_by_destruction)
		to_chat(user, span_warning("\The [src] won't yield to bare hands — break it apart."))
		return
	to_chat(user, span_notice("You start working on \the [src]…"))
	if(!do_after(user, work_time, src))
		to_chat(user, span_warning("You stop working on \the [src]."))
		return
	resolve(user)

// Tools/weapons: speed up interaction work, or deal damage in destruction
// mode.
/obj/structure/quarry_objective/attackby(obj/item/W, mob/user)
	if(resolved)
		return
	if(resolve_by_destruction)
		hit_node(W?.force || 5, user)
		return
	if(!user.Adjacent(src))
		return
	// A real tool roughly halves the work; bare improvising is full time.
	var/this_work = istype(W, /obj/item/tool) ? round(work_time * 0.5) : work_time
	to_chat(user, span_notice("You work on \the [src] with \the [W]…"))
	if(!do_after(user, this_work, src))
		to_chat(user, span_warning("You stop working on \the [src]."))
		return
	resolve(user)

// Apply damage to a destruction-mode node.
/obj/structure/quarry_objective/proc/hit_node(amount, mob/user)
	if(resolved || !resolve_by_destruction)
		return
	if(!isnum(amount) || amount <= 0)
		amount = 5
	health -= amount
	playsound(src, 'sound/weapons/smash.ogg', 50, 1)
	if(health <= 0)
		resolve(user)

// Mark resolved, credit the goal, clean up (or stay if keep_on_resolve).
/obj/structure/quarry_objective/proc/resolve(mob/user)
	if(resolved)
		return
	resolved = TRUE
	visible_message(span_notice("[resolve_message]"))
	if(SSquarry)
		SSquarry.on_layer_objective(z, objective_tag)
	on_resolved(user)
	if(!keep_on_resolve)
		qdel(src)

// Hook for subtypes that transform rather than vanish (e.g. light up).
/obj/structure/quarry_objective/proc/on_resolved(mob/user)
	return


// === concrete nodes ==================================================

// #1 Gas flooded — pack and seal a leaking fissure.
/obj/structure/quarry_objective/gas_fissure
	name = "gas fissure"
	desc = "A cracked seam venting choking gas. Pack it before the level fills."
	objective_tag = "seal"
	resolve_message = "The fissure is packed and seals over with a hiss."
	work_time = 6 SECONDS

// #2 Lava — cool a molten vent until it crusts over.
/obj/structure/quarry_objective/lava_vent
	name = "lava vent"
	desc = "A glowing vent pushing out heat. Cool it down."
	icon_state = "button"
	objective_tag = "cool"
	resolve_message = "The vent crusts over and dims to black rock."
	work_time = 7 SECONDS
	light_range = 3
	light_power = 1

// #3 Ice — melt a frozen choke blocking the works.
/obj/structure/quarry_objective/ice_choke
	name = "ice choke"
	desc = "A plug of black ice. Heat it through to clear the way."
	objective_tag = "heat"
	resolve_message = "The ice plug cracks, slumps, and melts away."
	work_time = 7 SECONDS

// #4 Darkness — raise and power an outpost light. Stays lit once on.
/obj/structure/quarry_objective/dark_pylon
	name = "lighting pylon"
	desc = "A dead floodlight pylon. Power it to push back the dark."
	objective_tag = "light"
	resolve_message = "The pylon shudders awake and floods the area with light."
	work_time = 5 SECONDS
	keep_on_resolve = TRUE

/obj/structure/quarry_objective/dark_pylon/on_resolved(mob/user)
	set_light(l_range = 7, l_power = 1.4, l_on = TRUE)
	icon_state = "button"

// #5 Virus — cleanse a blight node (the source of the contagion).
// Doused with an antiviral (spaceacillin) it dies instantly — the
// Chem/Medical "make and bring the cure" path. Bare work is possible but
// slow, and you're being infected the whole time.
/obj/structure/quarry_objective/blight_node
	name = "blight bloom"
	desc = "A weeping growth seeding the level with sickness. Cleanse it — antiviral works best."
	objective_tag = "cure"
	resolve_message = "The blight blackens, withers, and falls to ash."
	work_time = 12 SECONDS

/obj/structure/quarry_objective/blight_node/attackby(obj/item/W, mob/user)
	if(resolved)
		return
	if(istype(W, /obj/item/reagent_containers))
		var/obj/item/reagent_containers/RC = W
		if(RC.reagents?.has_reagent(REAGENT_ID_SPACEACILLIN, 5))
			RC.reagents.remove_reagent(REAGENT_ID_SPACEACILLIN, 5)
			to_chat(user, span_notice("You douse \the [src] with antiviral agent; it blackens instantly."))
			resolve(user)
			return
	return ..()

// #7 Hives — destroy the spawning core in melee/ranged combat.
/obj/structure/quarry_objective/hive_core
	name = "hive core"
	desc = "A pulsing nest spewing fauna. Tear it down."
	objective_tag = "hive"
	resolve_message = "The hive core ruptures, twitches, and goes still."
	resolve_by_destruction = TRUE
	max_health = 400
	health = 400
	light_range = 2
	light_power = 0.6


// === Shaft assault console (#8 siege) ================================
//
// The trigger for the Shaft Assault floor, placed next to the layer's
// bay. Activating it starts a timed defend-the-elevator hold:
//   - drives the survive_timer goal from a real-time clock,
//   - roars at the bay each process tick (the noise draws the assault to
//     the lift),
//   - spawns escalating waves on a cadence,
//   - ABORTS (resets the timer; must be retriggered) if any live hostile
//     gets into the elevator bay, or if the shaft is abandoned.
// On reaching the hold duration it satisfies the goal and re-checks the
// frontier unlock. Runs on SSobj (~2s) only while active.
/obj/structure/quarry_siege_console
	name = "shaft assault control"
	desc = "A deep-drill assault trigger. Start it, then hold the elevator clear for three minutes — anything that gets into the lift aborts the sequence."
	icon = 'icons/obj/turbolift.dmi'
	icon_state = "button"
	density = TRUE
	anchored = TRUE
	light_range = 2
	light_power = 0.7
	/// TRUE while an assault is running.
	var/active = FALSE
	/// world.time the current assault started.
	var/started_at = 0
	/// How long the hold must last.
	var/duration = 3 MINUTES
	/// world.time of the next wave spawn.
	var/next_wave = 0
	var/wave_interval = 15 SECONDS

/obj/structure/quarry_siege_console/Destroy()
	STOP_PROCESSING(SSobj, src)
	return ..()

/obj/structure/quarry_siege_console/examine(mob/user)
	. = ..()
	if(active)
		var/left = max(0, round((started_at + duration - world.time) / 10))
		. += span_warning("ASSAULT ACTIVE — [left]s remaining. Keep the elevator clear!")
	else
		. += span_notice("Idle. Activate to begin the assault.")

/obj/structure/quarry_siege_console/attack_hand(mob/user)
	if(!user.Adjacent(src))
		to_chat(user, span_warning("You need to be next to \the [src]."))
		return
	if(user.incapacitated())
		return
	if(active)
		to_chat(user, span_warning("The assault sequence is already running."))
		return
	if(!SSquarry)
		to_chat(user, span_warning("\The [src] is dead."))
		return
	var/datum/quarry_layer/L = SSquarry.layer_at_z(z)
	if(L?.archetype && L.archetype.is_cleared(L))
		to_chat(user, span_notice("The shaft is already secured."))
		return
	active = TRUE
	started_at = world.time
	next_wave = world.time
	visible_message(span_danger("\The [src] blares to life — the assault begins! Hold the elevator!"))
	START_PROCESSING(SSobj, src)

/obj/structure/quarry_siege_console/proc/abort_assault(reason)
	active = FALSE
	STOP_PROCESSING(SSobj, src)
	var/datum/quarry_layer/L = SSquarry?.layer_at_z(z)
	if(L)
		for(var/datum/quarry_goal/survive_timer/G in L.goals)
			G.progress = 0
	visible_message(span_danger("\The [src] wails: [reason]. Assault aborted — reset and try again."))

/obj/structure/quarry_siege_console/process()
	if(!active || !SSquarry)
		return
	var/datum/quarry_layer/L = SSquarry.layer_at_z(z)
	if(!L?.loaded)
		active = FALSE
		STOP_PROCESSING(SSobj, src)
		return
	if(SSquarry.is_layer_empty(L.z))
		abort_assault("the shaft was abandoned")
		return
	var/list/bay = SSquarry.elevator?.bay_at(L.depth)
	// Breach check: a live hostile inside the lift aborts the sequence.
	if(length(bay))
		for(var/turf/T as anything in bay)
			for(var/mob/living/simple_mob/M in T)
				if(M.stat == DEAD)
					continue
				abort_assault("hostiles in the lift")
				return
	// A ton of noise at the elevator — draws the assault to the bay.
	if(length(bay))
		var/turf/center = bay[5]
		if(isturf(center))
			playsound(center, 'sound/effects/explosionfar.ogg', 70, 1)
			SSquarry.emit_noise(center, QUARRY_NOISE_EXPLOSION, src)
	SSquarry.add_layer_danger(L, 3)
	// Escalating waves on a cadence, scaling slightly with depth.
	if(world.time >= next_wave)
		next_wave = world.time + wave_interval
		var/turf/origin = _quarry_random_layer_floor(L)
		if(origin)
			_quarry_archetype_spawn_mobs(L, origin, rand(3, 5) + round(L.depth / 5))
	// Advance the timer + UI; finish when the hold completes.
	var/elapsed = (world.time - started_at) / 10
	var/target_seconds = duration / 10
	for(var/datum/quarry_goal/survive_timer/G in L.goals)
		G.progress = min(G.target, elapsed)
	if(elapsed >= target_seconds)
		active = FALSE
		STOP_PROCESSING(SSobj, src)
		for(var/datum/quarry_goal/survive_timer/G in L.goals)
			G.progress = G.target
		visible_message(span_notice("\The [src] chimes — the drill breaks through! The way down is open."))
		SSquarry.recompute_unlocked_depth()
