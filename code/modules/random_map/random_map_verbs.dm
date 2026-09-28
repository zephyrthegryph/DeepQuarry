ADMIN_VERB(print_random_map, R_DEBUG, "Display Random Map", "Show the contents of a random map.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/choice = verb_ask(user, "a1", args, /datum/om/prompt/choice, message = "Choose a map to display.", title = "Map Choice", choices = GLOB.random_maps)
	if(isnull(choice))
		return
	if(!choice)
		return
	var/datum/random_map/selected_map = GLOB.random_maps[choice]
	if(istype(selected_map))
		selected_map.display_map(user)

ADMIN_VERB(delete_random_map, R_DEBUG, "Delete Random Map", "Delete a random map.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/choice = verb_ask(user, "a2", args, /datum/om/prompt/choice, message = "Choose a map to delete.", title = "Map Choice", choices = GLOB.random_maps)
	if(isnull(choice))
		return
	if(!choice)
		return
	var/datum/random_map/selected_map = GLOB.random_maps[choice]
	GLOB.random_maps[choice] = null
	if(istype(selected_map))
		log_and_message_admins("has deleted [selected_map.name].", user)
		qdel(selected_map)

ADMIN_VERB(create_random_map, R_DEBUG, "Create Random Map", "Create a random map.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/map_datum = verb_ask(user, "a3", args, /datum/om/prompt/choice, message = "Choose a map to create.", title = "Map Choice", choices = subtypesof(/datum/random_map))
	if(isnull(map_datum))
		return
	if(!map_datum)
		return

	var/datum/random_map/selected_map
	var/_answer_a4 = verb_ask(user, "a4", args, /datum/om/prompt/choice/alert, message = "Do you wish to customise the map?", title = "Customize", choices = list("Yes","No"))
	if(isnull(_answer_a4))
		return
	if(_answer_a4 == "Yes")
		var/seed = verb_ask(user, "a5", args, /datum/om/prompt/text, message = "Seed? (blank for none)")
		if(isnull(seed))
			return
		var/lx =   verb_ask(user, "a6", args, /datum/om/prompt/number, message = "X-size? (blank for default)")
		if(isnull(lx))
			return
		var/ly =   verb_ask(user, "a7", args, /datum/om/prompt/number, message = "Y-size? (blank for default)")
		if(isnull(ly))
			return
		selected_map = new map_datum(seed,null,null,0,lx,ly,1,null,TRUE)
	else
		selected_map = new map_datum(null,null,null,0,null,null,1,null,TRUE)

	if(selected_map)
		log_and_message_admins("has created [selected_map.name]", user)

ADMIN_VERB(apply_random_map, R_DEBUG, "Apply Random Map", "Apply a map to the game world.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/choice = verb_ask(user, "a8", args, /datum/om/prompt/choice, message = "Choose a map to apply.", title = "Map Choice", choices = GLOB.random_maps)
	if(isnull(choice))
		return
	if(!choice)
		return
	var/datum/random_map/selected_map = GLOB.random_maps[choice]
	if(istype(selected_map))
		var/tx = verb_ask(user, "a9", args, /datum/om/prompt/number, message = "X? (default to current turf)")
		if(isnull(tx))
			return
		var/ty = verb_ask(user, "a10", args, /datum/om/prompt/number, message = "Y? (default to current turf)")
		if(isnull(ty))
			return
		var/tz = verb_ask(user, "a11", args, /datum/om/prompt/number, message = "Z? (default to current turf)")
		if(isnull(tz))
			return
		if(!tx || !ty || !tz) //If someone puts 0 for ANY of these, ignore it and get their current turf.
			var/turf/target_turf = get_turf(user.mob)
			tx = tx ? tx : target_turf.x
			ty = ty ? ty : target_turf.y
			tz = tz ? tz : target_turf.z
		log_and_message_admins("has applied [selected_map.name] at x[tx],y[ty],z[tz].", user)
		selected_map.set_origins(tx,ty,tz)
		selected_map.apply_to_map()

ADMIN_VERB(overlay_random_map, R_DEBUG, "Overlay Random Map", "Apply a map to another map.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/choice = verb_ask(user, "a12", args, /datum/om/prompt/choice, message = "Choose a map as base.", title = "Map Choice", choices = GLOB.random_maps)
	if(isnull(choice))
		return
	if(!choice)
		return
	var/datum/random_map/base_map = GLOB.random_maps[choice]

	var/_answer_a13 = verb_ask(user, "a13", args, /datum/om/prompt/choice, message = "Choose a map to overlay.", title = "Map Choice", choices = GLOB.random_maps)
	if(isnull(_answer_a13))
		return
	choice = _answer_a13
	if(!choice)
		return

	var/datum/random_map/overlay_map = GLOB.random_maps[choice]

	if(istype(base_map) && istype(overlay_map))
		var/tx = verb_ask(user, "a14", args, /datum/om/prompt/number, message = "X? (default to 1)")
		if(isnull(tx))
			return
		var/ty = verb_ask(user, "a15", args, /datum/om/prompt/number, message = "Y? (default to 1)")
		if(isnull(ty))
			return
		if(!tx) tx = 1
		if(!ty) ty = 1
		log_and_message_admins("has applied [overlay_map.name] to [base_map.name] at x[tx],y[ty],z[overlay_map.origin_z].", user)
		overlay_map.overlay_with(base_map,tx,ty)
		base_map.display_map(user)
