/datum/unit_test/dq_generated_room_definitions_are_valid

/datum/unit_test/dq_generated_room_definitions_are_valid/Run()
	var/list/catalog = generated_room_definition_catalog()
	var/list/ids = list()
	for(var/datum/generated_room_definition/definition in catalog)
		TEST_ASSERT(definition.is_contract_valid(), "Room definition [definition.type] has an invalid dimensional or density contract")
		TEST_ASSERT(istype(definition.room_style, /datum/generated_room_style), "Room definition [definition.id] has no typed visual style")
		TEST_ASSERT(ispath(definition.room_style.floor_type, /turf/simulated/floor), "Room definition [definition.id] has an invalid floor override")
		TEST_ASSERT(!ids[definition.id], "Room definition ID [definition.id] is duplicated")
		ids[definition.id] = TRUE
		for(var/feature_type in definition.required_features)
			var/datum/generated_room_feature/feature = new feature_type
			TEST_ASSERT(feature.id && ispath(feature.atom_type, /atom), "Room [definition.id] has a malformed feature declaration")
			qdel(feature)
		for(var/group_type in definition.required_groups + definition.optional_groups)
			var/datum/generated_room_feature_group/group = new group_type
			TEST_ASSERT(group.id && length(group.feature_types), "Room [definition.id] has an empty feature group")
			for(var/feature_type in group.feature_types)
				var/datum/generated_room_feature/feature = new feature_type
				TEST_ASSERT(feature.id && ispath(feature.atom_type, /atom), "Room [definition.id] group [group.id] has a malformed feature")
				qdel(feature)
			qdel(group)
	TEST_ASSERT_EQUAL(length(catalog), 14, "Room catalog does not cover every department module role")
	QDEL_LIST(catalog)

/datum/unit_test/dq_generated_room_styles_are_department_specific

/datum/unit_test/dq_generated_room_styles_are_department_specific/Run()
	var/datum/generated_room_definition/ai_core/ai = new
	var/datum/generated_room_definition/surgery/medical = new
	var/datum/generated_room_definition/engineering_power/engineering = new
	var/datum/generated_room_definition/logistics_cargo/cargo = new
	TEST_ASSERT(istype(ai.room_style, /datum/generated_room_style/ai), "AI core lost its room-specific flooring style")
	TEST_ASSERT(ai.room_style.floor_type != medical.room_style.floor_type, "AI and medical rooms unexpectedly share flooring")
	TEST_ASSERT(engineering.room_style.accent_color != cargo.room_style.accent_color, "Engineering and cargo trim colors are not distinguishable")
	TEST_ASSERT(ai.room_style.aesthetic_id != medical.room_style.aesthetic_id, "Room style metadata does not distinguish AI from medical")
	qdel(ai)
	qdel(medical)
	qdel(engineering)
	qdel(cargo)

/datum/unit_test/dq_generated_room_fragments_have_valid_sockets

/datum/unit_test/dq_generated_room_fragments_have_valid_sockets/Run()
	var/datum/generated_room_fragment/reception_corner/fragment = new
	TEST_ASSERT(fragment.template_path && fragment.width > 0 && fragment.height > 0, "Reception fragment has no usable footprint or template")
	var/list/socket_ids = list()
	for(var/datum/generated_room_fragment_socket/socket in fragment.sockets)
		TEST_ASSERT(socket.id && !socket_ids[socket.id], "Reception fragment has a missing or duplicate socket ID")
		TEST_ASSERT(socket.edge in list(NORTH, SOUTH, EAST, WEST), "Fragment socket [socket.id] is not on a cardinal edge")
		TEST_ASSERT(socket.offset >= 1, "Fragment socket [socket.id] has an invalid offset")
		socket_ids[socket.id] = TRUE
	TEST_ASSERT(socket_ids["staff-door"] && socket_ids["public-frontage"], "Reception fragment omitted its access or circulation socket")
	qdel(fragment)

/datum/unit_test/dq_generated_room_selection_is_deterministic

/datum/unit_test/dq_generated_room_selection_is_deterministic/Run()
	var/datum/generated_room_definition/surgery/definition = new
	var/datum/generated_room_content_plan/first = definition.build_content_plan(424242, "research", "sterile")
	var/datum/generated_room_content_plan/second = definition.build_content_plan(424242, "research", "sterile")
	TEST_ASSERT_EQUAL(first.variant_id, "sterile-research", "Matching faction/style did not select the only compatible room variant")
	TEST_ASSERT_EQUAL(first.variant_id, second.variant_id, "Same room seed changed the selected variant")
	TEST_ASSERT_EQUAL(json_encode(first.feature_types), json_encode(second.feature_types), "Same room seed changed required features")
	TEST_ASSERT_EQUAL(json_encode(first.group_types), json_encode(second.group_types), "Same room seed changed feature groups")
	qdel(first)
	qdel(second)
	qdel(definition)

/datum/unit_test/dq_generated_room_catalog_covers_module_roles

