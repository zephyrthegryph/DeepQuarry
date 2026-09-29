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
	var/init_time

/obj/effect/bspawner/Initialize(mapload)
	. = ..()
	init_time = world.time

DECLARE_START_TIMER(/obj/effect/bspawner, "time_between_spawn", PROC_REF(spawn_due))
DECLARE_START_TIMER(/obj/effect/bspawner, "time_to_end", /datum/proc/qdel_self)

/// One item every time_between_spawn (its timer re-arms) until time_to_end deletes it.
/obj/effect/bspawner/proc/spawn_due()
	if(QDELETED(src))
		return
	spawn_item()
	spawned_num++
	om_after(src, time_between_spawn, PROC_REF(spawn_due))

/obj/effect/bspawner/proc/spawn_item()
	if(!isnull(item_arg))
		new spawn_type(loc,item_arg)
	else
		new spawn_type(loc)

/obj/effect/bspawner/min30
	time_to_end = 30 MINUTES
