//This will update a mob's name, real_name, mind.name, data_core records, pda and id
//Calling this proc without an oldname will only update the mob and skip updating the pda, id and records ~Carn
/mob/proc/fully_replace_character_name(oldname,newname)
	if(!newname)	return 0
	set_real_name(newname)
	name = newname
	if(mind)
		mind.name = newname
		if(mind.identity)
			mind.identity.real_name = newname
	if(dna)
		dna.real_name = real_name

	if(oldname)
		//update the datacore records! This is goig to be a bit costly.
		for(var/list/L in list(GLOB.data_core.general, GLOB.data_core.medical, GLOB.data_core.security, GLOB.data_core.locked))
			for(var/datum/data/record/R in L)
				if(R.fields["name"] == oldname)
					R.set_fields_at("name", newname)
					break

		//update our pda and id if we have them on our person
		var/list/searching = GetAllContents(searchDepth = 3)
		var/search_id = 1
		var/search_pda = 1

		for(var/A in searching)
			if( search_id && istype(A,/obj/item/card/id) )
				var/obj/item/card/id/ID = A
				if(ID.registered_name == oldname)
					ID.set_registered_name(newname)
					ID.name = "[newname]'s ID Card ([ID.assignment])"
					if(!search_pda)	break
					search_id = 0

			else if( search_pda && istype(A,/obj/item/pda) )
				var/obj/item/pda/PDA = A
				if(PDA.owner == oldname)
					PDA.set_owner(newname)
					PDA.name = "PDA-[newname] ([PDA.ownjob])"
					if(!search_id)	break
					search_pda = 0
	return 1

/mob/proc/rename_self_apply(datum/act/request/request_act)
	var/datum/prompt/text/rename_self/P = request_act.answer
	var/role = P.role
	if(ELAPSED(P, started_at, CLOCK_WORLD) > 5 MINUTES)
		return	//took too long
	var/newname = sanitizeName(P.value, , P.allow_numbers)	//returns null if the name doesn't meet some basic requirements. Tidies up a few other things like bad-characters.
	for(var/mob/living/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(M == src)
			continue
		if(!newname || M.real_name == newname)
			newname = null
			break
	if(!newname)
		to_chat(src, "Sorry, that [role]-name wasn't appropriate, please try another. It's possibly too long/short, has bad characters or is already taken.")
		if(P.attempt < 3)
			rename_self(role, P.allow_numbers, P.attempt + 1, P.started_at)
		return

	var/oldname = real_name
	if(cmptext("ai",role))
		var/mob/living/silicon/ai/A = src
		if(istype(A))
			oldname = null//don't bother with the records update crap
			play_simple_announcement(world, ANNOUNCER_MSG_NEW_AI)
			// Set eyeobj name
			A.SetName(newname)

	fully_replace_character_name(oldname,newname)

/// We get 3 attempts to pick a suitable name, within five minutes; a cancel keeps the old one.
/mob/proc/rename_self_entered(datum/act/request/request_act)
	if(!request_act.answer)
		return
	return rename_self_apply(request_act)

//Generalised helper proc for letting mobs rename themselves. Used to be clname() and ainame()
//Last modified by Carn
/mob/proc/rename_self(role, allow_numbers=0, attempt = 1, started_at)
	if(isnull(started_at))
		started_at = TIME_NOW(CLOCK_WORLD)
	open_request(src, /datum/prompt/text/rename_self, TYPE_PROC_REF(/mob, rename_self_entered), answerer = src, default = real_name, role = role, allow_numbers = allow_numbers, attempt = attempt, started_at = started_at)
