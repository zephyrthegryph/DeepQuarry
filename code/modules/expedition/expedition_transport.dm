// Ship-facing expedition planning and travel integration.

/proc/expedition_threat_bands()
	var/static/list/threat_bands = list("Low" = EXP_DIFF_LOW, "Medium" = EXP_DIFF_MED, "High" = EXP_DIFF_HIGH)
	return threat_bands

/proc/expedition_mission_types()
	var/static/list/mission_types = list(
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
		/datum/expedition_mission/station_assault,
	)
	return mission_types

/obj/effect/overmap/visitable/sector/expedition
	name = "expedition site"
	desc = "A dynamically surveyed expedition destination."
	icon_state = "sector"
	known = TRUE
	in_space = FALSE
	var/datum/expedition_site/site

/obj/effect/overmap/visitable/sector/expedition/Destroy()
	if(site && site.overmap_sector == src)
		site.overmap_sector = null
	site = null
	return ..()

/obj/effect/shuttle_landmark/automatic/clearing/expedition
	name = "Expedition Landing Zone"
	radius = 18
	var/datum/expedition_site/site

/obj/effect/shuttle_landmark/automatic/clearing/expedition/shuttle_arrived(datum/shuttle/shuttle)
	. = ..()
	if(!site || shuttle != site.assigned_shuttle)
		return
	site.status = EXP_STATUS_ACTIVE
	site.deployed_at = world.time
	site.last_occupied = world.time
	for(var/area/A in shuttle.shuttle_area)
		for(var/mob/living/L in A)
			site.participants |= L

/obj/effect/shuttle_landmark/automatic/clearing/expedition/Destroy()
	if(site && site.landing_waypoint == src)
		site.landing_waypoint = null
	site = null
	return ..()

/obj/machinery/computer/shuttle_control/explore
	/// Site currently assigned to this craft.
	var/datum/expedition_site/active_expedition
	var/next_expedition_plot = 0

/obj/machinery/computer/shuttle_control/explore/Destroy()
	QDEL_NULL(flight_operations_ui)
	if(active_expedition && active_expedition.origin_console == src)
		active_expedition.origin_console = null
	active_expedition = null
	return ..()

/obj/machinery/computer/shuttle_control/explore/proc/expedition_data()
	if(!active_expedition || QDELETED(active_expedition))
		return null
	var/datum/expedition_mission/M = active_expedition.mission
	return list(
		"name" = active_expedition.name,
		"objective" = M ? M.objective_text() : "Survey the destination.",
		"progress" = M ? M.progress_text() : "-",
		"complete" = active_expedition.status == EXP_STATUS_COMPLETE,
	)

/obj/machinery/computer/shuttle_control/explore/proc/can_plot_expedition()
	return !active_expedition || QDELETED(active_expedition) || active_expedition.status == EXP_STATUS_EXPIRED

/obj/machinery/computer/shuttle_control/explore/proc/plot_expedition(mob/user, datum/shuttle/autodock/overmap/shuttle)
	var/datum/flight_vessel/vessel = SSflight_operations?.vessel_for_ship(shuttle.myship)
	var/datum/expedition_site/site = SSexpedition.plot_for_vessel(user, vessel, src)
	if(site)
		active_expedition = site
		next_expedition_plot = world.time + EXP_LAUNCH_COOLDOWN
