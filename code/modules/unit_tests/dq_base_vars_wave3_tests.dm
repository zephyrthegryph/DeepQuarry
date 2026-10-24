// base_vars wave 3: the vars that left the base types (sparse slots and the buckle_rules, movable_motion, atom_rules, living_rules, mob_rules,
// butchery_rules, footstep_rules, machine_rules and item_rules traits) must still be seen and edited by name: View Variables, mass edit
// and SDQL reach each of them as they reached the var, and each reads as the default the var had until it is set.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Every slot of this wave: list(owner type, slot name, a value to set, the default it reads as).
/proc/dq_wave3_slot_rows()
	var/static/list/rows = list(
		list(/mob, "is_floating", 1, 0),
		list(/mob, "muffled", TRUE, FALSE),
		list(/mob, "autowhisper", TRUE, FALSE),
		list(/mob, "lying_prev", 1, 0),
		list(/mob, "seer", 1, 0),
		list(/mob, "in_throw_mode", 1, 0),
		list(/mob, "is_motion_tracking", TRUE, FALSE),
		list(/mob, "wants_to_see_motion_echos", FALSE, TRUE),
		list(/mob, "voice_freq", 1000, 42500),
		list(/mob/living, "flight_vore", TRUE, FALSE),
		list(/mob/living, "tod", "12:00", null),
		list(/mob/living, "is_swinging", TRUE, FALSE),
		list(/mob/living, "is_ventcrawling", TRUE, FALSE),
		list(/mob/living, "weight_gain", 2, 1),
		list(/mob/living, "weight_loss", 2, 0.5),
		list(/mob/living, "vore_egg_type", "snake", "egg"),
		list(/mob/living, "stuffing_feeder", TRUE, FALSE),
		list(/mob/living, "appendage_alt_setting", TRUE, FALSE),
		list(/mob/living/carbon, "dream_wait", 5, 0),
		list(/mob/living/carbon/human, "markings_len", 3, 0),
		list(/mob/living/carbon/human, "resleeve_lock", "somekey", null),
	)
	return rows

/// Every trait var of this wave: list(holder type, old var name, a value to set).
/proc/dq_wave3_trait_rows()
	var/static/list/rows = list(
		list(/obj/item/pen, "buckle_dir", NORTH),
		list(/obj/item/pen, "buckle_lying", 1),
		list(/obj/item/pen, "buckle_movable", 1),
		list(/obj/item/pen, "buckle_require_restraints", 1),
		list(/obj/item/pen, "max_buckled_mobs", 3),
		list(/obj/item/pen, "throw_speed", 9),
		list(/obj/item/pen, "icon_expected_height", 64),
		list(/obj/item/pen, "does_spin", FALSE),
		list(/obj/item/pen, "unacidable", FALSE),
		list(/obj/item/pen, "light_cone_x_offset", 4),
		list(/obj/item/pen, "light_cone_y_offset", 5),
		list(/obj/item/pen, "bubble_icon", "robot"),
		list(/obj/item/pen, "throwpass", 1),
		list(/obj/item/pen, "emp_integrity_factor", 2),
		list(/obj/item/pen, "emp_protection_flags", EMP_PROTECT_SELF),
		list(/obj/item/pen, "conflict_id", "crusher"),
		list(/obj/item/pen, "light_system", OVERLAY_LIGHT),
		list(/obj/item/pen, "actions_types", list()),
		list(/obj/item/pen, "sprite_sheets_obj", list()),
		list(/obj/machinery/light_switch, "maintenance_flags", MACHINE_MAINT_STANDARD),
		list(/obj/machinery/light_switch, "heat_dissipation", 12),
		list(/mob/living/carbon/human, "use_modern_ai", TRUE),
		list(/mob/living/carbon/human, "has_huds", FALSE),
		list(/mob/living/carbon/human, "max_nutrition", 99),
		list(/mob/living/carbon/human, "fire_reaction", FIRE_REACTION_IGNITE),
		list(/mob/living/carbon/human, "fire_trigger_verb", "burst"),
		list(/mob/living/carbon/human, "fire_heats_body", TRUE),
		list(/mob/living/carbon/human, "force_max_speed", 1),
		list(/mob/living/carbon/human, "adminbus_trash", TRUE),
		list(/mob/living/carbon/human, "parasitic", TRUE),
		list(/mob/living/carbon/human, "appendage_color", "#112233"),
		list(/mob/living/carbon/human, "vore_shred_time", 5 SECONDS),
		list(/mob/living/carbon/human, "composition_reagent", "water"),
		list(/mob/living/carbon/human, "low_sorting_priority", TRUE),
		list(/mob/living/carbon/human, "universal_understand", 1),
		list(/mob/living/carbon/human, "forced_psay", TRUE),
		list(/mob/living/carbon/human, "vent_crawl_time", 1 SECONDS),
		list(/mob/living/carbon/human, "meat_amount", 4),
		list(/mob/living/carbon/human, "butchery_loot", list()),
		list(/mob/living/carbon/human, "footstep_volume", 0.5),
		list(/mob/living/carbon/human, "footstep_e_range", -2),
	)
	return rows

