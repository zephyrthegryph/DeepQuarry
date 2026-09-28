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
	var/tmp/site_handle

// its site forgets its sector.
/obj/effect/overmap/visitable/sector/expedition/on_destroy(force)
	if(site() && site().overmap_sector() == src)
		site().overmap_sector_handle = null
	site_handle = null
	..()

/obj/effect/shuttle_landmark/automatic/clearing/expedition
	name = "Expedition Landing Zone"
	radius = 18
	var/tmp/site_handle

/obj/effect/shuttle_landmark/automatic/clearing/expedition/shuttle_arrived(datum/shuttle/shuttle)
	. = ..()
	if(!site() || shuttle != site().assigned_shuttle())
		return
	site().status = EXP_STATUS_ACTIVE
	site().deployed_at = world.time
	site().last_occupied = world.time
	for(var/area/A in shuttle.shuttle_area)
		for(var/mob/living/L in A)
			site().participants |= L

// its site forgets its landing waypoint.
/obj/effect/shuttle_landmark/automatic/clearing/expedition/on_destroy(force)
	if(site() && site().landing_waypoint == src)
		site().landing_waypoint = null
	site_handle = null
	..()

/obj/machinery/computer/shuttle_control/explore
	/// Site currently assigned to this craft.
	var/tmp/active_expedition_handle
	var/next_expedition_plot = 0

REF_OWNED(/obj/machinery/computer/shuttle_control/explore, "flight_operations_ui")

// its expedition forgets its origin console.
/obj/machinery/computer/shuttle_control/explore/on_destroy(force)
	if(active_expedition()?.origin_console() == src)
		active_expedition().origin_console_handle = null
	..()

/obj/machinery/computer/shuttle_control/explore/proc/expedition_data()
	if(!active_expedition() || QDELETED(active_expedition()))
		return null
	var/datum/expedition_mission/M = active_expedition().mission
	return list(
		"name" = active_expedition().name,
		"objective" = M ? M.objective_text() : "Survey the destination.",
		"progress" = M ? M.progress_text() : "-",
		"complete" = active_expedition().status == EXP_STATUS_COMPLETE,
	)

/obj/machinery/computer/shuttle_control/explore/proc/can_plot_expedition()
	return !active_expedition() || QDELETED(active_expedition()) || active_expedition().status == EXP_STATUS_EXPIRED

/obj/machinery/computer/shuttle_control/explore/proc/plot_expedition(mob/user, datum/shuttle/autodock/overmap/shuttle)
	var/datum/flight_vessel/vessel = GLOB.flight_service?.vessel_for_ship(shuttle.myship())
	var/datum/expedition_site/site = GLOB.expedition_service.plot_for_vessel(user, vessel, src)
	if(site)
		active_expedition_handle = om_handle(site)
		next_expedition_plot = world.time + EXP_LAUNCH_COOLDOWN

/// LC-refs: the site this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/effect/shuttle_landmark/automatic/clearing/expedition/proc/site() as /datum/expedition_site
	return om_resolve(site_handle)

/// LC-refs: the site this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/effect/overmap/visitable/sector/expedition/proc/site() as /datum/expedition_site
	return om_resolve(site_handle)

/// LC-refs: the active_expedition this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/computer/shuttle_control/explore/proc/active_expedition() as /datum/expedition_site
	return om_resolve(active_expedition_handle)
