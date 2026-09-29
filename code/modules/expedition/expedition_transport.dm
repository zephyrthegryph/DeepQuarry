// Ship-facing expedition planning and travel integration.

GLOBAL_LIST_INIT(expedition_threat_bands, list("Low" = EXP_DIFF_LOW, "Medium" = EXP_DIFF_MED, "High" = EXP_DIFF_HIGH))

GLOBAL_LIST_INIT(expedition_mission_types, list(
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
	))

/obj/effect/overmap/visitable/sector/expedition
	name = "expedition site"
	desc = "A dynamically surveyed expedition destination."
	icon_state = "sector"
	known = TRUE
	in_space = FALSE
	var/tmp/datum/expedition_site/site

/obj/effect/shuttle_landmark/automatic/clearing/expedition
	name = "Expedition Landing Zone"
	radius = 18
	var/tmp/datum/expedition_site/site

/obj/effect/shuttle_landmark/automatic/clearing/expedition/shuttle_arrived(datum/shuttle/shuttle)
	. = ..()
	if(!site() || shuttle != site().assigned_shuttle())
		return
	site().status = EXP_STATUS_ACTIVE
	EXPIRY_STAMP(site(), deployed_at, CLOCK_WORLD)
	EXPIRY_STAMP(site(), last_occupied, CLOCK_WORLD)
	for(var/area/A in shuttle.shuttle_area)
		for(var/mob/living/L in contents_of(A))
			site().participants |= L

/obj/machinery/computer/shuttle_control/explore
	/// Site currently assigned to this craft.
	var/tmp/datum/expedition_site/active_expedition
	EXPIRY_DECLARE(next_expedition_plot)


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
		rel_set(src, nameof(active_expedition), site)
		EXPIRY_SET(src, next_expedition_plot, EXP_LAUNCH_COOLDOWN, CLOCK_WORLD)

/// The site this landing zone belongs to (a relation view).
/obj/effect/shuttle_landmark/automatic/clearing/expedition/proc/site() as /datum/expedition_site
	return site

/// The site this sector belongs to (a relation view).
/obj/effect/overmap/visitable/sector/expedition/proc/site() as /datum/expedition_site
	return site

/// The site assigned to this craft (pairs with the site's origin_console).
/obj/machinery/computer/shuttle_control/explore/proc/active_expedition() as /datum/expedition_site
	return active_expedition

// The site owns its landing waypoint and overmap sector (implicit OWN); their site vars are plain
// one-sided views. The console and the site name each other (a true two-sided pair).
/obj/effect/overmap/visitable/sector/expedition/relations()
	. = ..()
	. += rel_one(nameof(site))
/obj/effect/shuttle_landmark/automatic/clearing/expedition/relations()
	. = ..()
	. += rel_one(nameof(site))
/datum/expedition_site/relations()
	. = ..()
	. += rel_one(nameof(origin_console), back = nameof(/obj/machinery/computer/shuttle_control/explore::active_expedition))
/obj/machinery/computer/shuttle_control/explore/relations()
	. = ..()
	. += rel_one(nameof(active_expedition), back = nameof(/datum/expedition_site::origin_console))
