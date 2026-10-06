//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:33

/obj/effect/accelerated_particle
	name = "Accelerated Particles"
	desc = "Small things moving very fast."
	icon = 'icons/obj/machines/particle_accelerator2.dmi'
	icon_state = "particle1"//Need a new icon for this
	anchored = TRUE
	density = TRUE
	movement_type = UNSTOPPABLE // for bumps to trigger
	var/movement_range = 10
	var/energy = 10		//energy in eV
	var/mega_energy = 0	//energy in MeV
	var/frequency = 1
	var/ionizing = 0
	var/particle_type
	var/additional_particles = 0
	var/tmp/turf/target
	var/tmp/turf/source
	var/movetotarget = 1

/// Flies one step every 0.1 s for as long as it exists; move() deletes it when its range runs out. A mob that walks into it is hit as if
/// the particle had hit it.
CAPABILITIES(/obj/effect/accelerated_particle)
	every(0.1 SECONDS, then(PROC_REF(move)))
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))
	param(nameof(dir), pos = 1, default = SOUTH)

/obj/effect/accelerated_particle/weak
	icon_state = "particle0"
	movement_range = 8
	energy = 5

/obj/effect/accelerated_particle/strong
	icon_state = "particle2"
	movement_range = 15
	energy = 15

/obj/effect/accelerated_particle/powerful
	icon_state = "particle3"
	movement_range = 25
	energy = 50

// ALLOW(init/INSTANCE_STATE): a particle starts moving the way it faces
/obj/effect/accelerated_particle/Initialize(mapload)
	. = ..()
	move()

/obj/effect/accelerated_particle/Bump(atom/A)
	if (A)
		if(ismob(A))
			toxmob(A)
		if(istype(A,/obj/machinery/the_singularitygen))
			var/obj/machinery/the_singularitygen/G = A
			G.set_energy(G.energy + energy)
		else if(istype(A,/obj/singularity))
			var/obj/singularity/G = A
			G.energy += energy
		else if(istype(A, /obj/machinery/particle_smasher))
			var/obj/machinery/particle_smasher/G = A
			G.set_energy(G.energy + energy)
		// R-UST fusion core and particle catcher deleted with the fusion
		// subsystem (depended on /obj/effect/fusion_em_field in core_field.dm).
		// Particles passing through where a fusion core used to be just continue
		// flying; if fusion is re-implemented on LINDA the energy-transfer branches
		// here should be restored.


/obj/effect/accelerated_particle/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	if(ismob(N.bumper))
		Bump(N.bumper)


/obj/effect/accelerated_particle/singularity_act()
	return

/obj/effect/accelerated_particle/proc/toxmob(mob/living/M)
	var/radiation = (energy*2)
	M.apply_effect((radiation*3),IRRADIATE,0)


/obj/effect/accelerated_particle/proc/move(datum/act/timer/A)
	if(target())
		if(movetotarget)
			if(!step_towards(src,target()) && !particle_force_step(get_step(src, get_dir(src,target()))))
				movement_range = 0 // left the map: deleted below
			if(get_dist(src,target()) < 1)
				movetotarget = 0
		else
			// get_step_away() already answers the turf to go to.
			var/turf/away = get_step_away(src, source())
			if(!(away && Move(away)) && !particle_force_step(away))
				movement_range = 0 // left the map: deleted below
	else
		if(!step(src,dir) && !particle_force_step(get_step(src,dir)))
			movement_range = 0 // left the map: fall through to the deletion below
	movement_range--
	if(movement_range <= 0)
		spent(src)

/// Pushes the particle onto `dest` when a normal step was blocked. At the map edge there is no
/// turf to push onto: the particle leaves the map (FALSE) and move() deletes it.
/obj/effect/accelerated_particle/proc/particle_force_step(turf/dest)
	if(!dest)
		return FALSE
	forceMove(dest)
	return TRUE

/// the source this refers to: a relation view, null once that is deleted.
/obj/effect/accelerated_particle/proc/source() as /turf
	return source

/// the target this refers to: a relation view, null once that is deleted.
/obj/effect/accelerated_particle/proc/target() as /turf
	return target
