#define VERTICAL_NOM_STATE "You cannot do that while in your current state."
#define VERTICAL_NOM_BELLY "No selected belly found."
#define VERTICAL_NOM_TARGETS "No eligible targets found."

/mob/living/proc/vertical_nom()
	set name = "Nom from Above"
	set desc = "Allows you to eat people who are below your tile or adjacent one. Requires passability."
	set category = VERB_CAT_ABILITIES_VORE

	if(stat == DEAD || has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED) || is_incorporeal())
		to_chat(src, span_notice("You cannot do that while in your current state."))
		return

	if(!(src.vore_selected))
		to_chat(src, span_notice("No selected belly found."))
		return

	var/list/targets = list()

	for(var/turf/T in range(1, src))
		if(isopenspace(T))
			while(isopenspace(T))
				T = GetBelow(T)
			if(T)
				for(var/mob/living/L in contents_of(T))
					if(L.devourable && L.can_be_drop_prey)
						targets += L

	if(!(targets.len))
		to_chat(src, span_notice("No eligible targets found."))
		return

	open_request(src, /datum/prompt/choice/vertical_nom_target, PROC_REF(vertical_nom_answered), answerer = src, choices = targets)

/mob/living/proc/vertical_nom_done(mob/living/target, starting_loc)
	if(target.loc != starting_loc)
		to_chat(target, span_vwarning("You have interrupted whatever that was..."))
		to_chat(src, span_vnotice("They got away."))
		return
	if(target?.buckled_to())
		var/atom/movable/_tmp_buck_47 = target?.buckled_to()
		_tmp_buck_47.unbuckle_mob()
	act_message(target, src, MSG_SELF(span_vdanger("You are dragged above and feel yourself slipping directly into %T%'s [vore_selected.get_belly_name()]!")), \
		MSG_OTHERS(span_vwarning("%U% suddenly disappears somewhere above!")))
	to_chat(src, span_vnotice("You successfully snatch \the [target], slipping them into your [vore_selected.get_belly_name()]."))
	vore_selected.nom_atom(target)

/mob/living/proc/vertical_nom_answered(datum/act/request/context)
	if(!context.answer)
		if(!isnull(context.request.value))
			switch(context.request.last_error)
				if(VERTICAL_NOM_STATE, VERTICAL_NOM_BELLY, VERTICAL_NOM_TARGETS)
					to_chat(src, span_notice(context.request.last_error))
					SStgui.update_uis(src)
		return
	var/mob/living/target = context.answer.value
	to_chat(target, span_vwarning("You feel yourself being pulled up by something... Or someone?!"))
	var/starting_loc = target.loc

	task_timed(src, 5 SECONDS, target, src, PROC_REF(vertical_nom_done), list(target, starting_loc))
	SStgui.update_uis(src)

/datum/prompt/choice/vertical_nom_target
	title = "Victim"
	question = "Please select a target."
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/vertical_nom_target/recheck_extra()
	var/mob/living/user = answerer
	if(!istype(user) || QDELETED(user))
		return "gone"
	if(!isnull(value))
		var/mob/living/target = value
		if(!istype(target) || QDELETED(target))
			return "gone"
	if(user.stat == DEAD || user.has_status(STAT_PARALYZED) || user.has_status(STAT_WEAKENED) || user.has_status(STAT_STUNNED) || user.is_incorporeal())
		return VERTICAL_NOM_STATE
	if(!user.vore_selected)
		return VERTICAL_NOM_BELLY
	for(var/turf/T in range(1, user))
		if(isopenspace(T))
			while(isopenspace(T))
				T = GetBelow(T)
			if(T)
				for(var/mob/living/L in contents_of(T))
					if(L.devourable && L.can_be_drop_prey)
						return null
	return VERTICAL_NOM_TARGETS

#undef VERTICAL_NOM_STATE
#undef VERTICAL_NOM_BELLY
#undef VERTICAL_NOM_TARGETS
