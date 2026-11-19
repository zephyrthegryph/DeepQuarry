// Every job a player can get at roundstart has a start landmark on the station map (Southern Cross), named for its title
// or one of its alt titles (SSjob.roundstart_spawns_for). A job without one falls back to the late-join spawn at roundstart.
// Latejoin-only and off-map jobs (Outsider, Anomaly, CentCom Officer) spawn elsewhere by design and are skipped.
// The test map holds no crew landmarks, so the names come from the station map's .dmm files.

/// The start landmark names placed on Southern Cross: name -> count.
/proc/dq_station_start_landmark_names()
	var/list/names = list()
	var/regex/landmark = regex("/obj/effect/landmark/start\\{\\r?\\n\\tname = \"(\[^\"]+)\"", "g")
	for(var/file_name in flist("maps/southern_cross/"))
		if(!findtext(file_name, ".dmm", -4))
			continue
		var/text = file2text("maps/southern_cross/[file_name]")
		while(landmark.Find(text))
			names[landmark.group[1]]++
	return names

/datum/unit_test/dq_job_roundstart_landmarks

/datum/unit_test/dq_job_roundstart_landmarks/Run()
	var/list/names = dq_station_start_landmark_names()
	TEST_ASSERT(length(names) > 20, "read the start landmarks of Southern Cross ([length(names)] names)")
	var/checked = 0
	var/list/missing = list()
	for(var/datum/job/job as anything in SSjob.occupations)
		if(job.faction != FACTION_STATION || !job.spawn_positions || job.latejoin_only || job.offmap_spawn)
			continue
		checked++
		var/found = names[job.title]
		if(!found)
			for(var/alt in job.alt_titles)
				if(names[alt])
					found = TRUE
					break
		if(!found)
			missing += job.title
	TEST_ASSERT(!length(missing), "roundstart jobs with no start landmark on Southern Cross: [english_list(missing)]")
	TEST_ASSERT(checked > 20, "checked the station jobs ([checked])")

/// A landmark named for an alt title serves the job when none carries its own title, and its own title wins when one does.
/datum/unit_test/dq_job_roundstart_spawns_alt_title

/datum/unit_test/dq_job_roundstart_spawns_alt_title/Run()
	var/datum/job/job = SSjob.get_job(JOB_SITE_MANAGER)
	TEST_ASSERT_NOTNULL(job, "the Site Manager job exists")
	TEST_ASSERT(LAZYACCESS(job.alt_titles, JOB_ALT_COLONY_DIRECTOR), "Colony Director is a Site Manager alt title")
	var/obj/effect/landmark/start/alt = allocate(/obj/effect/landmark/start, run_loc_floor_bottom_left)
	alt.name = JOB_ALT_COLONY_DIRECTOR
	var/obj/effect/landmark/start/other = allocate(/obj/effect/landmark/start, run_loc_floor_bottom_left)
	other.name = JOB_CHEF
	var/list/spawns = SSjob.roundstart_spawns_for(JOB_SITE_MANAGER, job, TRUE, list(alt, other))
	TEST_ASSERT(alt in spawns, "an alt-title landmark serves the job when none carries its title: [english_list(spawns)]")
	TEST_ASSERT(!(other in spawns), "another job's landmark is not used")
	var/obj/effect/landmark/start/exact = allocate(/obj/effect/landmark/start, run_loc_floor_top_right)
	exact.name = JOB_SITE_MANAGER
	spawns = SSjob.roundstart_spawns_for(JOB_SITE_MANAGER, job, TRUE, list(alt, other, exact))
	TEST_ASSERT(exact in spawns, "a landmark with the job's own title is used")
	TEST_ASSERT(!(alt in spawns), "the alt-title landmark is not used when one with the title exists")
