#define SD_FLOOR_TILE 0
#define SD_WALL_TILE 1
#define SD_DOOR_TILE 2
#define SD_EMPTY_TILE 3
#define SD_SUPPLY_TILE 7

/datum/random_map/droppod
	descriptor = "drop pod"
	initial_wall_cell = 0
	limit_x = 3
	limit_y = 3
	preserve_map = 0
	max_attempts = 1

	wall_type = /turf/simulated/wall/titanium
	floor_type = /turf/simulated/floor/reinforced
	var/list/supplied_drop_types
	var/door_type = /obj/structure/droppod_door
	var/drop_type = /mob/living/simple_mob/animal/passive/bird/parrot
	var/auto_open_doors

	var/placement_explosion_dev =   1
	var/placement_explosion_heavy = 2
	var/placement_explosion_light = 6
	var/placement_explosion_flash = 4

/datum/random_map/droppod/New(seed, tx, ty, tz, tlx, tly, do_not_apply, do_not_announce, supplied_drop, list/supplied_drops, automated)

	if(supplied_drop)
		drop_type = supplied_drop
	else if(islist(supplied_drops) && supplied_drops.len)
		supplied_drop_types = supplied_drops
		drop_type = "custom"
	if(automated)
		auto_open_doors = 1

	//Make sure there is a clear midpoint.
	if(limit_x % 2 == 0) limit_x++
	if(limit_y % 2 == 0) limit_y++
	..()

/datum/random_map/droppod/generate_map()

	// No point calculating these 200 times.
	var/x_midpoint = n_ceil(limit_x / 2)
	var/y_midpoint = n_ceil(limit_y / 2)

	// Draw walls/floors/doors.
	for(var/x = 1, x <= limit_x, x++)
		for(var/y = 1, y <= limit_y, y++)
			var/current_cell = get_map_cell(x,y)
			if(!current_cell)
				continue

			var/on_x_bound = (x == 1 || x == limit_x)
			var/on_y_bound = (y == 1 || y == limit_y)
			var/draw_corners = (limit_x < 5 && limit_y < 5)
			if(on_x_bound || on_y_bound)
				// Draw access points in midpoint of each wall.
				if(x == x_midpoint || y == y_midpoint)
					map[current_cell] = SD_DOOR_TILE
				// Draw the actual walls.
				else if(draw_corners || (!on_x_bound || !on_y_bound))
					map[current_cell] = SD_WALL_TILE
				//Don't draw the far corners on large pods.
				else
					map[current_cell] = SD_EMPTY_TILE
			else
				// Fill in the corners.
				if((x == 2 || x == (limit_x-1)) && (y == 2 || y == (limit_y-1)))
					map[current_cell] = SD_WALL_TILE
				// Fill in EVERYTHING ELSE.
				else
					map[current_cell] = SD_FLOOR_TILE

	// Draw the drop contents.
	var/current_cell = get_map_cell(x_midpoint,y_midpoint)
	if(current_cell)
		map[current_cell] = SD_SUPPLY_TILE
	return 1

/datum/random_map/droppod/apply_to_map()
	if(placement_explosion_dev || placement_explosion_heavy || placement_explosion_light || placement_explosion_flash)
		var/turf/T = locate((origin_x + n_ceil(limit_x / 2)-1), (origin_y + n_ceil(limit_y / 2)-1), origin_z)
		if(istype(T))
			explosion(T, placement_explosion_dev, placement_explosion_heavy, placement_explosion_light, placement_explosion_flash)
			// Let the explosion finish proccing before we ChangeTurf(), otherwise it might destroy our spawned objects.
			om_after(src, 1.5 SECONDS, PROC_REF(apply_cells))
			return
	return ..()

/datum/random_map/droppod/get_appropriate_path(value)
	if(value == SD_FLOOR_TILE || value == SD_SUPPLY_TILE)
		return floor_type
	else if(value == SD_WALL_TILE)
		return wall_type
	else if(value == SD_DOOR_TILE )
		return wall_type
	return null

// Pods are circular. Get the direction this object is facing from the center of the pod.
/datum/random_map/droppod/get_spawn_dir(x, y)
	var/x_midpoint = n_ceil(limit_x / 2)
	var/y_midpoint = n_ceil(limit_y / 2)
	if(x == x_midpoint && y == y_midpoint)
		return null
	var/turf/target = locate(origin_x+x-1, origin_y+y-1, origin_z)
	var/turf/middle = locate(origin_x+x_midpoint-1, origin_y+y_midpoint-1, origin_z)
	if(!istype(target) || !istype(middle))
		return null
	return get_dir(middle, target)

/datum/random_map/droppod/get_additional_spawns(value, turf/T, spawn_dir)

	// Splatter anything under us that survived the explosion.
	if(value != SD_EMPTY_TILE && T.contents.len)
		for(var/atom/movable/AM in turf_contents_of_type(T, /atom/movable))
			if(AM.simulated && !istype(AM, /mob/observer))
				qdel(AM)

	// Also spawn doors and loot.
	if(value == SD_DOOR_TILE)
		var/obj/structure/S = new door_type(T, auto_open_doors)
		S.set_dir(spawn_dir)

	else if(value == SD_SUPPLY_TILE)
		get_spawned_drop(T)

