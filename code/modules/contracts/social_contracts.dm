/// Social contract catalog. Every objective consumes ordinary authoritative
/// gameplay events and every exceptional target is intentionally broader than
/// the minimum settlement threshold so heads can choose when to cash out.

/proc/add_social_role(datum/contract/social/contract, id, title, description, list/departments, minimum = 1, maximum = 0)
	return contract.add_stakeholder_role(new /datum/contract_stakeholder_role(id, title, description, departments, minimum, maximum))

/proc/configure_social_identity(datum/contract/social/contract, station_rep, department_rep, staff_rep)
	contract.base_station_reputation_reward = station_rep
	contract.base_department_reputation_reward = department_rep
	contract.base_personal_reputation_reward = staff_rep
	contract.station_reputation_reward = station_rep
	contract.department_reputation_reward = department_rep
	contract.personal_reputation_reward = staff_rep

// Cargo procurement tender
/datum/contract_definition/social/procurement_tender
	id = "station_procurement_tender"
	title = "Station Procurement Tender"
	description = "The Interstellar Traders' Guild requests a transparent procurement cycle with Cargo serving accountable departmental requesters."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CARGO
	issuer_name = "Interstellar Traders' Guild Procurement Exchange"
	issuer_faction = REPUTATION_FACTION_TRADERS_GUILD
	reward = 2600

