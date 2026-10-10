#define XENOARCH_SPAWN_CHANCE 0.5
#define DIGSITESIZE_LOWER 4
#define DIGSITESIZE_UPPER 12
#define ARTIFACTSPAWNNUM_LOWER 18 	//This used to be 6-12 when xenoarch was performed on mostly a single Z level: The mining asteroid.
#define ARTIFACTSPAWNNUM_UPPER 36 	//Due to the increasing complexity of the game, that number resulted in current-day xenaorcheologists possibly being able to find one or maybe two artifacts a Z level.
									//This meant that xenoarch, an already tedious job, would be made even slower and more tedious and find very few large artifacts, which is the 'bulk' of their job. This should help alleviate that.
									//Ideally, this should be replaced with Z level specific (i.e. spawn 3-6 artifacts per Z level) spawns, but that is for the future.
									//For now, this is functional.
#define PROCEDURAL_LOWER 5			//These are high as the generation of them can could be laggy if spammed. This ONLY happens if the entire Z level has been depleted of large artifacts.
#define PROCEDURAL_UPPER 10			//It's easier to just go 'Here's more artifacts to dig up' and give xenoarch more to do.

// The xenoarchaeology system (was SSxenoarch): places digsites and large artifacts on the initialized map, and
// generates more when a z-level runs out. It has no periodic work. It needs the map's mineral turfs initialized, so
// it boots after SSatoms (its `needs`). The API is in xenoarch_api.dm.
SYSTEM_DEF(xenoarch)
	name = "Xenoarch"
	needs = list(/datum/system/atoms)
	var/list/artifact_spawning_turfs = list()
	var/list/digsite_spawning_turfs = list()

/datum/system/xenoarch/initialize()
	if(initialized)
		return
	initialized = TRUE
	var/started = REALTIMEOFDAY
	SetupXenoarch()
	log_world("Xenoarch system initialized: [length(digsite_spawning_turfs)] digsites, [length(artifact_spawning_turfs)] large artifacts in [(REALTIMEOFDAY - started) / 10]s.")

/datum/system/xenoarch/stat_entry(msg)
	return "[msg]Digsites: [length(digsite_spawning_turfs)] | Artifacts: [length(artifact_spawning_turfs)]"

