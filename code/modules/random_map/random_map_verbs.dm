ADMIN_VERB(print_random_map, R_DEBUG, "Display Random Map", "Show the contents of a random map.", ADMIN_CATEGORY_DEBUG_EVENTS)
	return random_map_stage(user, list())

/datum/admin_verb/print_random_map/proc/random_map_stage(client/user, list/map_answers)
	if(!user || !user.mob || QDELETED(user.mob))
		return
	if(!("a1" in map_answers))
		open_request(src, /datum/prompt/choice/random_map_review, PROC_REF(random_map_answered), answerer = user.mob, map_answers = map_answers, map_key = "a1", question = "Choose a map to display.", title = "Map Choice", choices = random_maps_by_name())
		return
	var/choice = map_answers["a1"]
	if(isnull(choice))
		return
	if(!choice)
		return
	var/list/maps_by_name = random_maps_by_name()
	var/datum/random_map/selected_map = maps_by_name[choice]
	if(istype(selected_map))
		selected_map.display_map(user)

ADMIN_VERB(delete_random_map, R_DEBUG, "Delete Random Map", "Delete a random map.", ADMIN_CATEGORY_DEBUG_EVENTS)
	return random_map_stage(user, list())

/datum/admin_verb/delete_random_map/proc/random_map_stage(client/user, list/map_answers)
	if(!user || !user.mob || QDELETED(user.mob))
		return
	if(!("a2" in map_answers))
		open_request(src, /datum/prompt/choice/random_map_review, PROC_REF(random_map_answered), answerer = user.mob, map_answers = map_answers, map_key = "a2", question = "Choose a map to delete.", title = "Map Choice", choices = random_maps_by_name())
		return
	var/choice = map_answers["a2"]
	if(isnull(choice))
		return
	if(!choice)
		return
	var/list/maps_by_name = random_maps_by_name()
	var/datum/random_map/selected_map = maps_by_name[choice]
	registry_leave(REGISTRY_RANDOM_MAPS, selected_map)
	if(istype(selected_map))
		log_and_message_admins("has deleted [selected_map.name].", user)
		qdel(selected_map)

ADMIN_VERB(create_random_map, R_DEBUG, "Create Random Map", "Create a random map.", ADMIN_CATEGORY_DEBUG_EVENTS)
	return random_map_stage(user, list())

/datum/admin_verb/create_random_map/proc/random_map_stage(client/user, list/map_answers)
	if(!user || !user.mob || QDELETED(user.mob))
		return
	if(!("a3" in map_answers))
		open_request(src, /datum/prompt/choice/random_map_review, PROC_REF(random_map_answered), answerer = user.mob, map_answers = map_answers, map_key = "a3", question = "Choose a map to create.", title = "Map Choice", choices = subtypesof(/datum/random_map))
		return
	var/map_datum = map_answers["a3"]
	if(isnull(map_datum))
		return
	if(!map_datum)
		return

	var/datum/random_map/selected_map
	if(!("a4" in map_answers))
		open_request(src, /datum/prompt/choice/random_map_review, PROC_REF(random_map_answered), answerer = user.mob, map_answers = map_answers, map_key = "a4", question = "Do you wish to customise the map?", title = "Customize", choices = list("Yes","No"), buttons = TRUE)
		return
	var/_answer_a4 = map_answers["a4"]
	if(isnull(_answer_a4))
		return
	if(_answer_a4 == "Yes")
		if(!("a5" in map_answers))
			open_request(src, /datum/prompt/text/random_map_review, PROC_REF(random_map_answered), answerer = user.mob, map_answers = map_answers, map_key = "a5", question = "Seed? (blank for none)")
			return
		var/seed = map_answers["a5"]
		if(isnull(seed))
			return
		if(!("a6" in map_answers))
			open_request(src, /datum/prompt/number/random_map_review, PROC_REF(random_map_answered), answerer = user.mob, map_answers = map_answers, map_key = "a6", question = "X-size? (blank for default)")
			return
		var/lx = map_answers["a6"]
		if(isnull(lx))
			return
		if(!("a7" in map_answers))
			open_request(src, /datum/prompt/number/random_map_review, PROC_REF(random_map_answered), answerer = user.mob, map_answers = map_answers, map_key = "a7", question = "Y-size? (blank for default)")
			return
		var/ly = map_answers["a7"]
		if(isnull(ly))
			return
		selected_map = new map_datum(seed,null,null,0,lx,ly,1,null,TRUE)
	else
		selected_map = new map_datum(null,null,null,0,null,null,1,null,TRUE)

	if(selected_map)
		log_and_message_admins("has created [selected_map.name]", user)

ADMIN_VERB(apply_random_map, R_DEBUG, "Apply Random Map", "Apply a map to the game world.", ADMIN_CATEGORY_DEBUG_EVENTS)
	return random_map_stage(user, list())