/datum/random_map/droppod/proc/get_spawned_drop(turf/T)
	var/obj/structure/bed/chair/C = new(T)
	C.set_light(3, l_color = "#CC0000")
	var/mob/living/drop
	// This proc expects a list of mobs to be passed to the spawner.
	// Use the supply pod if you don't want to drop mobs.
	// Mobs will not double up; if you want multiple mobs, you
	// will need multiple drop tiles.
	if(islist(supplied_drop_types) && length(supplied_drop_types))
		while(length(supplied_drop_types))
			drop = DEFAULTPICK(supplied_drop_types, null)
			LAZYREMOVE(supplied_drop_types, drop)
			if(istype(drop))
				drop.tag = null
				if(drop?.buckled_to())
					var/atom/movable/_tmp_buck_37 = drop?.buckled_to()
					_tmp_buck_37.unbuckle_mob(drop, TRUE)
				drop.forceMove(T)
	else if(ispath(drop_type))
		drop = new drop_type(T)
		if(istype(drop))
			if(drop?.buckled_to())
				var/atom/movable/_tmp_buck_38 = drop?.buckled_to()
				_tmp_buck_38.unbuckle_mob(drop, TRUE)
			drop.forceMove(T)

ADMIN_VERB(call_drop_pod, R_FUN, "Call Drop Pod", "Call an immediate drop pod on your location.", ADMIN_CATEGORY_FUN_DROP_POD)
	// Everything is asked before anything is made: each answer re-runs this verb.
	var/spawn_path = verb_ask(user, "path", args, /datum/om/prompt/choice, message = "Select a mob type.", title = "Drop Pod Selection", choices = subtypesof(/mob/living))
	if(!ispath(spawn_path, /mob/living))
		return

	var/input = verb_ask(user, "player", args, /datum/om/prompt/choice/alert, message = "Do you wish the mob to have a player?", title = "Assign Player?", choices = list("No","Yes"))
	if(!input)
		return
	var/spawn_count = 0
	var/client/selected_player
	var/antag_type
	if(input == "No")
		spawn_count = verb_ask(user, "count", args, /datum/om/prompt/number, message = "How many mobs do you wish the pod to contain?", title = "Drop Pod Selection", min = 1)
		if(isnull(spawn_count) || spawn_count <= 0)
			return
	else
		var/list/candidates = list()
		for(var/client/player in GLOB.clients)
			if(player.mob && isobserver(player.mob))
				candidates[player.ckey] = player

		if(!candidates.len)
			to_chat(user, "There are no candidates for a drop pod launch.")
			return

		// Get a player and a mob type.
		var/player_ckey = verb_ask(user, "ckey", args, /datum/om/prompt/choice, message = "Select a player.", title = "Drop Pod Selection", choices = candidates)
		if(!player_ckey)
			return
		selected_player = candidates[player_ckey]
		if(!selected_player)
			to_chat(user, "That player is no longer a candidate.")
			return

		// Equip them, if they are human and it is desirable.
		if(ispath(spawn_path, /mob/living/carbon/human))
			antag_type = verb_ask(user, "antag", args, /datum/om/prompt/choice, message = "Select an equipment template to use or cancel for nude.", title = "Drop Pod Selection", choices = SSantag_job.all_antag_types, cancel_answer = "")
			if(isnull(antag_type))
				return

	if(verb_ask(user, "sure", args, /datum/om/prompt/choice/alert, message = "Are you SURE you wish to deploy this drop pod? It will cause a sizable explosion and gib anyone underneath it.", title = "Danger!", choices = list("No","Yes")) != "Yes")
		return

	var/mob/living/spawned_mob
	var/list/spawned_mobs = list()
	if(selected_player)
		// Spawn the mob in nullspace for now.
		spawned_mob = new spawn_path()
		spawned_mob.tag = "awaiting drop"
		if(antag_type)
			var/datum/antagonist/A = SSantag_job.all_antag_types[antag_type]
			A?.equip(spawned_mob)
	else
		for(var/i=0;i<spawn_count;i++)
			var/mob/living/M = new spawn_path()
			M.tag = "awaiting drop"
			spawned_mobs |= M

	// Chuck them into the pod.
	var/automatic_pod
	var/mob/user_mob = user.mob
	if(spawned_mob && selected_player)
		if(isliving(selected_player.mob))
			move_player(selected_player.mob, spawned_mob, "dropped in a pod by [key_name(user)]")
		else if(selected_player.mob.mind)
			transfer_mind(selected_player.mob.mind, spawned_mob, "dropped in a pod by [key_name(user)]", force = TRUE)
		else
			spawned_mob.ckey = selected_player.mob.ckey // an observer without a character: first assignment
		spawned_mobs = list(spawned_mob)
		message_admins("[key_name(user)] dropped a pod containing \the [spawned_mob] ([spawned_mob.key]) at ([user_mob.x],[user_mob.y],[user_mob.z])")
		log_admin("[key_name(user)] dropped a pod containing \the [spawned_mob] ([spawned_mob.key]) at ([user_mob.x],[user_mob.y],[user_mob.z])")
	else if(spawned_mobs.len)
		automatic_pod = 1
		message_admins("[key_name(user)] dropped a pod containing [length(spawned_mobs)] [LAZYACCESS(spawned_mobs, 1)] at ([user_mob.x],[user_mob.y],[user_mob.z])")
		log_admin("[key_name(user)] dropped a pod containing [length(spawned_mobs)] [LAZYACCESS(spawned_mobs, 1)] at ([user_mob.x],[user_mob.y],[user_mob.z])")
	else
		return

	new /datum/random_map/droppod(null, user_mob.x-1, user_mob.y-1, user_mob.z, supplied_drops = spawned_mobs, automated = automatic_pod)

#undef SD_FLOOR_TILE
#undef SD_WALL_TILE
#undef SD_DOOR_TILE
#undef SD_EMPTY_TILE
#undef SD_SUPPLY_TILE
