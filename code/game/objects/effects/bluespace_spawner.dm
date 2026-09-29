/obj/effect/bspawner
	name = "bluespace tear"
	desc = "An erratic portal of bluespace energies, its tear seems quite unstable but seems to endlessly create crystals. . ."
	anchored = 1
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "portalgateway"
	var/item_to_spawn = /obj/item/stack/telecrystal
	var/item_arg = 8
	var/time_between_spawn = 1 MINUTE
	var/time_to_end = 45 MINUTES
	var/spawned_num = 0
	EXPIRY_DECLARE(init_time)

/obj/effect/bspawner/Initialize(mapload)
	. = ..()
	EXPIRY_STAMP(src, init_time, CLOCK_WORLD)

DECLARE_REPEAT(/obj/effect/bspawner, "time_between_spawn", spawn_due, null)
DECLARE_START_TIMER(/obj/effect/bspawner, "time_to_end", /datum/proc/qdel_self)

/// One item every time_between_spawn (declared repeat) until time_to_end deletes it.
/obj/effect/bspawner/proc/spawn_due()
	if(QDELETED(src))
		return REPEAT_STOP
	spawn_item()
	spawned_num++

/obj/effect/bspawner/proc/spawn_item()
	if(!isnull(item_arg))
		new item_to_spawn(loc,item_arg)
	else
		new item_to_spawn(loc)

/obj/effect/bspawner/min30
	time_to_end = 30 MINUTES
