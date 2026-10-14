// Gameplay policies for request validation; the engine owns request lifetime.
/datum/request/check_context()
	var/datum/request/R = src
	if(!R.ask_flags && !R.rights && !R.usable_state)
		return R.recheck_extra()
	var/flags = R.ask_flags
	var/mob/answerer = R.answerer
	var/mob/asker = R.asker || answerer
	var/atom/subject = R.subject
	if(!subject && isatom(R.owner))
		subject = R.owner
	if((flags & (ASK_ALIVE | ASK_CONSCIOUS | ASK_CAPABLE | ASK_ADJACENT | ASK_NEAR_SUBJECT | ASK_RESTRAINED)) && (!ismob(answerer) || !ismob(asker)))
		return "not a mob"
	if((flags & ASK_ALIVE) && (answerer.stat == DEAD || asker.stat == DEAD))
		return "dead"
	if((flags & ASK_CONSCIOUS) && (answerer.stat != CONSCIOUS || asker.stat != CONSCIOUS))
		return "not conscious"
	if((flags & ASK_CAPABLE) && (answerer.incapacitated() || asker.incapacitated()))
		return "not able to"
	if((flags & ASK_RESTRAINED) && (answerer.restrained() || asker.restrained()))
		return "restrained"
	if(flags & ASK_ADJACENT)
		var/atom/other = (asker != answerer) ? asker : subject
		if(!istype(other) || !answerer.Adjacent(other))
			return "too far away"
	if((flags & ASK_NEAR_SUBJECT) && (!istype(subject) || !answerer.Adjacent(subject)))
		return "too far away"
	if(flags & ASK_HELD)
		if(!ismob(asker) || !subject || (asker.get_active_hand() != subject && asker.get_inactive_hand() != subject))
			return "not holding it"
	if(flags & ASK_CARRIED)
		var/atom/movable/carried = subject
		if(!istype(carried))
			return "not carrying it"
		var/found = FALSE
		for(var/atom/holder = carried.loc; holder; holder = holder.loc)
			if(holder == asker)
				found = TRUE
				break
		if(!found)
			return "not carrying it"
	if(flags & ASK_INSIDE)
		var/atom/movable/inside = answerer
		if(!istype(inside) || !subject || inside.loc != subject)
			return "not inside it"
	if(R.rights)
		var/client/C = ismob(answerer) ? answerer.client : null
		if(!admin_can(C, R.rights))
			return "no admin rights"
	if(R.usable_state)
		var/datum/tgui_state/S = GLOB.vars["tgui_[R.usable_state]_state"]
		if(!ismob(answerer) || !subject || !istype(S) || S.can_use_topic(subject, answerer) < STATUS_INTERACTIVE)
			return "can't use it"
	return R.recheck_extra()
