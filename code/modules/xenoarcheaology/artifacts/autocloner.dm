/obj/machinery/auto_cloner
	name = "mysterious pod"
	desc = "It's full of a viscous liquid, but appears dark and silent."
	icon = 'icons/obj/cryogenics.dmi'
	icon_state = "cellold0"
	var/spawn_type
	var/time_spent_spawning = 0
	var/time_per_spawn = 0
	EXPIRY_DECLARE(last_process)
	density = TRUE
	var/previous_power_state = 0

	use_power = USE_POWER_IDLE
	active_power_usage = 2000
	idle_power_usage = 1000

CAPABILITIES(/obj/machinery/auto_cloner)
	started_work(step = PROC_REF(work_step), wakes_on = list(nameof(stat)), unpowered = TRUE)
	rolls(nameof(time_per_spawn), range_of(1200, 3600))
	rolls(nameof(spawn_type), PROC_REF(roll_spawn_type))

/// Rolled before init (rolls()): a third of the cloners grow something nasty.
/obj/machinery/auto_cloner/proc/roll_spawn_type(datum/roller/R)
	if(R.chance(33))
		return R.choose(list(/mob/living/simple_mob/animal/space/alien, /mob/living/simple_mob/animal/space/bear, /mob/living/simple_mob/creature,
			/mob/living/simple_mob/slime/xenobio, /mob/living/simple_mob/animal/space/carp))
	return R.choose(list(/mob/living/simple_mob/animal/passive/cat, /mob/living/simple_mob/animal/passive/dog/corgi,
		/mob/living/simple_mob/animal/passive/dog/corgi/puppy, /mob/living/simple_mob/animal/passive/chicken, /mob/living/simple_mob/animal/passive/cow,
		/mob/living/simple_mob/animal/passive/bird/parrot, /mob/living/simple_mob/animal/passive/crab, /mob/living/simple_mob/animal/passive/mouse,
		/mob/living/simple_mob/animal/passive/mothroach, /mob/living/simple_mob/animal/goat))

//todo: how the hell is the asteroid permanently powered?
/// Grows its mob while powered; unpowered, the half-grown mob breaks down and, once gone, the
/// cloner sleeps until power returns (a power change runs a step).
/obj/machinery/auto_cloner/proc/work_step(datum/act/timer/A)
	if(!last_process)
		EXPIRY_STAMP(src, last_process, CLOCK_WORLD)
	if(powered(power_channel))
		if(!previous_power_state)
			previous_power_state = 1
			icon_state = "cellold1"
			src.visible_message(span_notice("[icon2html(src,viewers(src))] [src] suddenly comes to life!"))

		//slowly grow a mob
		if(prob(5))
			src.visible_message(span_notice("[icon2html(src,viewers(src))] [src] [pick("gloops","glugs","whirrs","whooshes","hisses","purrs","hums","gushes")]."))

		//if we've finished growing...
		if(time_spent_spawning >= time_per_spawn)
			time_spent_spawning = 0
			set_use_power(USE_POWER_IDLE)
			src.visible_message(span_notice("[icon2html(src,viewers(src))] [src] pings!"))
			icon_state = "cellold1"
			desc = "It's full of a bubbling viscous liquid, and is lit by a mysterious glow."
			if(spawn_type)
				new spawn_type(src.loc)

		//if we're getting close to finished, kick into overdrive power usage
		if(time_spent_spawning / time_per_spawn > 0.75)
			set_use_power(USE_POWER_ACTIVE)
			icon_state = "cellold2"
			desc = "It's full of a bubbling viscous liquid, and is lit by a mysterious glow. A dark shape appears to be forming inside..."
		else
			set_use_power(USE_POWER_IDLE)
			icon_state = "cellold1"
			desc = "It's full of a bubbling viscous liquid, and is lit by a mysterious glow."

		time_spent_spawning = time_spent_spawning + world.time - last_process
	else
		if(previous_power_state)
			previous_power_state = 0
			icon_state = "cellold0"
			src.visible_message(span_notice("[icon2html(src,viewers(src))] [src] suddenly shuts down."))

		//cloned mob slowly breaks down
		time_spent_spawning = max(time_spent_spawning + last_process - world.time, 0)
		if(!time_spent_spawning)
			last_process = 0
			return PROCESS_KILL

	EXPIRY_STAMP(src, last_process, CLOCK_WORLD)