/datum/contract_definition/social/procurement_tender/configure_contract(datum/contract/social/contract, list/context)
	..()
	configure_social_identity(contract, 8, 26, 14)
	contract.description = "Fulfill a procurement tender worth 2,400 Thalers across six distinct supply categories. A minimum settlement begins at half of every target; broader and more valuable purchasing earns the successful and exceptional grades."
	add_social_role(contract, "procurement", "Cargo procurement lead", "Approves requests and coordinates supply deliveries.", list(DEPARTMENT_CARGO), 1, 2)
	add_social_role(contract, "requester", "Departmental requester", "Commits a department to explain and receive part of the tender.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL, DEPARTMENT_RESEARCH, DEPARTMENT_SECURITY, DEPARTMENT_CIVILIAN, DEPARTMENT_COMMAND), 2, 6)
	contract.personal_side_definitions = list("cargo_local_priority")
	var/datum/contract_requirement/event_count/value = new(CONTRACT_EVENT_SUPPLY_ORDER_FULFILLED, 2400, null, "value", TRUE, CONTRACT_EVIDENCE_SCOPE_ANY)
	value.name = "Delivered procurement value"
	value.description = "Receive up to the exceptional target of 2,400 Thalers in Cargo-funded supply orders."
	value.require_value("funding_department", DEPARTMENT_CARGO)
	contract.add_requirement(value)
	var/datum/contract_requirement/event_count/variety = new(CONTRACT_EVENT_SUPPLY_ORDER_FULFILLED, 6, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_ANY)
	variety.name = "Procurement breadth"
	variety.description = "Receive six distinct supply-pack categories for an exceptional tender."
	variety.require_value("funding_department", DEPARTMENT_CARGO)
	variety.unique_field = "pack_type"
	contract.add_requirement(variety)

// Research market trial
/datum/contract_definition/social/prototype_field_license
	id = "prototype_field_license"
	title = "Prototype Market Trial"
	description = "Eclipse Applied Technologies will fund a trial of Research-built equipment with station personnel as paying customers."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "Eclipse Applied Technologies"
	issuer_faction = REPUTATION_FACTION_ECLIPSE
	reward = 2800

/datum/contract_definition/social/prototype_field_license/configure_contract(datum/contract/social/contract, list/context)
	..()
	configure_social_identity(contract, 8, 28, 16)
	contract.description = "Build and sell a varied range of useful Research equipment to station personnel. Eclipse will judge the trial by sales revenue, the number of buyers served, and the breadth of products adopted."
	add_social_role(contract, "inventor", "Research product lead", "Builds, prices, and supplies equipment for the trial.", list(DEPARTMENT_RESEARCH), 1, 3)
	add_social_role(contract, "tester", "Trial customer", "Purchases station-made equipment for practical use.", null, 3, 8)
	contract.personal_side_definitions = list("research_exclusive_export")
	var/list/metrics = list(
		list("amount", 1800, "Sales revenue", "Earn 1,800 Thalers from Research equipment sales."),
		list("customer_count", 8, "Customer adoption", "Sell to eight distinct station account holders."),
		list("verified_item_count", 8, "Equipment delivered", "Deliver eight physically verified Research products."),
		list("verified_type_count", 4, "Product variety", "Sell equipment from four distinct product types."),
	)
	for(var/list/metric as anything in metrics)
		var/datum/contract_requirement/event_count/requirement = new(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, metric[2], list("department" = DEPARTMENT_RESEARCH, "rollup" = "department"), metric[1], TRUE, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
		requirement.name = metric[3]
		requirement.description = metric[4]
		contract.add_requirement(requirement)

// Engineering reconstruction, generated by real station damage.
/datum/contract_definition/social/emergency_reconstruction_bond
	id = "emergency_reconstruction_bond"
	title = "Emergency Reconstruction Bond"
	description = "NanoTrasen Emergency Works offers a graded reconstruction award after substantial damage to station infrastructure."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_ENGINEERING
	issuer_name = "NanoTrasen Emergency Works"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3200
	initial_offers = 0
	auto_replace = FALSE
	offer_kind = CONTRACT_OFFER_OPPORTUNITY
	candidate_duration = 10 MINUTES

/datum/contract_definition/social/emergency_reconstruction_bond/configure_contract(datum/contract/social/contract, list/context)
	..()
	var/list/affected_assets = opportunity_bound_values(context, "atom_id")
	var/list/affected_asset_names = opportunity_bound_values(context, "asset_label")
	var/list/affected_areas = opportunity_bound_values(context, "area_name")
	configure_social_identity(contract, 12, 30, 16)
	var/asset_roster = length(affected_asset_names) ? english_list(affected_asset_names) : "the structures and machines listed in the incident report"
	var/area_roster = length(affected_areas) ? english_list(affected_areas) : (context?["trigger_area"] || "the affected station areas")
	contract.description = "Restore these damaged assets: [asset_roster]. The incident spans [area_roster]; repairs to unrelated equipment will not count."
	add_social_role(contract, "repair", "Engineering repair lead", "Coordinates safe reconstruction and performs or directs repairs.", list(DEPARTMENT_ENGINEERING), 1, 3)
	add_social_role(contract, "liaison", "Area liaison", "Provides access, priorities, and operational verification for affected departments.", null, 2, 6)
	contract.personal_side_definitions = list("emergency_exclusive_contractor")
	var/repair_target = min(1000, max(150, length(affected_assets) * 75))
	var/datum/contract_requirement/event_count/restoration = new(CONTRACT_EVENT_INFRASTRUCTURE_REPAIRED, repair_target, null, "repair_amount", TRUE, CONTRACT_EVIDENCE_SCOPE_ANY)
	restoration.name = "Restored integrity"
	restoration.description = "Complete [repair_target] points of repair specifically on assets recorded in the originating incident."
	if(length(affected_assets))
		restoration.require_any_value("atom_id", affected_assets)
	contract.add_requirement(restoration)
	// A listed asset can be destroyed or repaired before the offer is accepted;
	// requiring three quarters keeps the commission robust without accepting
	// unrelated replacement work.
	var/asset_target = min(10, max(1, FLOOR(length(affected_assets) * 0.75, 1)))
	var/datum/contract_requirement/event_count/assets = new(CONTRACT_EVENT_INFRASTRUCTURE_REPAIRED, asset_target)
	assets.name = "Distinct repaired assets"
	assets.description = "Repair [asset_target] of the damaged assets named in the incident report."
	assets.unique_field = "atom_id"
	if(length(affected_assets))
		assets.require_any_value("atom_id", affected_assets)
	contract.add_requirement(assets)
	var/area_target = min(4, max(1, length(affected_areas)))
	var/datum/contract_requirement/event_count/areas = new(CONTRACT_EVENT_INFRASTRUCTURE_REPAIRED, area_target)
	areas.name = "Operational reach"
	areas.description = "Restore affected infrastructure across [area_target] incident area[area_target == 1 ? "" : "s"]."
	areas.unique_field = "area_name"
	if(length(affected_areas))
		areas.require_any_value("area_name", affected_areas)
	contract.add_requirement(areas)

// Security restorative settlements
/datum/contract_definition/social/restorative_settlement
	id = "restorative_settlement_program"
	title = "Restorative Settlement Program"
	description = "SolGov Justice Administration funds documented restitution and negotiated release outcomes for custodial cases involving identifiable people."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_SECURITY
	issuer_name = "SolGov Restorative Justice Office"
	issuer_faction = REPUTATION_FACTION_SOLGOV
	reward = 2700

/datum/contract_definition/social/restorative_settlement/configure_contract(datum/contract/social/contract, list/context)
	..()
	configure_social_identity(contract, 12, 28, 14)
	contract.description = "Resolve up to four distinct custodial cases through release or parole and record up to 800 Thalers in voluntary restitution transfers using the exact transfer purpose 'Restorative settlement'."
	add_social_role(contract, "mediator", "Security mediator", "Documents custody and facilitates the agreement.", list(DEPARTMENT_SECURITY), 1, 3)
	add_social_role(contract, "party", "Settlement party", "Participates as a harmed party, responsible party, representative, or guarantor.", null, 2, 8)
	contract.personal_side_definitions = list("security_record_suppression")
	var/datum/contract_requirement/event_count/cases = new(CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, 4, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	cases.name = "Restorative case resolutions"
	cases.description = "Release or parole four distinct people after their custody has been recorded."
	cases.unique_field = "physical_subject_id"
	cases.require_tag("custody_resolution")
	cases.require_value("previous_status", "Incarcerated")
	cases.require_value("physical_custody_verified", TRUE)
	contract.add_requirement(cases)
	var/datum/contract_requirement/event_count/restitution = new(CONTRACT_EVENT_MONEY_TRANSFERRED, 800, null, "amount")
	restitution.name = "Recorded restitution"
	restitution.description = "Transfer 800 Thalers with the payment purpose 'Restorative settlement'."
	restitution.require_value("purpose", "Restorative settlement")
	contract.add_requirement(restitution)

// Civilian hospitality commission
/datum/contract_definition/social/corporate_hospitality
	id = "corporate_hospitality_commission"
	title = "Corporate Hospitality Commission"
	description = "The Traders' Guild commissions a station hospitality program supported by broad paid patronage."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CIVILIAN
	issuer_name = "Interstellar Traders' Guild Hospitality Bureau"
	issuer_faction = REPUTATION_FACTION_TRADERS_GUILD
	reward = 2400

/datum/contract_definition/social/corporate_hospitality/configure_contract(datum/contract/social/contract, list/context)
	..()
	var/customer_target = contract_scaled_participant_target(10, 4, 1)
	configure_social_identity(contract, 8, 24, 18)
	var/revenue_target = customer_target * 200
	var/tip_target = customer_target * 30
	contract.description = "Across closed accounting periods, earn [revenue_target] Thalers from [customer_target] distinct customers and [tip_target] Thalers in voluntary gratuities. Refunded or circular purchases do not count."
	add_social_role(contract, "host", "Hospitality host", "Plans, prices, and provides the commissioned service.", list(DEPARTMENT_CIVILIAN), 1, 4)
	add_social_role(contract, "patron", "Registered patron", "Participates as a paying customer or event sponsor.", null, 4, 12)
	contract.personal_side_definitions = list("service_gratuity_drive")
	for(var/list/metric as anything in list(
		list("amount", revenue_target, "Hospitality revenue"),
		list("customer_count", customer_target, "Distinct patrons"),
		list("tip", tip_target, "Voluntary gratuities"),
	))
		var/datum/contract_requirement/event_count/requirement = new(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, metric[2], list("department" = DEPARTMENT_CIVILIAN, "rollup" = "department"), metric[1], TRUE, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
		requirement.name = metric[3]
		requirement.description = "Reach the exceptional [lowertext(metric[3])] target through paid food and drink service."
		contract.add_requirement(requirement)

// Cross-department manufacturing
/datum/contract_definition/social/interdepartmental_manufacturing
	id = "interdepartmental_manufacturing_bid"
	title = "Interdepartmental Manufacturing Bid"
	description = "NanoTrasen Industrial Planning requests a diversified station-built equipment package with traceable departmental provenance."
	scope = CONTRACT_SCOPE_STATION
	department = DEPARTMENT_COMMAND
	issuer_name = "NanoTrasen Industrial Planning"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3400

/datum/contract_definition/social/interdepartmental_manufacturing/configure_contract(datum/contract/social/contract, list/context)
	..()
	configure_social_identity(contract, 14, 20, 16)
	contract.description = "Fabricate a 2,400-Thaler equipment portfolio spanning eight product types, with contributions from Engineering, Research, and Cargo."
	add_social_role(contract, "engineering", "Engineering fabricator", "Contributes Engineering-built equipment.", list(DEPARTMENT_ENGINEERING), 1, 3)
	add_social_role(contract, "research", "Research fabricator", "Contributes Research-built equipment.", list(DEPARTMENT_RESEARCH), 1, 3)
	add_social_role(contract, "cargo", "Cargo integrator", "Sources materials and contributes Cargo-attributed fabrication.", list(DEPARTMENT_CARGO), 1, 3)
	contract.personal_side_definitions = list("command_executive_reserve")
	var/datum/contract_requirement/fact_portfolio/departments = new(CONTRACT_EVENT_ITEM_PRODUCED, 2400, "department", "value", 3)
	departments.name = "Interdepartmental production value"
	departments.description = "Produce 2,400 Thalers across three contributing departments."
	contract.add_requirement(departments)
	var/datum/contract_requirement/fact_portfolio/designs = new(CONTRACT_EVENT_ITEM_PRODUCED, 2400, "item_type", "value", 8)
	designs.name = "Equipment-package breadth"
	designs.description = "Produce the same value across eight distinct product types."
	contract.add_requirement(designs)

// Workforce compact
/datum/contract_definition/social/workforce_compact
	id = "workforce_productivity_compact"
	title = "Workforce Productivity Compact"
	description = "NanoTrasen Labor Relations offers an operating grant for a funded, broadly represented payroll cycle."
	scope = CONTRACT_SCOPE_STATION
	department = DEPARTMENT_COMMAND
	issuer_name = "NanoTrasen Labor Relations"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3000

/datum/contract_definition/social/workforce_compact/configure_contract(datum/contract/social/contract, list/context)
	..()
	configure_social_identity(contract, 12, 22, 18)
	contract.description = "Close a monthly cycle with up to 20,000 funded allocation Thalers, six funded departments, and full payroll coverage. At least three departmental delegates must approve participation."
	add_social_role(contract, "executive", "Executive sponsor", "Commits the station budget and final payroll policy.", list(DEPARTMENT_COMMAND), 1, 2)
	add_social_role(contract, "delegate", "Department workforce delegate", "Represents departmental compensation and operating needs.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL, DEPARTMENT_RESEARCH, DEPARTMENT_SECURITY, DEPARTMENT_CARGO, DEPARTMENT_CIVILIAN), 3, 8)
	contract.personal_side_definitions = list("command_executive_reserve")
	for(var/list/metric as anything in list(
		list("funded_allocation_total", 20000, "Funded operating allocations"),
		list("funded_department_count", 6, "Represented departments"),
		list("payroll_coverage", 1, "Payroll coverage"),
	))
		var/datum/contract_requirement/event_count/requirement = new(CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, metric[2], list("rollup" = "station"), metric[1])
		requirement.name = metric[3]
		requirement.description = "Reach the exceptional [lowertext(metric[3])] specification in one or more closed budget cycles."
		contract.add_requirement(requirement)

// Medical access program
/datum/contract_definition/social/clinical_access
	id = "clinical_access_program"
	title = "Clinical Access Program"
	description = "VeyMed Community Health funds broad, measurable improvement of real registered conditions across consenting station patients."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_MEDICAL
	issuer_name = "VeyMed Community Health"
	issuer_faction = REPUTATION_FACTION_VEYMED
	reward = 2900

/datum/contract_definition/social/clinical_access/configure_contract(datum/contract/social/contract, list/context)
	..()
	var/patient_target = contract_scaled_participant_target(6, 2)
	var/condition_target = min(4, max(2, CEILING(patient_target / 2, 1)))
	configure_social_identity(contract, 10, 30, 16)
	contract.description = "Improve diagnosed conditions across [patient_target] distinct patients and [condition_target] condition families, with substantial aggregate clinical benefit documented in their records."
	add_social_role(contract, "clinician", "Clinical coordinator", "Coordinates patient access, diagnosis, treatment, and follow-up.", list(DEPARTMENT_MEDICAL), 1, 4)
	add_social_role(contract, "patient", "Participating patient", "Agrees to participate in the access program and its outcome accounting.", null, 3, 10)
	contract.personal_side_definitions = list("clinical_priority_coordinator")
	var/datum/contract_requirement/event_count/patients = new(CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, patient_target, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	patients.name = "Distinct improved patients"
	patients.description = "Improve registered conditions on [patient_target] distinct living patients."
	patients.unique_field = "subject_id"
	contract.add_requirement(patients)
	var/datum/contract_requirement/event_count/improvement = new(CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, patient_target * 40, null, "improvement", TRUE, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	improvement.name = "Clinical improvement"
	improvement.description = "Deliver substantial aggregate improvement across the participating patients."
	contract.add_requirement(improvement)
	var/datum/contract_requirement/event_count/breadth = new(CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, condition_target, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	breadth.name = "Clinical breadth"
	breadth.description = "Treat [condition_target] distinct registered condition types."
	breadth.unique_field = "condition_type"
	contract.add_requirement(breadth)

// Cargo provenance auction
/datum/contract_definition/social/freight_provenance_auction
	id = "freight_provenance_auction"
	title = "Freight Provenance Auction"
	description = "The Traders' Guild offers an auction premium for valuable freight sourced from a broad station producer network."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CARGO
	issuer_name = "Interstellar Traders' Guild Auction House"
	issuer_faction = REPUTATION_FACTION_TRADERS_GUILD
	reward = 3000

/datum/contract_definition/social/freight_provenance_auction/configure_contract(datum/contract/social/contract, list/context)
	..()
	configure_social_identity(contract, 8, 26, 18)
	contract.description = "Export 4,500 Thalers of accepted freight across four origin departments and eight product types. Cargo brokers must recruit at least four supplier stakeholders."
	add_social_role(contract, "broker", "Cargo auction broker", "Coordinates valuation, packaging, and outbound freight.", list(DEPARTMENT_CARGO), 1, 3)
	add_social_role(contract, "supplier", "Station supplier", "Contributes personally or departmentally produced auction lots.", null, 4, 12)
	contract.personal_side_definitions = list("cargo_local_priority")
	var/datum/contract_requirement/fact_portfolio/origins = new(CONTRACT_EVENT_ITEM_EXPORTED, 4500, "origin_department", "value", 4)
	origins.name = "Provenance value"
	origins.description = "Export 4,500 Thalers from four station origin departments."
	origins.require_value("handling_department", DEPARTMENT_CARGO)
	contract.add_requirement(origins)
	var/datum/contract_requirement/fact_portfolio/types = new(CONTRACT_EVENT_ITEM_EXPORTED, 4500, "item_type", "value", 8)
	types.name = "Auction-lot variety"
	types.description = "Export that portfolio across eight product types."
	types.require_value("handling_department", DEPARTMENT_CARGO)
	contract.add_requirement(types)

// Research production and station adoption
/datum/contract_definition/social/publication_patent
	id = "publication_patent_dispute"
	title = "Research Commercialization Portfolio"
	description = "Eclipse requests a substantial portfolio of Research designs followed by verified adoption among station personnel."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "Eclipse Intellectual Property Office"
	issuer_faction = REPUTATION_FACTION_ECLIPSE
	reward = 3100

/datum/contract_definition/social/publication_patent/configure_contract(datum/contract/social/contract, list/context)
	..()
	configure_social_identity(contract, 9, 28, 18)
	contract.description = "Produce a valuable and varied Research portfolio, then prove that station personnel will pay to use it. Production and customer sales are judged separately."
	add_social_role(contract, "author", "Research designer", "Develops and fabricates products for the portfolio.", list(DEPARTMENT_RESEARCH), 1, 4)
	add_social_role(contract, "licensee", "Crew customer", "Purchases station-made technology for practical use.", null, 2, 8)
	contract.personal_side_definitions = list("research_exclusive_export")
	var/datum/contract_requirement/fact_portfolio/production = new(CONTRACT_EVENT_ITEM_PRODUCED, 1800, "item_type", "value", 6, CONTRACT_EVIDENCE_SCOPE_ANY)
	production.name = "Patentable production portfolio"
	production.description = "Produce 1,800 Thalers across six Research designs."
	production.require_value("department", DEPARTMENT_RESEARCH)
	contract.add_requirement(production)
	for(var/list/metric as anything in list(
		list("amount", 1200, "Customer sales"),
		list("customer_count", 5, "Crew customers"),
		list("verified_type_count", 3, "Adopted product variety"),
	))
		var/datum/contract_requirement/event_count/requirement = new(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, metric[2], list("department" = DEPARTMENT_RESEARCH, "rollup" = "department"), metric[1], TRUE, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
		requirement.name = metric[3]
		requirement.description = "Reach the exceptional [lowertext(metric[3])] target."
		contract.add_requirement(requirement)

// Command development grant
/datum/contract_definition/social/station_development_grant
	id = "station_development_grant"
	title = "Station Development Grant"
	description = "NanoTrasen Development funds a cross-department capital program backed by both budget execution and physical station production."
	scope = CONTRACT_SCOPE_STATION
	department = DEPARTMENT_COMMAND
	issuer_name = "NanoTrasen Station Development"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3600

/datum/contract_definition/social/station_development_grant/configure_contract(datum/contract/social/contract, list/context)
	..()
	configure_social_identity(contract, 16, 22, 14)
	contract.description = "Fund 20,000 Thalers across five departments and produce a 2,000-Thaler physical development portfolio spanning three recipient departments."
	add_social_role(contract, "command", "Grant administrator", "Selects recipients and commits station capital.", list(DEPARTMENT_COMMAND), 1, 2)
	add_social_role(contract, "recipient", "Department grant recipient", "Commits a department to turn funding into usable station production.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL, DEPARTMENT_RESEARCH, DEPARTMENT_SECURITY, DEPARTMENT_CARGO, DEPARTMENT_CIVILIAN), 3, 6)
	contract.personal_side_definitions = list("command_executive_reserve")
	var/datum/contract_requirement/event_count/funding = new(CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 20000, list("rollup" = "station"), "funded_allocation_total")
	funding.name = "Executed development funding"
	funding.description = "Fund 20,000 Thalers in a closed station budget cycle."
	contract.add_requirement(funding)
	var/datum/contract_requirement/event_count/departments = new(CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 5, list("rollup" = "station"), "funded_department_count")
	departments.name = "Funded recipients"
	departments.description = "Fund five distinct qualifying departments."
	contract.add_requirement(departments)
	var/datum/contract_requirement/fact_portfolio/production = new(CONTRACT_EVENT_ITEM_PRODUCED, 2000, "department", "value", 3)
	production.name = "Capital production"
	production.description = "Produce 2,000 Thalers of station equipment across three departments."
	contract.add_requirement(production)

// Event-generated supply shortage response
/datum/contract_definition/social/supply_shortage_response
	id = "supply_shortage_response"
	title = "Supply Shortage Response"
	description = "NanoTrasen Logistics offers an outcome award for resolving an active supply shortage reported by station departments."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CARGO
	issuer_name = "NanoTrasen Logistics Recovery"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 2800
	initial_offers = 0
	auto_replace = FALSE
	offer_kind = CONTRACT_OFFER_OPPORTUNITY
	candidate_duration = 10 MINUTES

/datum/contract_definition/social/supply_shortage_response/is_available(list/context)
	return !!context?["shortage_id"]

/datum/contract_definition/social/supply_shortage_response/configure_contract(datum/contract/social/contract, list/context)
	..()
	configure_social_identity(contract, 10, 28, 16)
	var/quantity_target = max(4, context?["quantity_target"] || 8)
	var/variety_target = max(2, context?["variety_target"] || 3)
	contract.description = "Resolve shortage order [context?["shortage_id"]] by delivering [quantity_target] requested units across [variety_target] requested categories aboard the supply shuttle."
	add_social_role(contract, "coordinator", "Cargo response coordinator", "Organizes collection, manifests, and shuttle delivery.", list(DEPARTMENT_CARGO), 1, 3)
	add_social_role(contract, "supplier", "Emergency supplier", "Provides requested goods, reagents, gases, food, or equipment.", null, 3, 10)
	contract.personal_side_definitions = list("cargo_local_priority")
	var/datum/contract_requirement/event_count/quantity = new(CONTRACT_EVENT_SUPPLY_SHORTAGE_DELIVERY, quantity_target, null, "quantity")
	quantity.name = "Delivered shortage quantity"
	quantity.description = "Deliver [quantity_target] requested units for the exceptional grade."
	quantity.require_value("shortage_id", context["shortage_id"])
	contract.add_requirement(quantity)
	var/datum/contract_requirement/event_count/variety = new(CONTRACT_EVENT_SUPPLY_SHORTAGE_DELIVERY, variety_target)
	variety.name = "Shortage-response breadth"
	variety.description = "Satisfy [variety_target] distinct requested categories."
	variety.require_value("shortage_id", context["shortage_id"])
	variety.unique_field = "item_name"
	contract.add_requirement(variety)

// Private counteroffers unique to the new social catalog. Existing Cargo,
// Service, Security, and Command counteroffers are reused above so every
// conflict continues to consume the same ordinary economy/security events.
/datum/contract_definition/personal_outcome/research_exclusive_export
	id = "research_exclusive_export"
	title = "Exclusive Prototype Acquisition"
	description = "Eclipse Special Acquisitions offers a private award for exporting a personally produced Research portfolio instead of preserving the parent contract's internal station market."
	issuer_name = "Eclipse Special Acquisitions"
	issuer_faction = REPUTATION_FACTION_ECLIPSE
	reward = 950

/datum/contract_definition/personal_outcome/research_exclusive_export/configure_contract(datum/contract/personal_outcome/contract, list/context)
	configure_personal_outcome(contract, context, 25 MINUTES)
	contract.personal_reputation_reward = 17
	var/datum/contract_requirement/fact_portfolio/exports = new(CONTRACT_EVENT_ITEM_EXPORTED, 1000, "item_type", "value", 3, CONTRACT_EVIDENCE_SCOPE_OWNER)
	exports.name = "Exclusive Research export"
	exports.description = "Export 1,000 Thalers of your Research-produced equipment across three product types."
	exports.require_value("department", DEPARTMENT_RESEARCH)
	exports.require_value("handling_department", DEPARTMENT_CARGO)
	contract.add_requirement(exports)

/datum/contract_definition/personal_outcome/emergency_exclusive_contractor
	id = "emergency_exclusive_contractor"
	title = "Exclusive Reconstruction Appointment"
	description = "Eclipse Emergency Contracting offers a private premium if you secure the lead reconstruction subcontract at the maximum requested share."
	issuer_name = "Eclipse Emergency Contracting"
	issuer_faction = REPUTATION_FACTION_ECLIPSE
	reward = 800

/datum/contract_definition/personal_outcome/emergency_exclusive_contractor/configure_contract(datum/contract/personal_outcome/contract, list/context)
	configure_personal_outcome(contract, context, 15 MINUTES)
	contract.personal_reputation_reward = 14
	var/datum/contract_requirement/event_count/appointment = new(CONTRACT_EVENT_STAKEHOLDER_APPROVED, 1, list("contract_id" = context["parent_contract_id"], "role_id" = context["role_id"]), null, TRUE, CONTRACT_EVIDENCE_SCOPE_OWNER)
	appointment.name = "Exclusive lead appointment"
	appointment.description = "Receive the Engineering repair-lead subcontract at lead share weight three."
	appointment.require_number("requested_weight", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3)
	contract.add_requirement(appointment)

/datum/contract_definition/personal_outcome/clinical_priority_coordinator
	id = "clinical_priority_coordinator"
	title = "Preferred Clinical Coordinator"
	description = "Chimera Clinical Partnerships offers a private premium if you secure the program's lead clinical subcontract at the maximum requested share."
	issuer_name = "Chimera Clinical Partnerships"
	issuer_faction = REPUTATION_FACTION_CHIMERA
	reward = 850

/datum/contract_definition/personal_outcome/clinical_priority_coordinator/configure_contract(datum/contract/personal_outcome/contract, list/context)
	configure_personal_outcome(contract, context, 15 MINUTES)
	contract.personal_reputation_reward = 15
	var/datum/contract_requirement/event_count/appointment = new(CONTRACT_EVENT_STAKEHOLDER_APPROVED, 1, list("contract_id" = context["parent_contract_id"], "role_id" = context["role_id"]), null, TRUE, CONTRACT_EVIDENCE_SCOPE_OWNER)
	appointment.name = "Preferred coordinator appointment"
	appointment.description = "Receive the Medical clinician subcontract at lead share weight three."
	appointment.require_number("requested_weight", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3)
	contract.add_requirement(appointment)