/datum/system/xenoarch/proc/SetupXenoarch()
	for(var/turf/simulated/mineral/M in world) //This selects every mineral turf in the world
		if(!M.density) //Checks to see if it's a mineral wall
			continue

		if((M.z in using_map.xenoarch_exempt_levels) || !prob(XENOARCH_SPAWN_CHANCE)) //Now we roll the dice. Base chance is 1/200 for a mineral turf to spawn a digsite. If it doesn't roll that chance, we skip this rock.
			continue

		var/farEnough = 1
		for(var/turf/T as anything in digsite_spawning_turfs) //Did any other digsites within 5 tiles roll lucky on their chance?
			if(T in range(5, M))
				farEnough = 0
				break
		if(!farEnough) //If they did, let's not crowd the area with digsites. Skip this rock, even if it rolled well.
			continue

		rel_add(src, nameof(digsite_spawning_turfs), M) //This rock was lucky enough to be selected and not near any other sites!

		var/digsite = get_random_digsite_type() //What type of artifact site is this? Dictates what items will spawn.
		var/target_digsite_size = rand(DIGSITESIZE_LOWER, DIGSITESIZE_UPPER) //What the minimum size our digsite will be.

		var/list/processed_turfs = list()
		var/list/turfs_to_process = list(M)

		var/list/viable_adjacent_turfs = list()
		if(target_digsite_size > 1)
			for(var/turf/simulated/mineral/T in orange(2, M)) //With the rock being the center, check every rock around us within 2 tiles in each direction. So 5x5 square with our rock as the center.
				if(!T.density) //Is it an actual mineral wall?
					continue
				if(T.finds) //If the rock being checked has an artifact in it already, skip it.
					continue
				if(T in processed_turfs) //The rock has already been processed...This shouldn't happen since farEnough above ensures digsites can't be next to each other. Presumably, this is a failsafe.
					continue
				viable_adjacent_turfs.Add(T) //Add to the list of rocks we can select for this site.

			//Below determines how many artifacts containing tiles will actually spawn.
			target_digsite_size = min(target_digsite_size, viable_adjacent_turfs.len) //Min((4-12),25) with base settings, if there are tiles all around the deposit. If there are less tiles around the deposit, it'll be smaller than the target_size.effectively.

		for(var/i = 1 to target_digsite_size) //Go through all the selected turfs and let's start processing them!
			turfs_to_process += pick_n_take(viable_adjacent_turfs)

		while(turfs_to_process.len)
			var/turf/simulated/mineral/archeo_turf = pop(turfs_to_process)

			//Here, we start to see how many artifacts will spawn in the selected rock. 1-3 artifacts per.
			processed_turfs.Add(archeo_turf)
			if(isnull(archeo_turf.finds))
				if(prob(50))
					rel_add(archeo_turf, nameof(archeo_turf.finds), new /datum/find(digsite, rand(10, 190)))	//Dictates how far one has to dig to properly excavate the artifact. From 10-190
				else if(prob(75))
					rel_add(archeo_turf, nameof(archeo_turf.finds), new /datum/find(digsite, rand(10, 90)))	//High chance of being visible, alerting xenoarch to a digsite location.
					rel_add(archeo_turf, nameof(archeo_turf.finds), new /datum/find(digsite, rand(110, 190)))
				else
					rel_add(archeo_turf, nameof(archeo_turf.finds), new /datum/find(digsite, rand(10, 50)))
					rel_add(archeo_turf, nameof(archeo_turf.finds), new /datum/find(digsite, rand(60, 140)))
					rel_add(archeo_turf, nameof(archeo_turf.finds), new /datum/find(digsite, rand(150, 190)))

				//sometimes a find will be close enough to the surface to show
				var/datum/find/F = archeo_turf.finds[1]
				if(F.excavation_required <= F.view_range) //view_range is by default 40.
					archeo_turf.set_archaeo_overlay("overlay_archaeo[rand(1,3)]")

			//have a chance for an artifact to spawn here, but not in animal or plant digsites
			if(isnull(M.artifact_find) && digsite != DIGSITE_GARDEN)
				rel_add(src, nameof(artifact_spawning_turfs), archeo_turf)

		//Larger maps will convince byond this is an infinite loop, so let go for a second
		CHECK_TICK

	//create artifact machinery. Colloquially known as large artifacts.
	//Any artifact turfs except for garden & animal digsites can be selected.
	var/num_artifacts_spawn = rand(ARTIFACTSPAWNNUM_LOWER, ARTIFACTSPAWNNUM_UPPER)
	while(length(artifact_spawning_turfs) > num_artifacts_spawn)
		rel_remove(src, nameof(artifact_spawning_turfs), pick(artifact_spawning_turfs))

	//Actually adds the large artifacts to the areas, now that we have our selected locations.
	var/list/artifacts_spawnturf_temp = artifact_spawning_turfs ? artifact_spawning_turfs.Copy() : list()
	while(artifacts_spawnturf_temp.len > 0)
		var/turf/simulated/mineral/artifact_turf = pop(artifacts_spawnturf_temp)
		rel_set(artifact_turf, nameof(artifact_turf.artifact_find), new /datum/artifact_find())

