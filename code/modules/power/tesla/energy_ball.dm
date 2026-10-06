#define TESLA_DEFAULT_POWER 1738260
#define TESLA_MINI_POWER 869130

/obj/singularity/energy_ball
	name = "energy ball"
	desc = "An energy ball."
	icon = 'icons/obj/tesla_engine/energy_ball.dmi'
	icon_state = "energy_ball"
	pixel_x = -32
	pixel_y = -32
	current_size = STAGE_TWO
	move_self = 1
	grav_pull = 0
	contained = 0
	density = TRUE
	energy = 0
	dissipate = 1
	dissipate_delay = 5
	dissipate_strength = 1
	var/miniball = FALSE
	var/produced_power
	var/energy_to_raise = 32
	var/energy_to_lower = -20
	resistance_flags = BOMB_PROOF

CAPABILITIES(/obj/singularity/energy_ball)
	param(nameof(miniball), pos = 2)

// ALLOW(init/INSTANCE_STATE): a full energy ball glows
/obj/singularity/energy_ball/Initialize(mapload)
	. = ..()
	if(!miniball)
		set_light(10, 7, "#EEEEFF")

// its orbiting mini-balls go with it.
/obj/singularity/energy_ball/on_destroy(force)
	for(var/obj/singularity/energy_ball/EB as anything in orbiting_balls())
		destroyed(EB)

	..()

/obj/singularity/energy_ball/admin_investigate_setup()
	if(miniball)
		return //don't annnounce miniballs
	..()

/// The ball's step (every 2 s, the singularity's every()): its energy, then a wander of one tile per decisecond and the zap.
/obj/singularity/energy_ball/singularity_frame(datum/act/timer/A)
	if(!src?.orbit_target())
		if (handle_energy())
			return

		// One step per decisecond, then the zap (basket_ball_step()).
		basket_ball_step(max(2 SECONDS - 5, 4 + length(orbiting_balls()) * 1.5), dir)
	else
		energy = 0 // ensure we dont have miniballs of miniballs

/obj/singularity/energy_ball/proc/zap_after_move()
	play_sfx(src, SFX_EFFECTS_LIGHTNINGBOLT, extrarange = 30)

	set_dir(tesla_zap(src, 7, TESLA_DEFAULT_POWER, TRUE, current_jumps = 1))

	for (var/ball in orbiting_balls())
		var/range = rand(1, CLAMP(length(orbiting_balls()), 3, 7))
		tesla_zap(ball, range, TESLA_MINI_POWER/7*range, TRUE, current_jumps = 1)

/obj/singularity/energy_ball/examine(mob/user)
	. = ..()
	if(length(orbiting_balls()))
		. += "The amount of orbiting mini-balls is [length(orbiting_balls())]."

/// One step of the ball's wander (smooth movement: one per decisecond), `left` more to go,
/// then the zap. `move_bias`: we face the last thing we zapped, so this favours that direction a bit.
/obj/singularity/energy_ball/proc/basket_ball_step(left, move_bias)
	var/move_dir = pick(GLOB.alldirs + move_bias) //ensures large-ball teslas don't just sit around
	if(target && prob(10))
		move_dir = get_dir(src,target)
	var/turf/T = get_step(src, move_dir)
	var/moved = FALSE
	if(can_move(T))
		forceMove(T)
		set_dir(move_dir)
		for(var/mob/living/carbon/C in contents_of(loc))
			dust_mob(C)
		moved = TRUE
	if(left <= 0)
		zap_after_move()
	else if(moved)
		after(src, 0.1 SECONDS, PROC_REF(basket_ball_step), with = list(left - 1, move_bias))
	else
		basket_ball_step(left - 1, move_bias)

/obj/singularity/energy_ball/proc/handle_energy()
	if (energy <= 0)
		log_game("TESLA([x],[y],[z]) Collapsed entirely.")
		investigate_log("collapsed.", I_SINGULO)
		spent(src)
		return TRUE

	if(energy >= energy_to_raise)
		energy_to_lower = energy_to_raise - 20
		energy_to_raise = energy_to_raise * 1.25

		play_sfx(src, SFX_EFFECTS_LIGHTNING_CHARGEUP)
		after(src, 10 SECONDS, PROC_REF(new_mini_ball))

	else if(energy < energy_to_lower && length(orbiting_balls()))
		energy_to_raise = energy_to_raise / 1.25
		energy_to_lower = (energy_to_raise / 1.25) - 20

		var/Orchiectomy_target = DEFAULTPICK(orbiting_balls(), null)
		spent(Orchiectomy_target)

	else
		dissipate() //sing code has a much better system.

