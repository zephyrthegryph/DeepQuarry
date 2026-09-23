/obj/effect/bspawner
	name = "bluespace tear"
	desc = "An erratic portal of bluespace energies, its tear seems quite unstable but seems to endlessly create crystals. . ."
	anchored = 1
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "portalgateway"
	var/obj/item_to_spawn = /obj/item/stack/telecrystal
	var/item_arg = 8
	var/time_between_spawn = 1 MINUTE
	var/time_to_end = 45 MINUTES
	var/spawned_num = 0
	var/init_time
	/// REACT_AT token for the next telecrystal spawn.
	var/tmp/spawn_timer
	/// REACT_AT token for the tear's collapse.
	var/tmp/end_timer

/obj/effect/bspawner/Initialize(mapload)
	. = ..()
	init_time = world.time
	spawn_timer = REACT_REARM(src, spawn_timer, init_time + time_between_spawn)
	end_timer = REACT_REARM(src, end_timer, init_time + time_to_end)

/obj/effect/bspawner/proc/spawn_item()
	if(!isnull(item_arg))
		new item_to_spawn(loc,item_arg)
	else
		new item_to_spawn(loc)

/obj/effect/bspawner/on_react(reason, source, source_kind)
	. = ..()
	if(!(reason & REACT_REASON_TIMER))
		return
	if(source == end_timer)
		end_timer = null
		qdel(src)
		return
	if(source == spawn_timer)
		spawn_timer = null
		spawn_item()
		spawned_num++
		spawn_timer = REACT_REARM(src, spawn_timer, init_time + time_between_spawn * (spawned_num + 1))

/obj/effect/bspawner/Destroy()
	spawn_timer = REACT_REARM(src, spawn_timer, null)
	end_timer = REACT_REARM(src, end_timer, null)
	. = ..()

/obj/effect/bspawner/min30
	time_to_end = 30 MINUTES
