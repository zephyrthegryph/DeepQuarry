/datum/objective/escape
	explanation_text = "Escape on the shuttle or an escape pod alive and free."

/datum/objective/escape/check_completion()
	if(issilicon(owner.current))
		return 0
	if(isbrain(owner.current))
		return 0
	if(!SSemergency_shuttle.returned())
		return 0
	if(!owner.current || owner.current.stat ==2)
		return 0
	var/turf/location = get_turf(owner.current.loc)
	if(!location)
		return 0

	if(istype(location, /turf/simulated/shuttle/floor4)) // Fails traitors if they are in the shuttle brig -- Polymorph
		if(istype(owner.current, /mob/living/carbon))
			var/mob/living/carbon/C = owner.current
			if (!C.get_equipped_item(SLOT_ID_HANDCUFFED))
				return 1
		return 0

	var/area/check_area = location.loc
	if(istype(check_area, /area/shuttle/escape/centcom))
		return 1
	if(istype(check_area, /area/shuttle/escape_pod1/centcom))
		return 1
	if(istype(check_area, /area/shuttle/escape_pod2/centcom))
		return 1
	if(istype(check_area, /area/shuttle/escape_pod3/centcom))
		return 1
	if(istype(check_area, /area/shuttle/escape_pod5/centcom))
		return 1
	else
		return 0
