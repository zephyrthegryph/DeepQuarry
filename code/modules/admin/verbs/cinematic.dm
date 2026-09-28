ADMIN_VERB(cinematic, R_FUN, "Cinematic", "Show a cinematic to all players.", ADMIN_CATEGORY_FUN_DO_NOT)
	var/datum/cinematic/choice = verb_ask(user, "cinematic", args, /datum/om/prompt/choice, message = "Chose a cinematic to play to everyone in the server.", title = "Choose Cinematic", choices = sortList(subtypesof(/datum/cinematic), GLOBAL_PROC_REF(cmp_typepaths_asc)))
	if(!choice || !ispath(choice, /datum/cinematic))
		return
	play_cinematic(choice, world)