/// Miniballs only orbit a real ball; they don't count as singularities.
/obj/singularity/energy_ball/skips_registry(registry_id)
	return miniball && registry_id == REGISTRY_SINGULARITIES

/obj/singularity/energy_ball/proc/new_mini_ball()
	if(!loc)
		return
	var/obj/singularity/energy_ball/EB = new(loc, 0, TRUE)

	EB.transform *= pick(0.3, 0.4, 0.5, 0.6, 0.7)
	var/icon/I = icon(icon,icon_state,dir)

	var/orbitsize = (I.Width() + I.Height()) * pick(0.4, 0.5, 0.6, 0.7, 0.8)
	orbitsize -= (orbitsize / world.icon_size) * (world.icon_size * 0.25)

	EB.orbit(src, orbitsize, pick(FALSE, TRUE), rand(10, 25), pick(3, 4, 5, 6, 36))

/// Touching the ball dusts you (instead of the singularity's consume).
/obj/singularity/energy_ball/touched(datum/act/op/A)
	dust_mob(A.actor)
	return OP_OK

/obj/singularity/energy_ball/Bump(atom/A)
	dust_mob(A)

/// Whatever runs into the ball is dusted (instead of the singularity's consume).
/obj/singularity/energy_ball/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	if(N.bumper && !QDELETED(N.bumper))
		dust_mob(N.bumper)

/// The miniballs orbiting this ball (ghosts may orbit it too; they don't count).
/obj/singularity/energy_ball/proc/orbiting_balls()
	. = list()
	for(var/obj/singularity/energy_ball/EB in src?.orbiter_list())
		. += EB

/obj/singularity/energy_ball/orbit(obj/singularity/energy_ball/target)
	. = ..()
	if(istype(target))
		target.dissipate_strength = length(target.orbiting_balls()) + 1

/obj/singularity/energy_ball/orbit_ended(atom/center)
	. = ..()
	if(istype(center, /obj/singularity/energy_ball))
		var/obj/singularity/energy_ball/orbitingball = center
		orbitingball.dissipate_strength = length(orbitingball.orbiting_balls()) + 1
	if(!loc && !QDELETED(src))
		expire(0)

/obj/singularity/energy_ball/proc/dust_mob(mob/living/L)
	if(!istype(L) || L.is_incorporeal())
		return
	// L.dust() - Changing to do fatal elecrocution instead
	L.electrocute_act(500, src, def_zone = BP_TORSO)

