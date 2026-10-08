// The material module's per-object records (code/modules/materials/engineering/material_state.dm) and the engine's
// per-atom record (code/datums/capabilities/capabilities.dm): they live in cap_data, not in base-type vars, and the
// saved part rides beside the delta (state_extra()/state_apply_extra(), code/datums/state/schema.dm).

/// Overrides, an arbitrary mix, wear and the engineered effects survive serialize -> materialize, and an untouched
/// object adds nothing to its blob.
/datum/unit_test/dq_material_state_round_trip

/datum/unit_test/dq_material_state_round_trip/Run()
	var/turf/floor = test_floor()
	var/list/errors = list()

	var/obj/item/dq_matter_test/tool/plain = allocate(/obj/item/dq_matter_test/tool, floor)
	var/list/plain_blob = state_serialize(plain, STATE_FULL, errors)
	TEST_ASSERT_NOTNULL(plain_blob, "an unmodified tool serializes: [jointext(errors, "; ")]")
	TEST_ASSERT_NULL(plain_blob[STATE_KEY_EXTRA], "an unmodified object has no extra state of its own")

	// A per-role override and the wear of a leaking, fatigued assembly.
	var/obj/item/dq_matter_test/tool/worn = allocate(/obj/item/dq_matter_test/tool, floor)
	worn.set_construction_material(MATERIAL_ROLE_GRIP, MAT_WOOD)
	var/datum/material_assembly/wear = material_assembly(worn)
	wear.fatigue = 12
	wear.leaking = TRUE
	wear.liner_integrity = 40
	wear.custom = TRUE
	var/datum/material_build/build = material_build(worn)
	build.engineered_id = MAT_STEEL
	build.profile = MATERIAL_APPLICATION_TOOL
	build.tool_quality_bonus = 7
	build.effective_density = 61.5
	errors = list()
	var/list/blob = state_serialize(worn, STATE_FULL, errors)
	TEST_ASSERT_NOTNULL(blob, "a tool with its own material state serializes: [jointext(errors, "; ")]")
	TEST_ASSERT_NOTNULL(blob[STATE_KEY_EXTRA], "its records ride beside the delta")
	var/expected = state_canonical(blob)
	for(var/pass in 1 to 2)
		var/list/source = pass == 1 ? blob : json_decode(json_encode(blob))
		errors = list()
		var/obj/item/dq_matter_test/tool/copy = state_materialize(source, floor, STATE_FULL, errors)
		TEST_ASSERT_NOTNULL(copy, "[pass == 2 ? "through JSON: " : ""]it materializes: [jointext(errors, "; ")]")
		TEST_ASSERT_EQUAL(copy.material_for_role(MATERIAL_ROLE_GRIP)?.name, MAT_WOOD, "the override fills its role again")
		TEST_ASSERT(material_build_view(copy).overrides == material_build_view(worn).overrides, "and is the same interned list")
		var/datum/material_assembly/restored_wear = material_assembly_view(copy)
		TEST_ASSERT_EQUAL(restored_wear.fatigue, 12, "fatigue comes back")
		TEST_ASSERT(restored_wear.leaking, "so does the leak")
		TEST_ASSERT_EQUAL(restored_wear.liner_integrity, 40, "and the liner")
		TEST_ASSERT_EQUAL(restored_wear.exterior_integrity, 100, "an untouched surface stays intact")
		TEST_ASSERT(restored_wear.custom, "and the fabricated flag")
		var/datum/material_build/restored_build = material_build_view(copy)
		TEST_ASSERT_EQUAL(restored_build.engineered_id, MAT_STEEL, "the engineered id comes back")
		TEST_ASSERT_EQUAL(restored_build.profile, MATERIAL_APPLICATION_TOOL, "and its profile")
		TEST_ASSERT_EQUAL(restored_build.tool_quality_bonus, 7, "and its bonus")
		TEST_ASSERT_EQUAL(restored_build.effective_density, 61.5, "and the effective density")
		TEST_ASSERT_EQUAL(dq_state_canonical_of(copy, errors), expected, "the copy serializes to the same state")
		qdel(copy)

	// An arbitrary mix is genuine per-instance state.
	var/obj/item/dq_matter_test/single/holder = allocate(/obj/item/dq_matter_test/single, floor)
	holder.add_materials(list(MAT_GLASS = 25))
	errors = list()
	var/obj/item/dq_matter_test/single/mixed = state_materialize(state_serialize(holder, STATE_FULL, errors), floor, STATE_FULL, errors)
	TEST_ASSERT_NOTNULL(mixed, "an item with a mix round-trips: [jointext(errors, "; ")]")
	TEST_ASSERT(dq_matter_lists_equal(mixed.material_totals(), list(MAT_STEEL = 300, MAT_GLASS = 25)), "and keeps what it is made of, got [dq_matter_text(mixed.material_totals())]")
	qdel(mixed)

	// A blob that carries no records puts a materialized copy's saved fields at their defaults.
	var/obj/item/dq_matter_test/tool/target = allocate(/obj/item/dq_matter_test/tool, floor)
	target.set_construction_material(MATERIAL_ROLE_GRIP, MAT_WOOD)
	material_assembly(target).fatigue = 30
	errors = list()
	TEST_ASSERT(state_apply(target, plain_blob, STATE_FULL, errors), "a blob applies onto an existing tool: [jointext(errors, "; ")]")
	TEST_ASSERT_NULL(material_build_view(target).overrides, "its overrides are gone")
	TEST_ASSERT_EQUAL(material_assembly_view(target).fatigue, 0, "and its wear")

