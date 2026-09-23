/obj/structure/prop/nest
	name = "diyaab den"
	desc = "A den of some creature."
	icon = 'icons/obj/structures.dmi'
	icon_state = "bonfire"
	density = TRUE
	anchored = TRUE
	interaction_message = span_warning("You feel like you shouldn't be sticking your nose into a wild animal's den.")

	var/disturbance_spawn_chance = 20
	var/last_spawn
	var/spawn_delay = 150
	var/randomize_spawning = FALSE
	var/creature_types = list(/mob/living/simple_mob/animal/sif/diyaab)
	var/list/den_mobs
	var/den_faction			//The faction of any spawned creatures.
	var/max_creatures = 3	//Maximum number of living creatures this nest can have at one time.

	var/tally = 0				//The counter referenced against total_creature_max, or just to see how many mobs it has spawned.
	var/total_creature_max	//If set, it can spawn this many creatures, total, ever.

	/// REACT_AT token for the next creature spawn attempt; null when not scheduled.
	var/tmp/nest_spawn_timer

/obj/structure/prop/nest/Initialize(mapload)
	. = ..()
	den_mobs = list()
	REACT_PROCESS(src, 2 SECONDS, "prunes dead creatures from its den roster every tick")
	last_spawn = world.time
	if(randomize_spawning) //Not the biggest shift in spawntime, but it's here.
		var/delayshift_clamp = spawn_delay / 10
		var/delayshift = rand(delayshift_clamp, -1 * delayshift_clamp)
		spawn_delay += delayshift
	nest_spawn_timer = REACT_REARM(src, nest_spawn_timer, last_spawn + spawn_delay)

/obj/structure/prop/nest/Destroy()
	den_mobs = null
	REACT_PROCESS_STOP(src)
	nest_spawn_timer = REACT_REARM(src, nest_spawn_timer, null)
	. = ..()

/obj/structure/prop/nest/attack_hand(mob/living/user) // Used to tell the player that this isn't useful for anything.
	..()
	if(user && prob(disturbance_spawn_chance))
		spawn_creature(get_turf(src))

/obj/structure/prop/nest/process()
	update_creatures()

/obj/structure/prop/nest/on_react(reason, source, source_kind)
	. = ..()
	if(!(reason & REACT_REASON_TIMER) || source != nest_spawn_timer)
		return
	nest_spawn_timer = null
	spawn_creature(get_turf(src))
	nest_spawn_timer = REACT_REARM(src, nest_spawn_timer, max(last_spawn + spawn_delay, world.time + 2 SECONDS))

/obj/structure/prop/nest/proc/spawn_creature(turf/spawnpoint)
	update_creatures() //Paranoia.
	if(total_creature_max && tally >= total_creature_max)
		return
	if(istype(spawnpoint) && den_mobs.len < max_creatures)
		last_spawn = world.time
		var/spawn_choice = pick(creature_types)
		var/mob/living/L = new spawn_choice(spawnpoint)
		if(den_faction)
			L.faction = den_faction
		visible_message(span_warning("\The [L] crawls out of \the [src]."))
		den_mobs += L
		tally++

/obj/structure/prop/nest/proc/remove_creature(mob/target)
	den_mobs -= target

/obj/structure/prop/nest/proc/update_creatures()
	for(var/mob/living/L in den_mobs)
		if(L.stat == 2)
			remove_creature(L)
