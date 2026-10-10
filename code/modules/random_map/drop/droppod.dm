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
			after(src, 1.5 SECONDS, PROC_REF(apply_cells))
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
	if(value != SD_EMPTY_TILE && contents_count(T))
		for(var/atom/movable/AM in turf_contents_of_type(T, /atom/movable))
			if(AM.simulated && !istype(AM, /mob/observer))
				spent(AM)

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

#define DROP_POD_PATH "path"
#define DROP_POD_PLAYER "player"
#define DROP_POD_COUNT "count"
#define DROP_POD_CKEY "ckey"
#define DROP_POD_ANTAG "antag"
#define DROP_POD_SURE "sure"
#define DROP_POD_OFFER_REFUSAL "offer_refusal"

ADMIN_VERB(call_drop_pod, R_FUN, "Call Drop Pod", "Call an immediate drop pod on your location.", ADMIN_CATEGORY_FUN_DROP_POD)
	ask_drop_pod_step(user.mob, list(), DROP_POD_PATH)

/datum/admin_verb/call_drop_pod/proc/drop_pod_candidates()
	var/list/candidates = list()
	for(var/client/player in GLOB.clients)
		if(player.mob && isobserver(player.mob))
			candidates[player.ckey] = player
	return candidates

/datum/admin_verb/call_drop_pod/proc/drop_pod_state_refusal(datum/request/R)
	if(QDELETED(R.answerer) || !R.answerer.client)
		return "gone"
	var/list/state = R.captured
	if(R.step_name != DROP_POD_PATH && !ispath(state[DROP_POD_PATH], /mob/living))
		return "invalid path"
	if(R.step_name == DROP_POD_COUNT && !isnull(R.value) && R.value <= 0)
		return "invalid count"
	if(state[DROP_POD_PLAYER] == "Yes")
		var/list/candidates = drop_pod_candidates()
		if(!length(candidates))
			return "no candidates"
		if(R.step_name == DROP_POD_CKEY && !isnull(R.value) && !candidates[R.value])
			return "candidate left"
		if(R.step_name != DROP_POD_CKEY && !candidates[state[DROP_POD_CKEY]])
			return "candidate left"
	return null

/datum/admin_verb/call_drop_pod/proc/drop_pod_refusal_notice(mob/user, reason)
	if(reason == "no candidates")
		to_chat(user, "There are no candidates for a drop pod launch.")
	else if(reason == "candidate left")
		to_chat(user, "That player is no longer a candidate.")

/datum/prompt/choice/admin_drop_pod
	rights = R_FUN
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/admin_drop_pod/prepare(datum/act/A)
	. = ..()
	captured[DROP_POD_OFFER_REFUSAL] = request_recheck(src)

/datum/prompt/choice/admin_drop_pod/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_verb/call_drop_pod/verb = owner
	return verb.drop_pod_state_refusal(src)

/datum/prompt/number/admin_drop_pod
	rights = R_FUN
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/number/admin_drop_pod/prepare(datum/act/A)
	. = ..()
	captured[DROP_POD_OFFER_REFUSAL] = request_recheck(src)

/datum/prompt/number/admin_drop_pod/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_verb/call_drop_pod/verb = owner
	return verb.drop_pod_state_refusal(src)

