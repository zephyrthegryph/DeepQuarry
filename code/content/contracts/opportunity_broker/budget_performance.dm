/datum/contract_opportunity_rule/budget_performance
	id = "budget_performance"
	definition_id = "opportunity_operational_dividend"
	description = "A broadly funded payroll cycle qualified the station for an operational dividend mandate."
	window_duration = 20 MINUTES
	cooldown = 30 MINUTES

/datum/contract_opportunity_rule/budget_performance/configure()
	var/datum/contract_opportunity_signal/cycle = add_signal(new /datum/contract_opportunity_signal("cycle", CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 1))
	cycle.require_value("rollup", "station")
	cycle.require_number("payroll_coverage", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 0.9)
	cycle.require_number("funded_department_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 6)
	cycle.require_number("funded_allocation_total", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 20000)
