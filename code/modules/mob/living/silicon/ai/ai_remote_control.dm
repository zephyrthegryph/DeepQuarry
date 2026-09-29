/mob/living/silicon/ai
	var/mob/living/silicon/robot/deployed_shell = null //For shell control

/// `picked`: the target came from the shell list (don't ask again if it's no longer usable).
/mob/living/silicon/ai/proc/deploy_to_shell(mob/living/silicon/robot/target, picked = FALSE)
	if(!CONFIG_GET(flag/allow_ai_shells))
		to_chat(src, span_warning("AI Shells are not allowed on this server. You shouldn't have this verb because of it, so consider making a bug report."))
		return

	if(incapacitated())
		to_chat(src, span_warning("You are incapacitated!"))
		return

	if(lacks_power())
		to_chat(src, span_warning("Your core lacks power, wireless is disabled."))
		return

	if(control_disabled)
		to_chat(src, span_warning("Wireless networking module is offline."))
		return

	var/list/possible = list()
	for(var/mob/living/silicon/robot/R as anything in REGISTRY_MEMBERS(REGISTRY_AI_SHELLS))
		if(R.shell && !R.deployed && (R.stat != DEAD) && (!R.connected_ai || (R.connected_ai == src) ) ) // shell restrictions
			if(istype(R.loc, /obj/machinery/recharge_station))	//Check Rechargers
				var/obj/machinery/recharge_station/RS = R.loc
				if(!(using_map.ai_shell_restricted && !(RS.z in using_map.ai_shell_allowed_levels)))	//Allow station borgs to be redeployed from Chargers.
					possible += R

			if(isbelly(R.loc))	//check belly space
				var/obj/belly/B = R.loc
				if(!(using_map.ai_shell_restricted && !(B.owner.z in using_map.ai_shell_allowed_levels)))	//No smuggling in borgs
					possible += R

			if(!(using_map.ai_shell_restricted && !(R.z in using_map.ai_shell_allowed_levels)))
				possible += R

	if(!LAZYLEN(possible))
		to_chat(src, span_warning("No usable AI shell beacons detected."))

	if(!picked && (!target || !(target in possible))) //If the AI is looking for a new shell, or its pre-selected shell is no longer valid
		if(LAZYLEN(possible))
			om_ask(src, /datum/om/prompt/choice/ai_shell, PROC_REF(shell_picked), choices = possible)
			return
		target = null

	if(!(target in possible))
		target = null
	if(!target || target.stat == DEAD || target.deployed || !(!target.connected_ai || (target.connected_ai == src) ) )
		if(target)
			to_chat(src, span_warning("It is no longer possible to deploy to \the [target]."))
		else
			to_chat(src, span_notice("Deployment aborted."))
		return

	else if(mind)
		soul_link(/datum/soul_link/shared_body, src, target)
		rel_set(src, "deployed_shell", target)
		if(src.client) // ITION: Resize shell based on our preffered size
			target.resize(src.client.prefs.read_preference(/datum/preference/numeric/human/size_multiplier)) // ITION + size_multiplier migrated
		target.deploy_init(src)
		mind.transfer_to(target)
		if(target.first_transfer)
			target.first_transfer = FALSE
			target.copy_from_prefs_vr()
			if(LAZYLEN(target.vore_organs))
				rel_set(target, "vore_selected", target.vore_organs[1])
		src.copy_vore_prefs_to_mob(target)
		rel_set(src, "teleop", target) // So the AI 'hears' messages near its core.
		target.post_deploy()

/// Picking a shell to deploy to (AIs and shells moving between shells). A cancel aborts deployment.
/datum/om/prompt/choice/ai_shell
	title = "Shell Choice"
	message = "Which body to control?"

/datum/om/prompt/choice/ai_shell/cancelled()
	to_chat(answerer, span_notice("Deployment aborted."))

/mob/living/silicon/ai/proc/shell_picked(datum/om/prompt/choice/ai_shell/ask)
	deploy_to_shell(ask.choice, TRUE)

/mob/living/silicon/ai/proc/deploy_to_shell_act()
	set category = VERB_CAT_AI_COMMANDS
	set name = "Deploy to Shell"
	deploy_to_shell() // This is so the AI is not prompted with a list of all mobs when using the 'real' proc.

/mob/living/silicon/ai/proc/disconnect_shell(message = "Your remote connection has been reset!")
	if(deployed_shell) // Forcibly call back AI in event of things such as damage, EMP or power loss.
		message = span_danger(message)
		deployed_shell.undeploy(message)