/datum/admin_verb/apply_random_map/proc/random_map_stage(client/user, list/map_answers)
	if(!user || !user.mob || QDELETED(user.mob))
		return
	if(!("a8" in map_answers))
		open_request(src, /datum/prompt/choice/random_map_review, PROC_REF(random_map_answered), answerer = user.mob, map_answers = map_answers, map_key = "a8", question = "Choose a map to apply.", title = "Map Choice", choices = random_maps_by_name())
		return
	var/choice = map_answers["a8"]
	if(isnull(choice))
		return
	if(!choice)
		return
	var/list/maps_by_name = random_maps_by_name()
	var/datum/random_map/selected_map = maps_by_name[choice]
	if(istype(selected_map))
		if(!("a9" in map_answers))
			open_request(src, /datum/prompt/number/random_map_review, PROC_REF(random_map_answered), answerer = user.mob, map_answers = map_answers, map_key = "a9", question = "X? (default to current turf)")
			return
		var/tx = map_answers["a9"]
		if(isnull(tx))
			return
		if(!("a10" in map_answers))
			open_request(src, /datum/prompt/number/random_map_review, PROC_REF(random_map_answered), answerer = user.mob, map_answers = map_answers, map_key = "a10", question = "Y? (default to current turf)")
			return
		var/ty = map_answers["a10"]
		if(isnull(ty))
			return
		if(!("a11" in map_answers))
			open_request(src, /datum/prompt/number/random_map_review, PROC_REF(random_map_answered), answerer = user.mob, map_answers = map_answers, map_key = "a11", question = "Z? (default to current turf)")
			return
		var/tz = map_answers["a11"]
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
	return random_map_stage(user, list())

/datum/admin_verb/overlay_random_map/proc/random_map_stage(client/user, list/map_answers)
	if(!user || !user.mob || QDELETED(user.mob))
		return
	if(!("a12" in map_answers))
		open_request(src, /datum/prompt/choice/random_map_review, PROC_REF(random_map_answered), answerer = user.mob, map_answers = map_answers, map_key = "a12", question = "Choose a map as base.", title = "Map Choice", choices = random_maps_by_name())
		return
	var/choice = map_answers["a12"]
	if(isnull(choice))
		return
	if(!choice)
		return
	var/list/maps_by_name = random_maps_by_name()
	var/datum/random_map/base_map = maps_by_name[choice]

	if(!("a13" in map_answers))
		open_request(src, /datum/prompt/choice/random_map_review, PROC_REF(random_map_answered), answerer = user.mob, map_answers = map_answers, map_key = "a13", question = "Choose a map to overlay.", title = "Map Choice", choices = random_maps_by_name())
		return
	var/_answer_a13 = map_answers["a13"]
	if(isnull(_answer_a13))
		return
	choice = _answer_a13
	if(!choice)
		return

	maps_by_name = random_maps_by_name()
	var/datum/random_map/overlay_map = maps_by_name[choice]

	if(istype(base_map) && istype(overlay_map))
		if(!("a14" in map_answers))
			open_request(src, /datum/prompt/number/random_map_review, PROC_REF(random_map_answered), answerer = user.mob, map_answers = map_answers, map_key = "a14", question = "X? (default to 1)")
			return
		var/tx = map_answers["a14"]
		if(isnull(tx))
			return
		if(!("a15" in map_answers))
			open_request(src, /datum/prompt/number/random_map_review, PROC_REF(random_map_answered), answerer = user.mob, map_answers = map_answers, map_key = "a15", question = "Y? (default to 1)")
			return
		var/ty = map_answers["a15"]
		if(isnull(ty))
			return
		if(!tx) tx = 1
		if(!ty) ty = 1
		log_and_message_admins("has applied [overlay_map.name] to [base_map.name] at x[tx],y[ty],z[overlay_map.origin_z].", user)
		overlay_map.overlay_with(base_map,tx,ty)
		base_map.display_map(user)

