// Mission types for the expedition system.
//
// A mission is a bundle of /datum/expedition_objective (see expedition_objective.dm)
// bound to one /datum/expedition_site. The completion system:
//   * populate(site)       builds the objectives and spawns their content.
//   * check_completion()   polled by SSexpedition.fire(): advances each
//                          objective, fails on a deadline or a party wipe, and
//                          returns TRUE once every REQUIRED objective is done.
//   * on_complete()        pays the base reward plus a bonus for each optional
//                          objective the crew also finished.
// Subtypes just declare build_objectives() — the mix of goals defines the run.

/datum/expedition_mission
	/// Short title shown on the launch console.
	var/name = "Expedition"
	/// Flavour / briefing text.
	var/desc = "A standard expedition."
	/// Difficulty band (EXP_DIFF_*). Scales content and rewards.
	var/difficulty = EXP_DIFF_LOW
	/// EXP_MISSION_* state.
	var/state = EXP_MISSION_ACTIVE
	/// Back-reference to the site, set in populate().
	var/datum/expedition_site/site
	/// Base survey points / Thalers paid on success.
	var/reward_points = 100
	var/reward_cash = 250
	/// The objectives this mission is made of.
	var/list/objectives
	/// Optional time limit (0 = none); failure if the deadline passes.
	var/time_limit = 0
	var/deadline = 0
	/// Optional: pin the site biome (a /datum/expedition_biome subtype). Null = random.
	var/biome_type = null
	/// Optional: pin the enemy faction (EXP_FACTION_*). 0/null = roll one for the site.
	var/faction_type = null

/datum/expedition_mission/New(_difficulty = EXP_DIFF_LOW)
	difficulty = _difficulty
	reward_points = 80 + difficulty * 70
	reward_cash = 150 + difficulty * 200
	objectives = list()

/datum/expedition_mission/Destroy()
	site = null
	if(objectives)
		for(var/datum/expedition_objective/O in objectives)
			qdel(O)
		objectives = null
	return ..()

// Override per mission: return the list of objectives.
/datum/expedition_mission/proc/build_objectives()
	return list()

// Convenience constructors for build_objectives().
/datum/expedition_mission/proc/required_obj(path)
	return new path(TRUE)

/datum/expedition_mission/proc/bonus_obj(path, pts = 50, cash = 0)
	var/datum/expedition_objective/O = new path(FALSE)
	O.bonus_points = pts
	O.bonus_cash = cash
	return O

/datum/expedition_mission/proc/populate(datum/expedition_site/S)
	site = S
	objectives = build_objectives()
	for(var/datum/expedition_objective/O in objectives)
		O.populate(S)
	if(time_limit)
		deadline = world.time + time_limit

// Polled by SSexpedition.fire(). Returns TRUE when all required objectives are
// done; flips state to FAILED on a deadline or a total party wipe.
/datum/expedition_mission/proc/check_completion()
	if(state == EXP_MISSION_COMPLETE)
		return TRUE
	if(state == EXP_MISSION_FAILED)
		return FALSE
	if(deadline && world.time > deadline)
		state = EXP_MISSION_FAILED
		return FALSE
	if(party_wiped())
		state = EXP_MISSION_FAILED
		return FALSE
	var/all_required = TRUE
	for(var/datum/expedition_objective/O in objectives)
		if(O.state == EXP_OBJ_INCOMPLETE)
			O.check()
		if(O.required)
			if(O.state == EXP_OBJ_FAILED)
				state = EXP_MISSION_FAILED
				return FALSE
			if(O.state != EXP_OBJ_COMPLETE)
				all_required = FALSE
	return all_required

// A wipe is when at least one crew deployed and none are left alive.
/datum/expedition_mission/proc/party_wiped()
	if(!site || !length(site.participants))
		return FALSE
	for(var/mob/living/L in site.participants)
		if(!QDELETED(L) && L.stat != DEAD)
			return FALSE
	return TRUE

// Pay base reward + bonus for each completed optional objective. Called once by
// the controller when check_completion() first returns TRUE.
/datum/expedition_mission/proc/on_complete()
	state = EXP_MISSION_COMPLETE
	var/pts = reward_points
	var/cash = reward_cash
	for(var/datum/expedition_objective/O in objectives)
		if(!O.required && O.state == EXP_OBJ_COMPLETE)
			pts += O.bonus_points
			cash += O.bonus_cash
	var/turf/payout_turf = site?.origin_console?.get_return_turf()
	if(site && length(site.participants))
		for(var/mob/living/L in site.participants)
			if(QDELETED(L) || L.stat == DEAD)
				continue
			var/obj/item/card/id/id = L.GetIdCard()
			if(id)
				id.survey_points += pts
				to_chat(L, span_notice("Expedition complete — [pts] survey points credited to [id]."))
			else
				to_chat(L, span_notice("Expedition complete — but you have no ID to credit survey points to."))
	if(payout_turf && cash > 0)
		spawn_money(cash, payout_turf)

