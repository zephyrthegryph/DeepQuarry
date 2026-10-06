// Open "View Variables" menu for target
/mob/observer/dead/action_quick(atom/target)
	if(admin_require(client, R_DEBUG, "action_quick", TRUE))
		SSadmin_verbs.dynamic_invoke_verb(client, /datum/admin_verb/debug_variables, target)

// Open "Show Player Panel" menu for target mob
/mob/observer/dead/action_pull(atom/target)
	if(admin_require(client, R_ADMIN, "action_pull", TRUE) && ismob(target))
		SSadmin_verbs.dynamic_invoke_verb(client, /datum/admin_verb/show_player_panel, target)
