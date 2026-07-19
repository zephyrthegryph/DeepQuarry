/datum/unit_test/dq_generated_station_valid_contract

/datum/unit_test/dq_generated_station_valid_contract/Run()
	var/datum/generated_station_department_definition/engineering = new
	engineering.id = "engineering"
	engineering.minimum_area = 20
	engineering.provisions += new /datum/generated_station_capability_provision("power", 2)
	var/datum/generated_station_department_definition/medical = new
	medical.id = "medical"
	medical.minimum_area = 10
	medical.requirements += new /datum/generated_station_capability_requirement("power", 1)
	var/datum/generated_station_department_instance/engineering_instance = new
	engineering_instance.id = "engineering-1"
	engineering_instance.definition = engineering
	engineering_instance.desired_area = 24
	engineering_instance.layout_node_id = "engineering-node"
	var/datum/generated_station_department_instance/medical_instance = new
	medical_instance.id = "medical-1"
	medical_instance.definition = medical
	medical_instance.desired_area = 12
	medical_instance.layout_node_id = "medical-node"
	var/datum/generated_station_layout_node/engineering_node = new
	engineering_node.id = "engineering-node"
	engineering_node.department_instance_id = engineering_instance.id
	engineering_node.x = 2
	engineering_node.y = 2
	engineering_node.width = 6
	engineering_node.height = 6
	var/datum/generated_station_layout_node/medical_node = new
	medical_node.id = "medical-node"
	medical_node.department_instance_id = medical_instance.id
	medical_node.x = 12
	medical_node.y = 2
	medical_node.width = 5
	medical_node.height = 5
	var/datum/generated_station_layout_edge/hall = new
	hall.id = "main-hall"
	hall.from_node_id = engineering_node.id
	hall.to_node_id = medical_node.id
	hall.kind = GENERATED_STATION_EDGE_TRANSIT
	hall.path = list(list(7, 4), list(8, 4), list(9, 4), list(10, 4), list(11, 4), list(12, 4))
	var/datum/generated_station_spec/spec = new
	spec.maximum_area = 50
	spec.grid_width = 20
	spec.grid_height = 12
	spec.departments = list(engineering_instance, medical_instance)
	spec.layout_nodes = list(engineering_node, medical_node)
	spec.layout_edges = list(hall)
	var/datum/generated_station_validation_result/result = spec.validate()
	TEST_ASSERT(result.is_valid(), "A complete station contract failed validation")
	qdel(result)
	qdel(spec)
	qdel(engineering)
	qdel(medical)

/datum/unit_test/dq_generated_station_reports_contract_gaps

/datum/unit_test/dq_generated_station_reports_contract_gaps/Run()
	var/datum/generated_station_department_definition/department_definition = new
	department_definition.id = "isolated"
	department_definition.minimum_area = 10
	department_definition.requirements += new /datum/generated_station_capability_requirement("atmosphere", 1)
	department_definition.requirements += new /datum/generated_station_capability_requirement("optional-network", 1, TRUE)
	var/datum/generated_station_department_instance/department = new
	department.id = "isolated-1"
	department.definition = department_definition
	department.desired_area = 5
	department.layout_node_id = "missing-node"
	var/datum/generated_station_spec/spec = new
	spec.departments += department
	var/datum/generated_station_validation_result/result = spec.validate()
	TEST_ASSERT(!result.is_valid(), "An invalid station contract passed validation")
	TEST_ASSERT(result.count_severity(GENERATED_STATION_ISSUE_ERROR) >= 3, "Validation omitted required contract errors")
	TEST_ASSERT_EQUAL(result.count_severity(GENERATED_STATION_ISSUE_WARNING), 1, "Optional missing capability was not reported as one warning")
	qdel(result)
	qdel(spec)
	qdel(department_definition)
