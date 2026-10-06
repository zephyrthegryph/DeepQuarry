/**
 * Hand pins of the chemistry numbers (doc/rewrite/reagents.md "Pins"), recorded on the legacy DM math before it moved to Rust
 * (verdigris/domains/chem). Rows: code/modules/unit_tests/snapshots/chem_math/<key>.txt. Re-record:
 * bash tools/dq_focused_test.sh --bless dq_chem_reaction_progress_pin dq_chem_metabolism_pin
 *
 * Reaction progress: for every chemical reaction decl, how far one step goes (calc_reaction_progress()) with its reactants at several
 * multiples of their ratios, with and without product already present (the yield limit). A bare holder: no atom, no reaction runs.
 *
 * Metabolism: a test human with known reagents in each of its three metabolism holders, five Life cycles of metabolize(): every
 * reagent's volume and dose after each cycle.
 */
/datum/unit_test/dq_chem_reaction_progress_pin

/datum/unit_test/dq_chem_reaction_progress_pin/Run()
	var/list/rows = list()
	var/list/decls = GLOB.decls_repository.get_decls_of_subtype(/datum/decl/chemical_reaction)
	var/list/paths = list()
	for(var/path in decls)
		paths += path
	sortTim(paths, GLOBAL_PROC_REF(cmp_text_asc))
	for(var/path in paths)
		var/datum/decl/chemical_reaction/C = decls[path]
		if(!length(C.required_reagents))
			continue
		for(var/k in list(1, 4.3, 25, 150))
			for(var/with_product in list(FALSE, TRUE))
				var/datum/reagents/H = new /datum/reagents(1000000)
				var/limit = INFINITY
				for(var/id in C.required_reagents)
					var/ratio = C.required_reagents[id]
					H.add_reagent(id, ratio * k, safety = 1)
				for(var/id in C.required_reagents)
					limit = min(limit, H.get_reagent_amount(id) / C.required_reagents[id])
				if(with_product && C.result && C.result_amount)
					H.add_reagent(C.result, C.result_amount * k * 0.5, safety = 1)
				var/progress = C.calc_reaction_progress(H, limit)
				rows += "[path] k=[k] product=[with_product] limit=[round(limit, 0.0001)] progress=[round(progress, 0.0001)]"
				qdel(H)
	var/dir = "[DQ_SNAPSHOT_ROOT]chem_math/"
	var/list/bad = list()
	var/failure = dq_snapshot_compare(dir, "chem_math", list(/datum/decl/chemical_reaction = rows), dq_snapshot_read_dir(dir, bad), null)
	TEST_ASSERT(isnull(failure), failure)

/datum/unit_test/dq_chem_metabolism_pin

/// The reagents put in each holder: holder name -> list(id = units).
/datum/unit_test/dq_chem_metabolism_pin/proc/doses()
	return list(
		"bloodstr" = list(REAGENT_ID_BICARIDINE = 12, REAGENT_ID_TRAMADOL = 40, REAGENT_ID_INAPROVALINE = 3.3),
		"ingested" = list(REAGENT_ID_NUTRIMENT = 10, REAGENT_ID_SUGAR = 6, REAGENT_ID_WATER = 20),
		"touching" = list(REAGENT_ID_WATER = 8),
	)

/datum/unit_test/dq_chem_metabolism_pin/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, dq_containment_floor())
	var/list/holders = list("bloodstr" = H.bloodstr, "ingested" = H.ingested, "touching" = H.touching)
	var/list/doses = doses()
	for(var/name in doses)
		var/datum/reagents/metabolism/M = holders[name]
		M.clear_reagents()
		var/list/give = doses[name]
		for(var/id in give)
			M.add_reagent(id, give[id], safety = 1)
	var/list/rows = list()
	for(var/cycle in 1 to 5)
		for(var/name in list("touching", "ingested", "bloodstr"))
			var/datum/reagents/metabolism/M = holders[name]
			M.metabolize()
			var/list/parts = list()
			for(var/datum/reagent/R as anything in M.reagent_list)
				parts += "[R.id]=[round(R.volume, 0.0001)]/[round(R.dose, 0.0001)]"
			sortTim(parts, GLOBAL_PROC_REF(cmp_text_asc))
			rows += "cycle [cycle] [name]: [jointext(parts, " ")]"
	var/dir = "[DQ_SNAPSHOT_ROOT]chem_math/"
	var/list/bad = list()
	var/failure = dq_snapshot_compare(dir, "chem_math", list(/datum/reagents/metabolism = rows), dq_snapshot_read_dir(dir, bad), null)
	TEST_ASSERT(isnull(failure), failure)