// Per-objective rows for the console.
/datum/expedition_mission/proc/objective_rows()
	var/list/rows = list()
	for(var/datum/expedition_objective/O in objectives)
		rows += list(list(
			"text" = O.objective_text(),
			"progress" = O.progress_text(),
			"state" = O.state,
			"required" = O.required,
		))
	return rows

// Compact fallbacks (primary objective) used by older console fields.
/datum/expedition_mission/proc/objective_text()
	if(length(objectives))
		var/datum/expedition_objective/O = objectives[1]
		return O.objective_text()
	return "Reach the site and return safely."

/datum/expedition_mission/proc/progress_text()
	if(length(objectives))
		var/datum/expedition_objective/O = objectives[1]
		return O.progress_text()
	return "-"

// ===========================================================================
// MISSION DEFINITIONS — each is a mix of objectives.
// ===========================================================================

/datum/expedition_mission/survey
	name = "Geological Survey"
	desc = "Deploy to the site and record readings from each survey marker before returning."
	reward_points = 90

/datum/expedition_mission/survey/build_objectives()
	return list(required_obj(/datum/expedition_objective/survey))

/datum/expedition_mission/extermination
	name = "Hostile Clearance"
	desc = "Hostiles have overrun the site. Eliminate the threat."

/datum/expedition_mission/extermination/build_objectives()
	return list(required_obj(/datum/expedition_objective/eliminate_all))

/datum/expedition_mission/salvage
	name = "Salvage Recovery"
	desc = "Recover scattered salvage from the site and return it to the launch pad."
	reward_cash = 400

/datum/expedition_mission/salvage/build_objectives()
	return list(required_obj(/datum/expedition_objective/collect))

/datum/expedition_mission/retrieval
	name = "Artifact Retrieval"
	desc = "A precursor relic lies in a guarded vault. Extract it and bring it back — survey the site for a bonus."
	difficulty = EXP_DIFF_MED
	reward_points = 200

/datum/expedition_mission/retrieval/build_objectives()
	return list(
		required_obj(/datum/expedition_objective/retrieve),
		bonus_obj(/datum/expedition_objective/survey, 70, 0),
	)

/datum/expedition_mission/rescue
	name = "Search & Rescue"
	desc = "A surveyor is stranded in a failing stasis capsule. Recover it before life support gives out."
	reward_points = 180
	time_limit = 8 MINUTES

/datum/expedition_mission/rescue/build_objectives()
	return list(required_obj(/datum/expedition_objective/rescue))

/datum/expedition_mission/derelict
	name = "Derelict Sweep"
	desc = "A derelict outpost has gone dark and hostile. Breach and clear it — recover its salvage for a bonus."
	reward_points = 160
	reward_cash = 350

/datum/expedition_mission/derelict/build_objectives()
	return list(
		required_obj(/datum/expedition_objective/clear_structure),
		bonus_obj(/datum/expedition_objective/collect, 50, 150),
	)

/datum/expedition_mission/raid
	name = "Demolition Raid"
	desc = "An unstable structure guarded by an elite must come down. Slay the elite and demolish the target."
	difficulty = EXP_DIFF_MED
	reward_points = 220
	reward_cash = 300

/datum/expedition_mission/raid/build_objectives()
	return list(
		required_obj(/datum/expedition_objective/destroy),
		required_obj(/datum/expedition_objective/eliminate_boss),
	)

/datum/expedition_mission/recovery
	name = "Black Box Recovery"
	desc = "Recover the relic from the wreck — and pull out any survivor you find for a bonus."
	reward_points = 190

/datum/expedition_mission/recovery/build_objectives()
	return list(
		required_obj(/datum/expedition_objective/retrieve),
		bonus_obj(/datum/expedition_objective/rescue, 90, 0),
	)

/datum/expedition_mission/siege
	name = "Hold the Line"
	desc = "Establish a foothold and hold the site against escalating waves. Slay the elite that shows for a bonus."
	difficulty = EXP_DIFF_MED
	reward_points = 240
	reward_cash = 350

/datum/expedition_mission/siege/build_objectives()
	return list(
		required_obj(/datum/expedition_objective/survive),
		bonus_obj(/datum/expedition_objective/eliminate_boss, 90, 0),
	)

/datum/expedition_mission/recon
	name = "Deep Recon"
	desc = "Push to the far waypoint and survey the site. Hauling back any salvage you find pays a bonus."
	reward_points = 160

/datum/expedition_mission/recon/build_objectives()
	return list(
		required_obj(/datum/expedition_objective/reach),
		required_obj(/datum/expedition_objective/survey),
		bonus_obj(/datum/expedition_objective/collect, 50, 150),
	)

/datum/expedition_mission/restore
	name = "Engine Commissioning"
	desc = "A derelict thermoelectric engine sits cold. Commission it — fuel the burn chamber, start the loop, and bring the generator online. Clearing the hostiles drawn to the work pays a bonus."
	difficulty = EXP_DIFF_MED
	reward_points = 240
	reward_cash = 350

/datum/expedition_mission/restore/build_objectives()
	return list(
		required_obj(/datum/expedition_objective/commission_engine),
		bonus_obj(/datum/expedition_objective/eliminate_all, 80, 100),
	)