/// This is the proc that is used when a Z level runs out of artifacts. This means you have 'completed' your job and now you get bonus goodies to keep you occupied.
/datum/system/xenoarch/proc/generate_more_artifacts(mob/living/user)

	/// So, to preface this, I had to do a lot of testing with this to ensure it wouldn't cause mass lag and that it properly functioned.
	/// At first, I tried to make it scan mineral in the user's Z. There's not really any preexisting functionality for this that I could find, so that was a negative.
	/// Next, I saw what would happen if it did 'in world' and then went 'if M.z != user.z continue' and that caused...A lot of lag. For a long time.
	/// This range(100) was for me was completely lagless. It gives a good amount of artifacts to keep digging and keep archeo working so they don't 'run out' of things to do.
	for(var/turf/simulated/mineral/M in range(100, user))

		if(!M.density)
			continue

		if(M.artifact_find)
			continue

		if(!prob(XENOARCH_SPAWN_CHANCE))
			continue

		var/farEnough = 1
		for(var/turf/T as anything in digsite_spawning_turfs)
			if(T in range(5, M))
				farEnough = 0
				break
		if(!farEnough)
			continue

		rel_add(src, nameof(digsite_spawning_turfs), M) //This rock was lucky enough to be selected and not near any other sites!

		var/digsite = get_random_digsite_type() //What type of artifact site is this? Dictates what items will spawn.
		var/target_digsite_size = rand(DIGSITESIZE_LOWER, DIGSITESIZE_UPPER) //What the minimum size our digsite will be.

		var/list/processed_turfs = list()
		var/list/turfs_to_process = list(M)

		var/list/viable_adjacent_turfs = list()
		if(target_digsite_size > 1)
			for(var/turf/simulated/mineral/T in orange(2, M)) //With the rock being the center, check every rock around us within 2 tiles in each direction. So 5x5 square with our rock as the center.
				if(!T.density) //Is it an actual mineral wall?
					continue
				if(T.finds) //If the rock being checked has an artifact in it already, skip it.
					continue
				if(T in processed_turfs) //The rock has already been processed...This shouldn't happen since farEnough above ensures digsites can't be next to each other. Presumably, this is a failsafe.
					continue
				viable_adjacent_turfs.Add(T) //Add to the list of rocks we can select for this site.

			//Below determines how many artifacts containing tiles will actually spawn.
			target_digsite_size = min(target_digsite_size, viable_adjacent_turfs.len) //Min((4-12),25) with base settings, if there are tiles all around the deposit. If there are less tiles around the deposit, it'll be smaller than the target_size.effectively.

		for(var/i = 1 to target_digsite_size) //Go through all the selected turfs and let's start processing them!
			turfs_to_process += pick_n_take(viable_adjacent_turfs)

		while(turfs_to_process.len)
			var/turf/simulated/mineral/archeo_turf = pop(turfs_to_process)

			//Here, we start to see how many artifacts will spawn in the selected rock. 1-3 artifacts per.
			processed_turfs.Add(archeo_turf)
			if(isnull(archeo_turf.finds))
				if(prob(50))
					rel_add(archeo_turf, nameof(archeo_turf.finds), new /datum/find(digsite, rand(10, 190)))	//Dictates how far one has to dig to properly excavate the artifact. From 10-190
				else if(prob(75))
					rel_add(archeo_turf, nameof(archeo_turf.finds), new /datum/find(digsite, rand(10, 90)))	//High chance of being visible, alerting xenoarch to a digsite location.
					rel_add(archeo_turf, nameof(archeo_turf.finds), new /datum/find(digsite, rand(110, 190)))
				else
					rel_add(archeo_turf, nameof(archeo_turf.finds), new /datum/find(digsite, rand(10, 50)))
					rel_add(archeo_turf, nameof(archeo_turf.finds), new /datum/find(digsite, rand(60, 140)))
					rel_add(archeo_turf, nameof(archeo_turf.finds), new /datum/find(digsite, rand(150, 190)))

				//sometimes a find will be close enough to the surface to show
				var/datum/find/F = archeo_turf.finds[1]
				if(F.excavation_required <= F.view_range) //view_range is by default 40.
					archeo_turf.set_archaeo_overlay("overlay_archaeo[rand(1,3)]")

			//have a chance for an artifact to spawn here, but not in animal or plant digsites
			if(isnull(M.artifact_find) && digsite != DIGSITE_GARDEN)
				rel_add(src, nameof(artifact_spawning_turfs), archeo_turf)

		//Larger maps will convince byond this is an infinite loop, so let go for a second
		CHECK_TICK

	//create artifact machinery. Colloquially known as large artifacts.
	//Any artifact turfs except for garden & animal digsites can be selected.
	var/num_artifacts_spawn = rand(PROCEDURAL_LOWER, PROCEDURAL_UPPER) //Our random generation will spawn fewer new large artifacts. Remember, this is for our Z level, not the whole map!
	while(length(artifact_spawning_turfs) > num_artifacts_spawn)
		rel_remove(src, nameof(artifact_spawning_turfs), pick(artifact_spawning_turfs))

	//Actually adds the large artifacts to the areas, now that we have our selected locations.
	var/list/artifacts_spawnturf_temp = artifact_spawning_turfs ? artifact_spawning_turfs.Copy() : list()
	while(artifacts_spawnturf_temp.len > 0)
		var/turf/simulated/mineral/artifact_turf = pop(artifacts_spawnturf_temp)
		rel_set(artifact_turf, nameof(artifact_turf.artifact_find), new /datum/artifact_find())

#undef XENOARCH_SPAWN_CHANCE
#undef DIGSITESIZE_LOWER
#undef DIGSITESIZE_UPPER
#undef ARTIFACTSPAWNNUM_LOWER
#undef ARTIFACTSPAWNNUM_UPPER
#undef PROCEDURAL_LOWER
#undef PROCEDURAL_UPPER
