/// Interned in Initialize(): objects with the same access share one list, so
/// replace these lists rather than editing them in place.
/obj/var/list/req_access
/obj/var/list/req_one_access

/// Swaps req_access and req_one_access for the shared copy with the same contents.
/obj/proc/intern_access_lists()
	if(length(req_access) && is_access_id_list(req_access))
		req_access = string_list(req_access)
	if(length(req_one_access) && is_access_id_list(req_one_access))
		req_one_access = string_list(req_one_access)

/proc/is_access_id_list(list/L)
	for(var/entry in L)
		if(!isnum(entry))
			return FALSE
	return TRUE

//returns 1 if this mob has sufficient access to use this object
/obj/proc/allowed(mob/M)
	return check_access(M?.GetIdCard())

/atom/movable/proc/GetAccess()
	var/obj/item/card/id/id = GetIdCard()
	return id ? id.GetAccess() : list()

/obj/proc/GetID()
	return null

/obj/proc/check_access(obj/item/I)
	return check_access_list(I ? I.GetAccess() : null)

/obj/proc/check_access_list(list/L)
	// We don't require access
	if(!LAZYLEN(req_access) && !LAZYLEN(req_one_access))
		return TRUE

	// They passed nothing, but we are something that requires access
	if(!LAZYLEN(L))
		return FALSE

	// Run list comparisons
	return has_access(req_access, req_one_access, L)

/proc/has_access(list/req_access, list/req_one_access, list/accesses)
	// req_access list has priority if set
	// Requires at least every access in list
	for(var/req in req_access)
		if(!(req in accesses))
			return FALSE

	// req_one_access is secondary if set
	// Requires at least one access in list
	if(LAZYLEN(req_one_access))
		for(var/req in req_one_access)
			if(req in accesses)
				return TRUE
		return FALSE

	return TRUE

/proc/get_all_jobs()
	var/list/all_jobs = list()
	var/list/all_datums = typesof(/datum/job)
	all_datums -= GLOB.exclude_jobs
	var/datum/job/jobdatum
	for(var/jobtype in all_datums)
		jobdatum = new jobtype
		all_jobs.Add(jobdatum.title)
	return all_jobs

/proc/get_all_centcom_jobs()
	return list("VIP Guest",
		"Custodian",
		"Thunderdome Overseer",
		"Intel Officer",
		"Medical Officer",
		"Death Commando",
		"Research Officer",
		"BlackOps Commander",
		"Supreme Commander",
		"Emergency Response Team",
		"Emergency Response Team Leader")

/atom/movable/proc/GetIdCard()
	return null

/mob/living/bot/GetIdCard()
	return botcard

/mob/living/carbon/human/GetIdCard()
	if(get_active_hand())
		var/obj/item/I = get_active_hand()
		var/id = I.GetID()
		if(id)
			return id
	if(get_equipped_item(SLOT_ID_WEAR_ID))
		var/id = get_equipped_item(SLOT_ID_WEAR_ID).GetID()
		if(id)
			return id

/mob/living/silicon/GetIdCard()
	return idcard

/proc/FindNameFromID(mob/living/carbon/human/H)
	ASSERT(istype(H))
	var/obj/item/card/id/C = H.GetIdCard()
	if(C)
		return C.registered_name

/proc/get_all_job_icons() //For all existing HUD icons
	return SSjob.occupations_by_name + GLOB.alt_titles_with_icons + list("Prisoner")

/obj/proc/GetJobName() //Used in secHUD icon generation
	var/obj/item/card/id/I = GetID()

	if(I)
		if(istype(I,/obj/item/card/id/centcom))
			return "Centcom"

		var/job_icons = get_all_job_icons()
		if(I.assignment	in job_icons) //Check if the job has a hud icon
			return I.assignment
		if(I.rank in job_icons)
			return I.rank

		var/centcom = get_all_centcom_jobs()
		if(I.assignment	in centcom) //Return with the NT logo if it is a CentCom job
			return "CentCom"
		if(I.rank in centcom)
			return "CentCom"
	else
		return

	return "Unknown" //Return unknown if none of the above apply