/datum/prompt/number/admin_drop_pod/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title, default, INFINITY, 1, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/admin_verb/call_drop_pod/proc/ask_drop_pod_step(mob/user, list/state, step)
	switch(step)
		if(DROP_POD_PATH)
			open_request(src, /datum/prompt/choice/admin_drop_pod, PROC_REF(drop_pod_answered), answerer = user, captured = state.Copy(), step_name = step, question = "Select a mob type.", title = "Drop Pod Selection", choices = subtypesof(/mob/living))
		if(DROP_POD_PLAYER)
			open_request(src, /datum/prompt/choice/admin_drop_pod, PROC_REF(drop_pod_answered), answerer = user, captured = state.Copy(), step_name = step, question = "Do you wish the mob to have a player?", title = "Assign Player?", choices = list("No","Yes"), buttons = TRUE)
		if(DROP_POD_COUNT)
			open_request(src, /datum/prompt/number/admin_drop_pod, PROC_REF(drop_pod_answered), answerer = user, captured = state.Copy(), step_name = step, question = "How many mobs do you wish the pod to contain?", title = "Drop Pod Selection")
		if(DROP_POD_CKEY)
			open_request(src, /datum/prompt/choice/admin_drop_pod, PROC_REF(drop_pod_answered), answerer = user, captured = state.Copy(), step_name = step, question = "Select a player.", title = "Drop Pod Selection", choices = drop_pod_candidates())
		if(DROP_POD_ANTAG)
			open_request(src, /datum/prompt/choice/admin_drop_pod, PROC_REF(drop_pod_answered), answerer = user, captured = state.Copy(), step_name = step, question = "Select an equipment template to use or cancel for nude.", title = "Drop Pod Selection", choices = antag_all_antag_types())
		if(DROP_POD_SURE)
			open_request(src, /datum/prompt/choice/admin_drop_pod, PROC_REF(drop_pod_answered), answerer = user, captured = state.Copy(), step_name = step, question = "Are you SURE you wish to deploy this drop pod? It will cause a sizable explosion and gib anyone underneath it.", title = "Danger!", choices = list("No","Yes"), buttons = TRUE)

/datum/admin_verb/call_drop_pod/proc/drop_pod_answered(datum/act/request/A)
	var/mob/actor = A.request.answerer
	var/list/state = A.request.captured.Copy()
	var/step = A.request.step_name
	if(!A.answer)
		if(state[DROP_POD_OFFER_REFUSAL])
			drop_pod_refusal_notice(actor, state[DROP_POD_OFFER_REFUSAL])
			return
		if(!isnull(A.request.value))
			drop_pod_refusal_notice(actor, A.request.last_error)
			return
		if(step != DROP_POD_ANTAG || A.request.outcome != REQ_CANCELLED)
			return
		var/reason = request_recheck(A.request)
		if(reason)
			drop_pod_refusal_notice(actor, reason)
			return
		state[DROP_POD_ANTAG] = ""
		ask_drop_pod_step(actor, state, DROP_POD_SURE)
		return
	state[step] = A.answer.value
	switch(step)
		if(DROP_POD_PATH)
			ask_drop_pod_step(actor, state, DROP_POD_PLAYER)
		if(DROP_POD_PLAYER)
			ask_drop_pod_step(actor, state, state[DROP_POD_PLAYER] == "No" ? DROP_POD_COUNT : DROP_POD_CKEY)
		if(DROP_POD_COUNT)
			ask_drop_pod_step(actor, state, DROP_POD_SURE)
		if(DROP_POD_CKEY)
			ask_drop_pod_step(actor, state, ispath(state[DROP_POD_PATH], /mob/living/carbon/human) ? DROP_POD_ANTAG : DROP_POD_SURE)
		if(DROP_POD_ANTAG)
			ask_drop_pod_step(actor, state, DROP_POD_SURE)
		if(DROP_POD_SURE)
			if(state[DROP_POD_SURE] == "Yes")
				launch_drop_pod(actor.client, state)

/datum/admin_verb/call_drop_pod/proc/launch_drop_pod(client/user, list/state)
	var/spawn_path = state[DROP_POD_PATH]
	var/spawn_count = state[DROP_POD_COUNT] || 0
	var/list/candidates = drop_pod_candidates()
	var/client/selected_player = candidates[state[DROP_POD_CKEY]]
	var/antag_type = state[DROP_POD_ANTAG]
	var/mob/living/spawned_mob
	var/list/spawned_mobs = list()
	if(selected_player)
		// Spawn the mob in nullspace for now.
		spawned_mob = new spawn_path()
		spawned_mob.tag = "awaiting drop"
		if(antag_type)
			var/datum/antagonist/A = antag_all_antag_types()[antag_type]
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

#undef DROP_POD_PATH
#undef DROP_POD_PLAYER
#undef DROP_POD_COUNT
#undef DROP_POD_CKEY
#undef DROP_POD_ANTAG
#undef DROP_POD_SURE
#undef DROP_POD_OFFER_REFUSAL

#undef SD_FLOOR_TILE
#undef SD_WALL_TILE
#undef SD_DOOR_TILE
#undef SD_EMPTY_TILE
#undef SD_SUPPLY_TILE
