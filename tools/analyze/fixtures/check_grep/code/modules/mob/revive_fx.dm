/proc/revive_fx(M)
	dead_mob_list -= M
	dead_mob_list.Remove(M)
	living_mob_list += M
	living_mob_list |= M
	living_mob_list.Add(M)
	registry_leave(REGISTRY_DEAD_MOBS, M)
	registry_join(REGISTRY_LIVING_MOBS, M)
	M.timeofdeath = 0
	timeofdeath = null
	timeofdeath = world.time
	var/x = dead_mob_list -= 1
	dead_mob_list += M
	dead_mob_list -= M // ALLOW(check_grep): ok
