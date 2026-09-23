GLOBAL_DATUM_INIT(crew_repository, /datum/repository/crew, new)

/datum/repository/crew
	var/list/cache_data

/datum/repository/crew/New()
	cache_data = list()
	..()

/datum/repository/crew/proc/health_data(zLevel)
	var/list/crewmembers = list()
	if(!zLevel)
		return crewmembers

	var/z_level = "[zLevel]"
	var/datum/cache_entry/cache_entry = cache_data[z_level]
	if(!cache_entry)
		cache_entry = new/datum/cache_entry
		cache_data[z_level] = cache_entry

	if(world.time < cache_entry.timestamp)
		return cache_entry.data

	var/tracked = scan()
	for(var/obj/item/clothing/under/C in tracked)
		var/turf/pos = get_turf(C)
		var/area/B = pos?.loc //No sensor in Dorm
		if((C.has_sensor) && (pos?.z == zLevel) && (C.sensor_mode != SUIT_SENSOR_OFF) && !(B.flag_check(AREA_BLOCK_SUIT_SENSORS)) && !(is_jammed(C)) && !(is_vore_jammed(C)))
			if(ishuman(C.loc))
				var/mob/living/carbon/human/H = C.loc
				if(H.get_equipped_item(SLOT_ID_UNIFORM) != C)
					continue

				var/list/crewmemberData = list("dead"=0, "area"="", "x"=-1, "y"=-1, "realZ"=-1, "z"="", "ref" = "\ref[H]")

				crewmemberData["sensor_type"] = C.sensor_mode
				crewmemberData["name"] = H.get_authentification_name(if_no_id="Unknown")
				crewmemberData["rank"] = H.get_authentification_rank(if_no_id="Unknown", if_no_job="No Job")
				crewmemberData["assignment"] = H.get_assignment(if_no_id="Unknown", if_no_job="No Job")

				if(C.sensor_mode >= SUIT_SENSOR_BINARY)
					crewmemberData["dead"] = H.stat == DEAD

				if(C.sensor_mode >= SUIT_SENSOR_VITAL)
					crewmemberData["stat"] = H.stat
					// Coarse status from vitality / criticality, plus the vitals
					// the sensors measure.
					crewmemberData["condition"] = sensor_status(H)
					crewmemberData["vitality"] = round(H.vitality() * 100, 1)
					var/datum/diagnosis/D = H.diagnose(/datum/diagnostic_profile/suit_sensors)
					if(D)
						crewmemberData["heartRate"] = D.heart_rate
						crewmemberData["oxygenation"] = D.oxygenation
						crewmemberData["temperature"] = D.temperature
						qdel(D)

				if(C.sensor_mode >= SUIT_SENSOR_TRACKING)
					var/area/A = get_area(H)
					crewmemberData["area"] = sanitize(A.get_name())
					crewmemberData["x"] = pos.x
					crewmemberData["y"] = pos.y
					crewmemberData["realZ"] = pos.z
					crewmemberData["z"] = using_map.get_zlevel_name(pos.z)

				crewmembers[++crewmembers.len] = crewmemberData

	crewmembers = sortByKey(crewmembers, "name")
	cache_entry.timestamp = world.time + 5 SECONDS
	cache_entry.data = crewmembers

	return crewmembers

/datum/repository/crew/proc/scan()
	var/list/tracked = list()
	for(var/mob/living/carbon/human/H in GLOB.mob_list)
		if(isanimal(H.loc))
			var/mob/living/simple_mob/tf_holder = H.loc
			if(tf_holder.tf_mob_holder == H) //Exclude characters that are TFd into other mobs.
				continue
		if(istype(H.get_equipped_item(SLOT_ID_UNIFORM), /obj/item/clothing/under))
			var/obj/item/clothing/under/C = H.get_equipped_item(SLOT_ID_UNIFORM)
			if (C.has_sensor)
				tracked |= C
	return tracked