/proc/tesla_zap(atom/source, zap_range = 3, power, explosive = FALSE, stun_mobs = TRUE, current_jumps)
	if(!source) // Some mobs and maybe some objects delete themselves when they die.
		return
	. = source.dir
	if(power < 1000)
		return
	if(current_jumps >= MAXIMUM_TESLA_JUMPS)
		return
	current_jumps++

	var/closest_dist = 0
	var/closest_atom
	var/obj/machinery/power/tesla_coil/closest_tesla_coil
	var/obj/machinery/power/grounding_rod/closest_grounding_rod
	var/mob/living/closest_mob
	var/obj/machinery/closest_machine
	var/obj/structure/closest_structure
	var/obj/structure/blob/closest_blob
	var/static/things_to_shock = typecacheof(list(/obj/machinery, /mob/living, /obj/structure))
	var/static/blacklisted_tesla_types = typecacheof(list(
										/obj/machinery/atmospherics,
										/obj/machinery/power/emitter,
										/obj/machinery/field_generator,
										/obj/machinery/door/blast,
										/obj/machinery/particle_accelerator/control_box,
										/obj/structure/particle_accelerator/fuel_chamber,
										/obj/structure/particle_accelerator/particle_emitter/center,
										/obj/structure/particle_accelerator/particle_emitter/left,
										/obj/structure/particle_accelerator/particle_emitter/right,
										/obj/structure/particle_accelerator/power_box,
										/obj/structure/particle_accelerator/end_cap,
										/obj/machinery/containment_field,
										/obj/structure/disposalpipe,
										/obj/structure/sign,
										/obj/machinery/gateway,
										/obj/structure/lattice,
										/obj/structure/grille,
										/obj/machinery/the_singularitygen/tesla))

	for(var/A in typecache_filter_multi_list_exclusion(oview(zap_range+2, source), things_to_shock, blacklisted_tesla_types))
		if(istype(A, /obj/machinery/power/tesla_coil))
			var/dist = get_dist(source, A)
			var/obj/machinery/power/tesla_coil/C = A
			if(!C.anchored)
				continue
			if(dist <= zap_range && (dist < closest_dist || !closest_tesla_coil) && !C.being_shocked)
				closest_dist = dist

				//we use both of these to save on istype and typecasting overhead later on
				//while still allowing common code to run before hand
				closest_tesla_coil = C
				closest_atom = C

		else if(closest_tesla_coil)
			continue //no need checking these other things

		else if(istype(A, /obj/machinery/power/grounding_rod))
			var/obj/machinery/power/grounding_rod/G = A
			var/dist = get_dist(source, A) - (G.anchored ? 2 : 0)
			if(dist <= zap_range && (dist < closest_dist || !closest_grounding_rod))
				closest_grounding_rod = A
				closest_atom = A
				closest_dist = dist

		else if(closest_grounding_rod)
			continue

		else if(isliving(A))
			var/dist = get_dist(source, A)
			var/mob/living/L = A
			if(om_has(L, EFFECT_GODMODE))
				continue
			if(dist <= zap_range && (dist < closest_dist || !closest_mob) && L.stat != DEAD && !has_trait(L, TRAIT_TESLA_SHOCKIMMUNE))
				closest_mob = L
				closest_atom = A
				closest_dist = dist

		else if(closest_mob)
			continue

		else if(istype(A, /obj/machinery))
			var/obj/machinery/M = A
			var/dist = get_dist(source, A)
			if(dist <= zap_range && (dist < closest_dist || !closest_machine) && !M.being_shocked)
				closest_machine = M
				closest_atom = A
				closest_dist = dist

		else if(closest_machine)
			continue

		else if(istype(A, /obj/structure/blob))
			var/obj/structure/blob/B = A
			var/dist = get_dist(source, A)
			if(dist <= zap_range && (dist < closest_dist || !closest_tesla_coil) && !B.being_shocked)
				closest_blob = B
				closest_atom = A
				closest_dist = dist

		else if(closest_blob)
			continue

		else if(istype(A, /obj/structure))
			var/obj/structure/S = A
			var/dist = get_dist(source, A)
			if(dist <= zap_range && (dist < closest_dist || !closest_tesla_coil) && !S.being_shocked)
				closest_structure = S
				closest_atom = A
				closest_dist = dist

	//Alright, we've done our loop, now lets see if was anything interesting in range
	if(closest_atom)
		//common stuff
		var/atom/srcLoc = get_turf(source) // Makes beams look nicer
		srcLoc.Beam(closest_atom, icon_state="lightning[rand(1,12)]", time=5, maxdistance = INFINITY) // Makes beams look nicer
		var/zapdir = get_dir(source, closest_atom)
		if(zapdir)
			. = zapdir

	var/drain_energy = FALSE // Safety First! Drain Tesla fast when its loose

	//per type stuff:
	if(closest_tesla_coil)
		closest_tesla_coil.tesla_act(power, explosive, stun_mobs, current_jumps = current_jumps)

	else if(closest_grounding_rod)
		closest_grounding_rod.tesla_act(power, explosive, stun_mobs, current_jumps = current_jumps)

	else if(closest_mob)
		var/shock_damage = CLAMP(round(power/400), 10, 90) + rand(-5, 5)
		closest_mob.electrocute_act(shock_damage, source, 1 - closest_mob.get_shock_protection(), ran_zone())
		log_game("TESLA([source.x],[source.y],[source.z]) Shocked [key_name(closest_mob)] for [shock_damage]dmg.")
		message_admins("Tesla zapped [key_name_admin(closest_mob)]!")
		if(issilicon(closest_mob))
			var/mob/living/silicon/S = closest_mob
			if(stun_mobs)
				S.emp_act(EMP_LIGHT)
			tesla_zap(closest_mob, 7, power / 1.5, explosive, stun_mobs, current_jumps = current_jumps) // metallic folks bounce it further
		else
			tesla_zap(closest_mob, 5, power / 1.5, explosive, stun_mobs, current_jumps = current_jumps)

	else if(closest_machine)
		drain_energy = TRUE // Safety First! Drain Tesla fast when its loose
		closest_machine.tesla_act(power, explosive, stun_mobs, current_jumps = current_jumps)

	else if(closest_blob)
		drain_energy = TRUE // Safety First! Drain Tesla fast when its loose
		closest_blob.tesla_act(power, explosive, stun_mobs, current_jumps = current_jumps)

	else if(closest_structure)
		drain_energy = TRUE // Safety First! Drain Tesla fast when its loose
		closest_structure.tesla_act(power, explosive, stun_mobs, current_jumps = current_jumps)

	// Safety First! Drain Tesla fast when its loose
	if(drain_energy && istype(source, /obj/singularity/energy_ball))
		var/obj/singularity/energy_ball/EB = source
		if (EB.energy > 0)
			EB.energy -= min(EB.energy, max(10, round(EB.energy * 0.05)))

#undef TESLA_DEFAULT_POWER
#undef TESLA_MINI_POWER
