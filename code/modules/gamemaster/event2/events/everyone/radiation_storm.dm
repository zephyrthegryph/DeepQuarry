/datum/event2/meta/radiation_storm
	name = "radiation storm"
	departments = list(DEPARTMENT_EVERYONE)
	chaos = 20
	chaotic_threshold = EVENT_CHAOS_THRESHOLD_MEDIUM_IMPACT
	event_type = /datum/event2/event/radiation_storm

/datum/event2/meta/radiation_storm/get_weight()
	var/medical_factor = GLOB.metric.count_people_in_department(DEPARTMENT_MEDICAL) * 10
	var/population_factor = GLOB.metric.count_people_in_department(DEPARTMENT_EVERYONE) * 5 // Note medical people will get counted twice at 25 weight.
	return 20 + medical_factor + population_factor

/datum/event2/event/radiation_storm
	start_delay_lower_bound = 1 MINUTE
	length_lower_bound = 1 MINUTE

/datum/event2/event/radiation_storm/announce()
	GLOB.command_announcement.Announce("High levels of radiation detected near \the [location_name()]. \
	Please evacuate into one of the shielded maintenance tunnels.", "Anomaly Alert", new_sound = ANNOUNCER_MSG_RADIATION)
	make_maint_all_access()

/datum/event2/event/radiation_storm/start()
	GLOB.command_announcement.Announce("The station has entered the radiation belt. \
	Please remain in a sheltered area until we have passed the radiation belt.", "Anomaly Alert")

/datum/event2/event/radiation_storm/event_tick()
	radiate()

/datum/event2/event/radiation_storm/proc/radiate()
	//This sucks. Just mutate.

	for(var/mob/living/carbon/C in GLOB.living_mob_list)
		if(!(C.z in using_map.station_levels) || C.isSynthetic() || isbelly(C.loc))
			continue
		var/area/A = get_area(C)
		if(!A)
			continue
		if(A.flag_check(RAD_SHIELDED))
			continue
		if(ishuman(C))
			var/mob/living/carbon/human/H = C
			var/chance = 5.0
			chance -= (chance / 100) * C.injury_armor(INJURY_RADIATION, null)
			if(prob(chance))
				if (prob(75))
					randmutb(H) // Applies bad mutation
					domutcheck(H,null,MUTCHK_FORCED)
				else
					randmutg(H) // Applies good mutation
					domutcheck(H,null,MUTCHK_FORCED)
				H.UpdateAppearance()

/datum/event2/event/radiation_storm/end()
	GLOB.command_announcement.Announce("The station has passed the radiation belt. \
	Please allow for up to one minute while radiation levels dissipate, and report to \
	medbay if you experience any unusual symptoms. Maintenance will lose all \
	access again shortly.", "Anomaly Alert")
	addtimer(CALLBACK(src, PROC_REF(maint_callback)), 2 MINUTES)

/datum/event2/event/radiation_storm/proc/maint_callback()
	revoke_maint_all_access()

// There is no actual radiation during a fake storm.
/datum/event2/event/radiation_storm/fake/radiate()
	return
