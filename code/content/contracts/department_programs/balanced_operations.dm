/datum/contract_definition/social/program/balanced_operations
	id = "balanced_operations_charter"
	title = "Balanced Operations Charter"
	description = "NanoTrasen requests a funded, diversified budget cycle with sustainable payroll coverage."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_COMMAND
	issuer_name = "NanoTrasen Corporate Finance"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3400
	expected_duration = 120 MINUTES
	contract_type = /datum/contract/social/balanced_operations

/datum/contract_definition/social/program/balanced_operations/configure_contract(datum/contract/social/balanced_operations/contract, list/context)
	..()
	add_social_role(contract, "executive", "Executive budget sponsor", "Sets allocations and accepts accountability for the closed cycle.", list(DEPARTMENT_COMMAND), 1, 2)
	add_social_role(contract, "delegate", "Department budget delegate", "Represents operating and workforce needs.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL, DEPARTMENT_RESEARCH, DEPARTMENT_SECURITY, DEPARTMENT_CARGO, DEPARTMENT_CIVILIAN, DEPARTMENT_SYNTHETIC), 5, 9)
	contract.personal_side_definitions = list("command_executive_reserve")
	rel_set(contract, nameof(contract.cycle_requirement), add_program_count(contract, CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 2, "Sustained operating agreement", "Close two distinct station budget cycles with payroll paid first, at least six funded departments, and at least 90% payroll coverage.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "accounting_period", list("rollup" = "station"), list(list("key" = "funded_department_count", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 6), list("key" = "payroll_coverage", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 0.9), list("key" = "station_balance", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 0))))
	var/datum/contract_negotiation_clause/operating_policy = new("operating_policy", "Operating policy", "Choose the station's priority for both covered budget cycles.")
	operating_policy.add_option(make_contract_clause_option("staff", "Staffing first", "Requires 98% payroll coverage across both cycles.", -100, -100, 200, 2, 1, 3, 0, list("budget_profile" = "staff")), TRUE)
	operating_policy.add_option(make_contract_clause_option("departments", "Operations first", "Requires all seven operating departments to receive funding.", -50, 250, -100, 1, 3, 0, 0, list("budget_profile" = "departments")))
	operating_policy.add_option(make_contract_clause_option("reserve", "Reserve first", "Requires a 5,000 Thaler station reserve at settlement.", 250, -100, -150, 2, -1, -1, 0, list("budget_profile" = "reserve")))
	contract.add_negotiation_clause(operating_policy)