/// Each var is gone from the base type, and View Variables lists it (a slot as `@slot.name`, a trait var as `@kind.field`) set or not.
/datum/unit_test/dq_base_vars_wave3_listed

/datum/unit_test/dq_base_vars_wave3_listed/Run()
	var/turf/T = dq_containment_floor()
	for(var/list/row as anything in dq_wave3_slot_rows())
		var/datum/holder = allocate(row[1] == /mob ? /mob/living/carbon/human : row[1], T)
		TEST_ASSERT(!(row[2] in holder.vars), "[row[2]] is no longer a var of [holder.type]")
		TEST_ASSERT((sparse_slot_label(row[2]) in sparse_slots_of(holder)), "[row[2]] is listed as a slot of [holder.type]")
		TEST_ASSERT(isnull(holder.sparse_slots), "listing [row[2]] allocates nothing")
	for(var/list/row as anything in dq_wave3_trait_rows())
		var/datum/holder = allocate(row[1], T)
		TEST_ASSERT(!(row[2] in holder.vars), "[row[2]] is no longer a var of [holder.type]")
		var/list/field = type_trait_field_named(holder, row[2])
		TEST_ASSERT_NOTNULL(field, "[row[2]] names a trait field of [holder.type]")
		TEST_ASSERT((("@[field[1]].[field[2]]") in type_trait_fields_of(holder)), "View Variables lists @[field[1]].[field[2]] for [holder.type]")

/// Every slot reads as the default its var had, is edited by View Variables and mass edit's writer (by label and by bare name), and Restore to Default clears it.
/datum/unit_test/dq_base_vars_wave3_slot_edit

/datum/unit_test/dq_base_vars_wave3_slot_edit/Run()
	var/turf/T = dq_containment_floor()
	for(var/list/row as anything in dq_wave3_slot_rows())
		var/datum/holder = allocate(row[1] == /mob ? /mob/living/carbon/human : row[1], T)
		var/name = row[2]
		var/label = sparse_slot_label(name)
		TEST_ASSERT_EQUAL(_sparse_get(holder, name, row[4]), row[4], "[name] reads as the default its var had")
		TEST_ASSERT(holder.vv_edit_var(label, row[3]), "the VV edit of [name] is accepted")
		TEST_ASSERT_EQUAL(vv_var_value(holder, label), row[3], "[name] reads back what View Variables wrote")
		TEST_ASSERT(vars_write(holder, name, row[3]), "the bare name of [name] is written by vars_write (SDQL, mass edit, traits)")
		TEST_ASSERT(holder.vv_edit_var(label, vv_var_default(holder, label)), "Restore to Default of [name] is accepted")
		TEST_ASSERT_EQUAL(_sparse_get(holder, name, row[4]), row[4], "[name] is back at its default")

/// Every trait var is written by its old name and by `@kind.field`, read back as the editors read it, and Restore to Default gives the type's value.
/datum/unit_test/dq_base_vars_wave3_trait_edit

/datum/unit_test/dq_base_vars_wave3_trait_edit/Run()
	var/turf/T = dq_containment_floor()
	for(var/list/row as anything in dq_wave3_trait_rows())
		var/datum/holder = allocate(row[1], T)
		var/name = row[2]
		var/list/field = type_trait_field_named(holder, name)
		TEST_ASSERT_NOTNULL(field, "[name] names a trait field")
		var/default = vv_var_default(holder, name)
		var/before = vv_var_value(holder, name)
		TEST_ASSERT_EQUAL(before, default, "[name] starts at its type's value")
		TEST_ASSERT(vars_write(holder, name, row[3]), "the old name [name] is written by vars_write")
		TEST_ASSERT_EQUAL(vv_var_value(holder, name), row[3], "[name] reads back what was written")
		TEST_ASSERT_EQUAL(type_trait_of(holder, field[1]).vars[field[2]], row[3], "the holder's own trait carries [name]")
		TEST_ASSERT_EQUAL(type_trait_of_type(holder.type, field[1]).vars[field[2]], default, "and the type's declaration is untouched")
		var/label = "@[field[1]].[field[2]]"
		TEST_ASSERT(vars_write(holder, label, default), "the VV name [label] is written too")
		TEST_ASSERT_EQUAL(vv_var_value(holder, label), default, "and Restore to Default puts [name] back")