/datum/admin_verb/print_random_map/proc/random_map_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	var/list/map_answers
	var/map_key
	if(istype(context.answer, /datum/prompt/choice/random_map_review))
		var/datum/prompt/choice/random_map_review/choice_request = context.answer
		map_answers = choice_request.map_answers.Copy()
		map_key = choice_request.map_key
	else if(istype(context.answer, /datum/prompt/text/random_map_review))
		var/datum/prompt/text/random_map_review/text_request = context.answer
		map_answers = text_request.map_answers.Copy()
		map_key = text_request.map_key
	else if(istype(context.answer, /datum/prompt/number/random_map_review))
		var/datum/prompt/number/random_map_review/number_request = context.answer
		map_answers = number_request.map_answers.Copy()
		map_key = number_request.map_key
	else
		return
	if(random_map_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	map_answers[map_key] = context.answer.answer_value
	return random_map_stage(user, map_answers)

/datum/admin_verb/delete_random_map/proc/random_map_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	var/list/map_answers
	var/map_key
	if(istype(context.answer, /datum/prompt/choice/random_map_review))
		var/datum/prompt/choice/random_map_review/choice_request = context.answer
		map_answers = choice_request.map_answers.Copy()
		map_key = choice_request.map_key
	else if(istype(context.answer, /datum/prompt/text/random_map_review))
		var/datum/prompt/text/random_map_review/text_request = context.answer
		map_answers = text_request.map_answers.Copy()
		map_key = text_request.map_key
	else if(istype(context.answer, /datum/prompt/number/random_map_review))
		var/datum/prompt/number/random_map_review/number_request = context.answer
		map_answers = number_request.map_answers.Copy()
		map_key = number_request.map_key
	else
		return
	if(random_map_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	map_answers[map_key] = context.answer.answer_value
	return random_map_stage(user, map_answers)

/datum/admin_verb/create_random_map/proc/random_map_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	var/list/map_answers
	var/map_key
	if(istype(context.answer, /datum/prompt/choice/random_map_review))
		var/datum/prompt/choice/random_map_review/choice_request = context.answer
		map_answers = choice_request.map_answers.Copy()
		map_key = choice_request.map_key
	else if(istype(context.answer, /datum/prompt/text/random_map_review))
		var/datum/prompt/text/random_map_review/text_request = context.answer
		map_answers = text_request.map_answers.Copy()
		map_key = text_request.map_key
	else if(istype(context.answer, /datum/prompt/number/random_map_review))
		var/datum/prompt/number/random_map_review/number_request = context.answer
		map_answers = number_request.map_answers.Copy()
		map_key = number_request.map_key
	else
		return
	if(random_map_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	map_answers[map_key] = context.answer.answer_value
	return random_map_stage(user, map_answers)

/datum/admin_verb/apply_random_map/proc/random_map_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	var/list/map_answers
	var/map_key
	if(istype(context.answer, /datum/prompt/choice/random_map_review))
		var/datum/prompt/choice/random_map_review/choice_request = context.answer
		map_answers = choice_request.map_answers.Copy()
		map_key = choice_request.map_key
	else if(istype(context.answer, /datum/prompt/text/random_map_review))
		var/datum/prompt/text/random_map_review/text_request = context.answer
		map_answers = text_request.map_answers.Copy()
		map_key = text_request.map_key
	else if(istype(context.answer, /datum/prompt/number/random_map_review))
		var/datum/prompt/number/random_map_review/number_request = context.answer
		map_answers = number_request.map_answers.Copy()
		map_key = number_request.map_key
	else
		return
	if(random_map_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	map_answers[map_key] = context.answer.answer_value
	return random_map_stage(user, map_answers)

/datum/admin_verb/overlay_random_map/proc/random_map_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	var/list/map_answers
	var/map_key
	if(istype(context.answer, /datum/prompt/choice/random_map_review))
		var/datum/prompt/choice/random_map_review/choice_request = context.answer
		map_answers = choice_request.map_answers.Copy()
		map_key = choice_request.map_key
	else if(istype(context.answer, /datum/prompt/text/random_map_review))
		var/datum/prompt/text/random_map_review/text_request = context.answer
		map_answers = text_request.map_answers.Copy()
		map_key = text_request.map_key
	else if(istype(context.answer, /datum/prompt/number/random_map_review))
		var/datum/prompt/number/random_map_review/number_request = context.answer
		map_answers = number_request.map_answers.Copy()
		map_key = number_request.map_key
	else
		return
	if(random_map_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	map_answers[map_key] = context.answer.answer_value
	return random_map_stage(user, map_answers)

/proc/random_map_advanced_call(mob/actor)
#ifdef TESTING
	return FALSE
#else
	return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
#endif

/datum/prompt/choice/random_map_review
	timeout = 0
	recheck_on_open = TRUE
	rights = R_DEBUG
	var/list/map_answers
	var/map_key

/datum/prompt/choice/random_map_review/recheck_extra()
	var/mob/admin = answerer
	if(!admin_can(admin?.client, 0))
		return "no admin rights"

/datum/prompt/text/random_map_review
	timeout = 0
	recheck_on_open = TRUE
	rights = R_DEBUG
	var/list/map_answers
	var/map_key

/datum/prompt/text/random_map_review/recheck_extra()
	var/mob/admin = answerer
	if(!admin_can(admin?.client, 0))
		return "no admin rights"

/datum/prompt/text/random_map_review/normalize(given)
	return istext(given) ? given : null

/datum/prompt/number/random_map_review
	timeout = 0
	recheck_on_open = TRUE
	rights = R_DEBUG
	var/list/map_answers
	var/map_key

/datum/prompt/number/random_map_review/recheck_extra()
	var/mob/admin = answerer
	if(!admin_can(admin?.client, 0))
		return "no admin rights"