/datum/unit_test/dq_generated_room_catalog_covers_module_roles/Run()
	var/list/departments = list("command", "ai", "security", "medical", "engineering", "logistics", "docking")
	var/list/definition_ids = list()
	var/resolved = 0
	for(var/department_id in departments)
		var/list/roles = generated_station_rust_room_roles(department_id)
		TEST_ASSERT_EQUAL(length(roles), 8, "Department [department_id] did not expose eight station-like room roles")
		for(var/role in roles)
			var/datum/generated_room_definition/definition = generated_room_definition_for(department_id, role)
			TEST_ASSERT(definition, "No room definition exists for [department_id]/[role]")
			TEST_ASSERT(!definition_ids[definition.id], "Two module roles share room definition ID [definition.id]")
			definition_ids[definition.id] = TRUE
			TEST_ASSERT(length(definition.required_features) || length(definition.required_groups), "Room [definition.id] has no required functional content")
			resolved++
			qdel(definition)
	TEST_ASSERT_EQUAL(resolved, 56, "Not every generated-station room role resolved a functional definition")

/datum/unit_test/dq_generated_room_roles_have_authored_signatures

/datum/unit_test/dq_generated_room_roles_have_authored_signatures/Run()
	var/list/departments = list("command", "ai", "security", "medical", "engineering", "logistics", "docking")
	var/list/issues = list()
	for(var/department_id in departments)
		for(var/role in generated_station_rust_room_roles(department_id))
			var/datum/generated_room_definition/definition = generated_room_definition_for(department_id, role)
			if(!definition)
				issues += "[department_id]/[role] has no authored definition"
				continue
			var/list/atom_types = list()
			for(var/feature_type in definition.required_features)
				var/datum/generated_room_feature/feature = new feature_type
				atom_types |= feature.atom_type
				qdel(feature)
			for(var/group_type in definition.required_groups)
				var/datum/generated_room_feature_group/group = new group_type
				for(var/feature_type in group.feature_types)
					var/datum/generated_room_feature/feature = new feature_type
					atom_types |= feature.atom_type
					qdel(feature)
				qdel(group)
			if(length(atom_types) < 3)
				issues += "[department_id]/[role] has only [length(atom_types)] functional fixture types"
			for(var/required_type in generated_room_required_signature(department_id, role))
				var/found = FALSE
				for(var/content_type in atom_types)
					if(ispath(content_type, required_type))
						found = TRUE
						break
				if(!found)
					issues += "[department_id]/[role] is missing [required_type]"
			qdel(definition)
	TEST_ASSERT(!length(issues), "Authored room contract failures: [jointext(issues, "; ")]")

/datum/unit_test/dq_generated_room_constraints_are_typed

/datum/unit_test/dq_generated_room_constraints_are_typed/Run()
	var/datum/generated_room_feature/reception_chair/chair = new
	TEST_ASSERT_EQUAL(length(chair.constraints), 2, "Reception chair lost a placement constraint")
	TEST_ASSERT(istype(chair.constraints[1], /datum/generated_room_constraint/faces_feature), "Reception chair facing rule is not a typed constraint")
	TEST_ASSERT(istype(chair.constraints[2], /datum/generated_room_constraint/requires_access_path), "Reception chair accessibility rule is not a typed constraint")
	qdel(chair)

/datum/unit_test/dq_generated_room_wall_constraints_match_placement

/datum/unit_test/dq_generated_room_wall_constraints_match_placement/Run()
	var/list/issues = list()
	for(var/feature_type in subtypesof(/datum/generated_room_feature))
		var/datum/generated_room_feature/feature = new feature_type
		for(var/datum/generated_room_constraint/constraint in feature.constraints)
			if(istype(constraint, /datum/generated_room_constraint/against_wall) && feature.placement_kind != "wall")
				issues += "[feature_type] requires a wall but uses placement kind '[feature.placement_kind]'"
		qdel(feature)
	TEST_ASSERT(!length(issues), "Generated-room wall metadata is inconsistent: [jointext(issues, "; ")]")

/datum/unit_test/dq_generated_room_definition_lookup_is_fresh

/datum/unit_test/dq_generated_room_definition_lookup_is_fresh/Run()
	var/datum/generated_room_definition/first = generated_room_definition_for("medical", "treatment")
	var/datum/generated_room_definition/second = generated_room_definition_for("medical", "treatment")
	TEST_ASSERT(istype(first, /datum/generated_room_definition/surgery), "Medical treatment did not resolve to a surgery contract")
	TEST_ASSERT(first != second, "Room definition lookup reused mutable definition state")
	TEST_ASSERT(isnull(generated_room_definition_for("medical", "unknown")), "Unknown room role unexpectedly resolved a contract")
	qdel(first)
	qdel(second)

/datum/unit_test/dq_generated_room_hard_dependencies_are_ordered

/datum/unit_test/dq_generated_room_hard_dependencies_are_ordered/Run()
	var/list/catalog = generated_room_definition_catalog()
	for(var/datum/generated_room_definition/definition in catalog)
		var/datum/generated_room_content_plan/plan = definition.build_content_plan(31337, "corporate", "industrial")
		var/list/ordered_types = plan.feature_types.Copy()
		for(var/group_type in plan.group_types)
			var/datum/generated_room_feature_group/group = new group_type
			ordered_types += group.feature_types
			qdel(group)
		var/list/available_ids = list()
		for(var/feature_type in ordered_types)
			var/datum/generated_room_feature/feature = new feature_type
			for(var/datum/generated_room_constraint/constraint in feature.constraints)
				if(constraint.hard && constraint.target_id && (istype(constraint, /datum/generated_room_constraint/faces_feature) || istype(constraint, /datum/generated_room_constraint/near_feature)))
					TEST_ASSERT(available_ids[constraint.target_id], "Room [definition.id] places [feature.id] before required target [constraint.target_id]")
			available_ids[feature.id] = TRUE
			qdel(feature)
		qdel(plan)
	QDEL_LIST(catalog)
