/**
 * Fusion table pin (doc/rewrite/proposals/transformations.md section 12), recorded on the legacy /datum/decl/fusion_reaction types before they became
 * /transformation/fusion rules, and kept byte-identical through the conversion.
 *
 * One row per reaction, keyed by its name: the two reactants, the energy it consumes and produces, its radiation and instability, the products, the least
 * field energy and temperature it needs, whether it has a special step (supermatter), and what get_fusion_reaction() answers for the pair in both orders
 * (the table is symmetric, and a pair named by two reactions answers the later one).
 *
 * Rows are `key => value` in code/modules/unit_tests/snapshots/xform/fusion.txt (see dq_xform_pins.dm); an empty file is recorded by the next run.
 */
#define DQ_FUSION_PIN_NAME "fusion"

/datum/unit_test/dq_xform_fusion_pin

/datum/unit_test/dq_xform_fusion_pin/proc/row(name, p_react, s_react, consumption, production, radiation, instability, list/products, min_level, min_temperature, special, answer_a, answer_b)
	var/list/made = list()
	for(var/product in products)
		made += "[product]=[products[product]]"
	return "[p_react]+[s_react]; consumes=[consumption]; produces=[production]; radiation=[radiation]; instability=[instability]; products=[jointext(made, ",")]; min_level=[min_level]; min_temp=[min_temperature]; special=[special ? 1 : 0]; lookup=[answer_a]/[answer_b]"

/datum/unit_test/dq_xform_fusion_pin/Run()
	var/list/rows = list()
	for(var/datum/decl/fusion_reaction/R as anything in subtypesof(/datum/decl/fusion_reaction))
		var/datum/decl/fusion_reaction/made = new R
		var/datum/decl/fusion_reaction/a = get_fusion_reaction(made.p_react, made.s_react)
		var/datum/decl/fusion_reaction/b = get_fusion_reaction(made.s_react, made.p_react)
		var/special = (made.type != /datum/decl/fusion_reaction) && made.type == /datum/decl/fusion_reaction/phoron_supermatter
		rows[copytext("[R]", length("/datum/decl/fusion_reaction/") + 1)] = row(R, made.p_react, made.s_react, made.energy_consumption, made.energy_production, made.radiation, made.instability, made.products, made.minimum_energy_level, made.minimum_reaction_temperature, special, a ? copytext("[a.type]", length("/datum/decl/fusion_reaction/") + 1) : "-", b ? copytext("[b.type]", length("/datum/decl/fusion_reaction/") + 1) : "-")
	var/failure = dq_xform_pin_compare(DQ_FUSION_PIN_NAME, rows)
	TEST_ASSERT(isnull(failure), failure)
