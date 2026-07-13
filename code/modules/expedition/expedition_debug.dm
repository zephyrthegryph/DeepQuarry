// Debug entry points for the expedition system. The production flow is the
// launch console (auto-placed by SSexpedition); these verbs let an admin jump a
// site directly for testing the generator + missions.
/client/verb/generate_expedition_site()
	set name = "Generate Expedition Site"
	set category = "Debug"

	if(!check_rights(R_DEBUG))
		return

	var/datum/expedition_site/site = SSexpedition.generate_site()
	if(!site || !site.landing)
		to_chat(usr, span_warning("Expedition site generation failed (see world log)."))
		return

	if(mob)
		mob.forceMove(site.landing)
	to_chat(usr, span_notice("Generated [site.name] on z[site.z_level]; moved you to its landing point."))

// Roll a chosen mission, generate its site, and drop the admin on the landing
// pad to play it through.
/client/verb/generate_expedition_mission()
	set name = "Generate Expedition Mission"
	set category = "Debug"

	if(!check_rights(R_DEBUG))
		return

	var/list/mission_types = list(
		/datum/expedition_mission/survey,
		/datum/expedition_mission/extermination,
		/datum/expedition_mission/salvage,
		/datum/expedition_mission/retrieval,
		/datum/expedition_mission/rescue,
		/datum/expedition_mission/derelict,
		/datum/expedition_mission/raid,
		/datum/expedition_mission/recovery,
		/datum/expedition_mission/siege,
		/datum/expedition_mission/recon,
		/datum/expedition_mission/restore,
	)
	var/mission_type = input(usr, "Mission type?", "Expedition Mission") as null|anything in mission_types
	if(!mission_type)
		return
	var/diff = input(usr, "Difficulty?", "Expedition Mission") as null|anything in list(EXP_DIFF_LOW, EXP_DIFF_MED, EXP_DIFF_HIGH)
	if(isnull(diff))
		return

	var/datum/expedition_mission/mission = new mission_type(diff)
	var/datum/expedition_site/site = SSexpedition.generate_site(mission)
	if(!site || !site.landing)
		to_chat(usr, span_warning("Expedition mission generation failed (see world log)."))
		return

	if(mob)
		mob.forceMove(site.landing)
	to_chat(usr, span_notice("Generated mission '[mission.name]' on [site.name] (z[site.z_level]). Objective: [mission.objective_text()]"))
