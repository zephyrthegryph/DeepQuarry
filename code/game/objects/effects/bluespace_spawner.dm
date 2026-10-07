/obj/effect/bspawner
	name = "bluespace tear"
	desc = "An erratic portal of bluespace energies, its tear seems quite unstable but seems to endlessly create crystals. . ."
	anchored = 1
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "portalgateway"
	var/spawn_type = /obj/item/stack/telecrystal
	var/item_arg = 8
	var/time_between_spawn = 1 MINUTE
	var/time_to_end = 45 MINUTES
	var/spawned_num = 0
	EXPIRY_DECLARE(init_time)

/obj/effect/bspawner/Initialize(mapload)
	. = ..()
	EXPIRY_STAMP(src, init_time, CLOCK_WORLD)

CAPABILITIES(/obj/effect/bspawner)
	every(PROC_REF(spawn_delay), then(PROC_REF(spawn_due)))
	after_init(nameof(time_to_end), then(TYPE_PROC_REF(/datum, qdel_self)))

/// The deciseconds between items.
/obj/effect/bspawner/proc/spawn_delay(datum/act/A)
	return time_between_spawn

/// One item every time_between_spawn (every()) until time_to_end deletes it.
/obj/effect/bspawner/proc/spawn_due(datum/act/timer/A)
	spawn_item()
	spawned_num++

/obj/effect/bspawner/proc/spawn_item()
	if(!isnull(item_arg))
		new spawn_type(loc,item_arg)
	else
		new spawn_type(loc)

/obj/effect/bspawner/min30
	time_to_end = 30 MINUTES
