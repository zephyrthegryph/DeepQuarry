// Boot-time memory profiler. Runs once a few seconds after world init.
// Counts every atom in the world by type prefix, then logs the top N.
// BYOND has no built-in heap breakdown — this is the closest we get to
// "where does memory go" without external tooling.
//
// Each atom in DM is roughly 200-600 bytes depending on type. Multiplying
// the type counts by a rough per-type estimate gives a sense of which
// type categories dominate. Note: this only sees atoms (turfs, objs, mobs,
// effects). Pure datums (configs, controllers, etc.) are NOT counted here.

/proc/quarry_profile_atoms()
	var/list/counts = list()
	// Group by the leftmost two path segments — e.g.
	// /turf/simulated/mineral/cave/quarry becomes "/turf/simulated".
	for(var/atom/A as anything in world)
		if(!A)
			continue
		var/path = "[A.type]"
		var/list/parts = splittext(path, "/")
		// parts[1] is "" (leading slash), parts[2] = top group, parts[3] = sub.
		var/key
		if(length(parts) >= 3)
			key = "/[parts[2]]/[parts[3]]"
		else if(length(parts) >= 2)
			key = "/[parts[2]]"
		else
			key = path
		counts[key] = (counts[key] || 0) + 1

	// Sort by count descending. BYOND doesn't have a native sort-by-value,
	// so do it manually: pull keys into a list, sort by their counts.
	var/list/sorted_keys = list()
	for(var/k in counts)
		sorted_keys += k
	// Bubble-sortish for clarity — N ~50 keys so fine.
	for(var/i in 1 to length(sorted_keys) - 1)
		for(var/j in 1 to length(sorted_keys) - i)
			if(counts[sorted_keys[j]] < counts[sorted_keys[j + 1]])
				var/tmp = sorted_keys[j]
				sorted_keys[j] = sorted_keys[j + 1]
				sorted_keys[j + 1] = tmp

	log_game("=== quarry profile: atom counts by top-level path ===")
	var/total = 0
	for(var/k in counts)
		total += counts[k]
	log_game("total atoms: [total]")
	var/shown = 0
	for(var/k as anything in sorted_keys)
		if(shown >= 30)
			break
		log_game("  [k]: [counts[k]]")
		shown++

	// Also count the most populous specific types (full path).
	var/list/exact = list()
	for(var/atom/A as anything in world)
		var/path = "[A.type]"
		exact[path] = (exact[path] || 0) + 1
	var/list/sorted_exact = list()
	for(var/k in exact)
		sorted_exact += k
	for(var/i in 1 to length(sorted_exact) - 1)
		for(var/j in 1 to length(sorted_exact) - i)
			if(exact[sorted_exact[j]] < exact[sorted_exact[j + 1]])
				var/tmp = sorted_exact[j]
				sorted_exact[j] = sorted_exact[j + 1]
				sorted_exact[j + 1] = tmp
	log_game("=== quarry profile: top 30 exact types ===")
	shown = 0
	for(var/k as anything in sorted_exact)
		if(shown >= 30)
			break
		log_game("  [k]: [exact[k]]")
		shown++

	// Also report some heavy globals that aren't atoms.
	log_game("=== quarry profile: notable global lists ===")
	log_game("  GLOB.clients: [length(GLOB.clients)]")
	log_game("  GLOB.player_list: [length(GLOB.player_list)]")
	log_game("  GLOB.preferences_datums: [length(GLOB.preferences_datums)]")
	if(SSquarry)
		log_game("  SSquarry.layers: [length(SSquarry.layers)]")
		log_game("  SSquarry.configs: [length(SSquarry.configs)]")
	log_game("  world.maxx x maxy x maxz: [world.maxx] x [world.maxy] x [world.maxz]")
	log_game("=== quarry profile: end ===")