/// A live service or response is wiring, not state: its holder refuses serialization and stays materialised.
/datum/unit_test/dq_material_state_pins_live_wiring

/datum/unit_test/dq_material_state_pins_live_wiring/Run()
	var/turf/floor = test_floor()
	var/obj/item/dq_matter_test/tool/tool = allocate(/obj/item/dq_matter_test/tool, floor)
	var/list/errors = list()
	TEST_ASSERT(state_can_serialize(tool), "a tool with no wiring serializes")
	var/datum/material_service/service = tool.enable_material_service()
	TEST_ASSERT_NOTNULL(service, "the tool has a material service")
	TEST_ASSERT_EQUAL(material_service_of(tool), service, "which is its assembly's service")
	TEST_ASSERT_NULL(state_serialize(tool, STATE_FULL, errors), "a live service pins its holder")
	TEST_ASSERT(findtext(jointext(errors, "; "), "material service"), "and says why: [jointext(errors, "; ")]")
	qdel(service)
	TEST_ASSERT(state_can_serialize(tool), "the holder serializes again once the service is gone")

	var/obj/item/dq_matter_test/tool/armed = allocate(/obj/item/dq_matter_test/tool, floor)
	new /datum/material_response(armed, get_material_by_name(MAT_STEEL), FALSE, FALSE, FALSE, TRUE)
	TEST_ASSERT_NOTNULL(material_build_view(armed).response, "the response is its build record's")
	errors = list()
	TEST_ASSERT_NULL(state_serialize(armed, STATE_FULL, errors), "a live response pins its holder")
	TEST_ASSERT(findtext(jointext(errors, "; "), "material response"), "and says why: [jointext(errors, "; ")]")

/// Deleting the holder deletes its records and the service they own, against a live owner.
/datum/unit_test/dq_material_state_teardown

/datum/unit_test/dq_material_state_teardown/Run()
	var/obj/item/cell/cell = allocate(/obj/item/cell, test_floor())
	var/datum/material_service/service = cell.enable_material_service()
	TEST_ASSERT_NOTNULL(service, "the cell has a material service")
	var/datum/material_assembly/assembly = material_assembly_of(cell)
	TEST_ASSERT_NOTNULL(assembly, "its service lives in an assembly record")
	var/datum/material_build/build = material_build(cell)
	qdel(cell)
	TEST_ASSERT(QDELETED(service), "the service is deleted with its holder")
	TEST_ASSERT(QDELETED(assembly), "and so is the assembly record")
	TEST_ASSERT(QDELETED(build), "and the build record")

/// The engine's lazy per-atom record: look_flash() and entry cooldowns keep nothing on the atom until used.
/datum/unit_test/dq_cap_engine_state

/datum/unit_test/dq_cap_engine_state/Run()
	var/obj/item/pen/pen = allocate(/obj/item/pen, test_floor())
	TEST_ASSERT_NULL(cap_engine_state_of(pen), "an atom the engine has kept nothing for has no record")
	look_flash(pen, "pointer_flash", 5 SECONDS)
	var/datum/cap_engine_state/engine = cap_engine_state_of(pen)
	TEST_ASSERT_NOTNULL(engine, "a flash makes the record")
	TEST_ASSERT(engine.look_flashes?["pointer_flash"], "which holds the overlay it is showing")
	var/token = engine.look_flash_tokens["pointer_flash"]
	look_flash_end(pen, "pointer_flash", "not-the-live-token", FALSE)
	TEST_ASSERT(engine.look_flashes?["pointer_flash"], "a stale token ends nothing")
	look_flash_end(pen, "pointer_flash", token, FALSE)
	TEST_ASSERT(!length(engine.look_flashes), "the live token takes the overlay back")
	look_flash(pen, "lit", 5 SECONDS, as_state = TRUE)
	TEST_ASSERT_EQUAL(engine.look_flash_state, "lit", "a base-state flash is kept as the state")
	qdel(pen)
	TEST_ASSERT(QDELETED(engine), "the record goes with its atom")

/// A thermite-treated wall draws its coating through the declared wall appearance.
/datum/unit_test/dq_wall_thermite_coating

/datum/unit_test/dq_wall_thermite_coating/Run()
	var/turf/floor = test_floor()
	var/turf/wall_turf = get_step(floor, NORTH) || get_step(floor, SOUTH)
	var/old_type = wall_turf.type
	wall_turf.ChangeTurf(/turf/simulated/wall)
	var/turf/simulated/wall/wall = wall_turf
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	wall.apply_materials(steel, steel, steel)
	TEST_ASSERT(!(wall_thermite_coat() in wall.appearance_overlays()), "a bare wall draws no coating")
	TEST_ASSERT(wall.set_thermite(TRUE), "set_thermite() reports the change")
	TEST_ASSERT(wall_thermite_coat() in wall.appearance_overlays(), "a coated wall draws it")
	TEST_ASSERT(!wall.set_thermite(TRUE), "and a second write reports none")
	TEST_ASSERT(icon_exists('icons/effects/effects.dmi', "thermite"), "the coating is a state the file has")
	wall_turf.ChangeTurf(old_type)