/// SDQL reads and updates a slot and a trait var by their old var names.
/datum/unit_test/dq_base_vars_wave3_sdql

/datum/unit_test/dq_base_vars_wave3_sdql/Run()
	test_driver_begin()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/dq_sparse_probe/H = allocate(/mob/living/carbon/human/dq_sparse_probe, test_floor())
	sparse_set(H, lying_prev, 7)
	vars_write(H, "meat_amount", 6)
	var/datum/SDQL2_query/defaults = allocate(/datum/SDQL2_query, list())
	var/datum/SDQL_parser/read_parser = allocate(/datum/SDQL_parser, SDQL2_tokenize("SELECT /mob/living/carbon/human/dq_sparse_probe", actor))
	var/list/read_tree = read_parser.parse(actor)
	var/datum/SDQL2_query/reader = allocate(/datum/SDQL2_query, read_tree, FALSE, TRUE, defaults.options, FALSE, actor)
	TEST_ASSERT_EQUAL(reader.SDQL_expression(H, list("lying_prev")), 7, "SDQL reads a wave 3 slot by its old var name")
	TEST_ASSERT_EQUAL(reader.SDQL_expression(H, list("meat_amount")), 6, "SDQL reads a wave 3 trait var by its old var name")
	var/datum/SDQL_parser/parser = allocate(/datum/SDQL_parser, SDQL2_tokenize("UPDATE /mob/living/carbon/human/dq_sparse_probe SET max_nutrition = 55", actor))
	var/list/tree = parser.parse(actor)
	TEST_ASSERT(!parser.error, "the real parser accepts an update that names a slot and a trait var")
	var/datum/SDQL2_query/query = allocate(/datum/SDQL2_query, tree, FALSE, TRUE, defaults.options, FALSE, actor)
	query.admin_run(actor)
	TEST_ASSERT(run_until(CALLBACK(src, PROC_REF(query_finished), query)), "the update query finishes")
	TEST_ASSERT_EQUAL(sparse_get(H, lying_prev), 7, "the slot is as it was")
	TEST_ASSERT_EQUAL(living_rules_of(H).max_nutrition, 55, "and the trait var")

/datum/unit_test/dq_base_vars_wave3_sdql/proc/query_finished(datum/SDQL2_query/query)
	return !QDELETED(query) && query.finished

/// The behaviour the vars carried: a type's declared value is read by an instance, a write is the instance's own, and the slots read the old defaults.
/datum/unit_test/dq_base_vars_wave3_behaviour

/datum/unit_test/dq_base_vars_wave3_behaviour/Run()
	var/turf/T = dq_containment_floor()
	var/obj/structure/bed/chair/office/chair = allocate(/obj/structure/bed/chair/office, T)
	var/obj/structure/bed/chair/office/other = allocate(/obj/structure/bed/chair/office, T)
	TEST_ASSERT_EQUAL(buckle_of(chair).movable, 1, "an office chair lets its rider move")
	chair.set_buckle_movable(0)
	TEST_ASSERT_EQUAL(buckle_of(chair).movable, 0, "a write is that chair's own")
	TEST_ASSERT_EQUAL(buckle_of(other).movable, 1, "and no other's")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_EQUAL(living_rules_of(H).has_huds, TRUE, "a human has HUDs")
	TEST_ASSERT_EQUAL(living_rules_of(H).vore_shred_time, 10 SECONDS, "a human shreds in 10 seconds")
	TEST_ASSERT_EQUAL(living_rules_of_type(/mob/living/simple_mob).vore_shred_time, 45 SECONDS, "anything else in 45")
	TEST_ASSERT_EQUAL(butchery_of_type(/mob/living/simple_mob/animal).butchery_loot[/obj/item/stack/animalhide], 3, "an animal gives three hides")
	TEST_ASSERT_EQUAL(sparse_get_or(H, wants_to_see_motion_echos, TRUE), TRUE, "a mob sees motion echos until it says otherwise")
	H.toggle_motion_echo_vis()
	TEST_ASSERT_EQUAL(sparse_get_or(H, wants_to_see_motion_echos, TRUE), FALSE, "the verb turns them off")

#endif
