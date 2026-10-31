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
	for(var/datum/xform/R as anything in xform_rules_in(MEDIUM_FIELD, REGIME_FUSION))
		var/datum/xform/a = get_fusion_reaction(R.reactant_a, R.reactant_b)
		var/datum/xform/b = get_fusion_reaction(R.reactant_b, R.reactant_a)
		var/special = R.rule_type == /transformation/fusion/phoron_supermatter
		var/root = length("/transformation/fusion/")
		rows[copytext("[R.rule_type]", root + 1)] = row(R, R.reactant_a, R.reactant_b, R.energy_in, R.energy_out, R.radiation, R.instability, R.field_products, R.min_level, R.min_heat, special, a ? copytext("[a.rule_type]", root + 1) : "-", b ? copytext("[b.rule_type]", root + 1) : "-")
	var/failure = dq_xform_pin_compare(DQ_FUSION_PIN_NAME, rows)
	TEST_ASSERT(isnull(failure), failure)
