// the resolver is declared in the block at the end

/obj/random
	spawn_types = list(1)
/obj/random/proc/roll()
	return 1
/obj/random_multi/foo
	var/list/to_spawn = list(a)
/obj/random_multi/item_to_spawn()
	return 2
/obj/random/thing
	possible_things = list(a)
	var/possible_b = list(b)
	var/list/items = list(c)
	var/other = list(d)
	var/list/big_loot = list(e)
	items = list(f) // ALLOW(sys_random_spawn_list): ok
	// items = list(g)
	// ALLOW(sys_random_spawn_list): above
	items = list(h)
/obj/random/other/proc/x() // c
/obj/random/other/verb/y()
/obj/random/other/z()
/obj/randomized/z()
/obj/spawn/child
	items = list(i)
/obj/spawn
	spawn_types = list(j)
/obj/unrelated
	items = list(k)
/obj/unrelated // comment
	items = list(l)
/obj/unrelated/foo()
	items = list(m)
/obj/spawnx/child
	items = list(n)
/datum/loot_table/x
var/t = loot_table_type
x = loot_reward (a)
x = item_to_spawn()
var/y = item_to_spawn_foo
// item_to_spawn
x = "item_to_spawn"
x = loot_reward(1) // ALLOW(sys_loot_table_datum): ok
// ALLOW(sys_item_to_spawn): above
item_to_spawn()
/datum/loot_tablex
/obj/random/trailing
	items = list(o)

	items = list(p)
CAPABILITIES(/obj/spawn)
	map_resolver(PROC_REF(r))
