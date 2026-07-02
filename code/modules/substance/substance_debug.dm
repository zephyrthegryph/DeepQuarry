// Debug entry points for validating the substance resolver (design doc §16 Phase 1).
//
// The production flow (alloying machine + console) lands in a later phase; these
// verbs let an admin exercise the pure engine: combine two source substances and
// read the full breakdown, or run a session simulation to eyeball the
// emergent-vs-noise line (do the same two sources combine consistently this round,
// differently next round, and surprise *sometimes* without being random noise?).

/client/verb/substance_combine_test()
	set name = "Substance: Combine Test"
	set category = "Debug"

	if(!check_rights(R_DEBUG))
		return

	var/list/ids = substance_archetype_ids()
	var/id_a = input(usr, "First source substance?", "Substance Combine") as null|anything in ids
	if(!id_a)
		return
	var/id_b = input(usr, "Second source substance?", "Substance Combine") as null|anything in ids
	if(!id_b)
		return

	var/datum/substance/A = substance_from_archetype(id_a)
	var/datum/substance/B = substance_from_archetype(id_b)
	if(!A || !B)
		to_chat(usr, span_warning("Could not build those source substances."))
		return

	var/datum/substance_reaction/R = substance_combine(A, B)
	var/list/out = list()
	out += "<b>Combine</b> [A.describe_full()]"
	out += "<b>  with</b> [B.describe_full()]"
	out += "----"
	for(var/line in R.log_lines)
		out += line
	out += "----"
	out += R.output ? "<b>Output:</b> [R.output.describe_full()]" : "<b>Output:</b> (none — bond failed)"
	if(length(R.byproducts))
		for(var/datum/substance/bp in R.byproducts)
			out += "Byproduct: [bp.describe_full()]"
	if(R.hazard)
		out += span_warning("Hazard: [R.hazard.desc] (severity [R.hazard.severity])")
	to_chat(usr, jointext(out, "<br>"))

	qdel(R)
	qdel(A)
	qdel(B)

// Run N combines of two chosen sources to see how stable/varied the result is
// within one round (purity wobble + byproduct/hazard rolls are the only variance;
// the profiles themselves are fixed this round).
/client/verb/substance_session_sim()
	set name = "Substance: Session Simulation"
	set category = "Debug"

	if(!check_rights(R_DEBUG))
		return

	var/list/ids = substance_archetype_ids()
	var/id_a = input(usr, "First source substance?", "Substance Sim") as null|anything in ids
	if(!id_a)
		return
	var/id_b = input(usr, "Second source substance?", "Substance Sim") as null|anything in ids
	if(!id_b)
		return
	var/runs = input(usr, "How many combines?", "Substance Sim", 8) as null|num
	if(!runs)
		return
	runs = clamp(round(runs), 1, 50)

	var/list/out = list("<b>[runs]x</b> [id_a] + [id_b] (this round)")
	var/hazards = 0
	for(var/i in 1 to runs)
		var/datum/substance/A = substance_from_archetype(id_a)
		var/datum/substance/B = substance_from_archetype(id_b)
		var/datum/substance_reaction/R = substance_combine(A, B)
		var/fam = R.output ? substance_family_name(R.output.family) : "none"
		out += "#[i]: [substance_relationship_name(R.relationship)] -> [fam] (M[R.magnitude] V[R.control] P[R.purity])[R.hazard ? " HAZARD" : ""]"
		if(R.hazard)
			hazards++
		qdel(R)
		qdel(A)
		qdel(B)
	out += "----"
	out += "Hazards: [hazards]/[runs]. Round salt is fixed, so the relationship is stable; magnitude/byproducts wobble with purity."
	to_chat(usr, jointext(out, "<br>"))

// Drop the substance machines plus a forge-ready stack of every source archetype at
// the admin's feet, so the whole loop can be exercised without flying an expedition.
/client/verb/substance_spawn_kit()
	set name = "Substance: Spawn Test Kit"
	set category = "Debug"

	if(!check_rights(R_DEBUG))
		return

	var/turf/T = get_turf(mob)
	if(!T)
		return
	new /obj/machinery/substance_combiner(T)
	new /obj/machinery/substance_refiner(T)
	new /obj/machinery/substance_extractor(T)
	// A forge-ready stack of each source archetype's material (combine/refine/forge).
	for(var/id in substance_archetype_ids())
		var/datum/substance/S = substance_from_archetype(id, 10)
		substance_spawn_stack(T, S, 20)
		qdel(S)
	to_chat(usr, span_notice("Spawned combiner/refiner/extractor and a forge-ready stack of each source substance."))
