// Vessel leaching (code/content/reagents/vessel_leaching.dm): harsh or hot contents take up a trace of the vessel's own material; borosilicate gives up nothing.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A beaker built entirely of `material_id` (every part of it), holding `amount` units of `reagent_id`, at `celsius`.
/datum/unit_test/proc/dq_leach_vessel(material_id, reagent_id, amount, celsius)
	var/obj/item/reagent_containers/glass/beaker/vessel = allocate(/obj/item/reagent_containers/glass/beaker, test_floor())
	if(material_id)
		vessel.apply_material_construction(list(MATERIAL_ROLE_STRUCTURE = material_id, MATERIAL_ROLE_LINER = material_id), material_template_path_for_application(MATERIAL_APPLICATION_CONTAINER), 500)
	vessel.reagents.add_reagent(reagent_id, amount, safety = 1)
	var/list/properties = vessel.thermal_properties()
	vessel.add_heat((T0C + celsius - vessel.get_temperature()) * properties[THERMAL_CAPACITY])
	return vessel

/datum/unit_test/dq_vessel_leach_hot_acid_in_steel_gains_metal

/datum/unit_test/dq_vessel_leach_hot_acid_in_steel_gains_metal/Run()
	var/obj/item/reagent_containers/glass/beaker/vessel = dq_leach_vessel(MAT_STEEL, REAGENT_ID_SACID, 30, 90)
	TEST_ASSERT(!vessel.reagents.has_reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL), "nothing leached before a step")
	vessel.vessel_leach(1)
	TEST_ASSERT(vessel.reagents.has_reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL), "hot acid in a steel vessel takes up the heavy-metal contaminant")

/datum/unit_test/dq_vessel_leach_borosilicate_gives_nothing

/datum/unit_test/dq_vessel_leach_borosilicate_gives_nothing/Run()
	var/obj/item/reagent_containers/glass/beaker/vessel = dq_leach_vessel(MAT_PGLASS, REAGENT_ID_SACID, 30, 200)
	vessel.vessel_leach(5)
	TEST_ASSERT_EQUAL(vessel.reagents.contaminant_volume(), 0, "borosilicate leaches nothing, even into hot acid")
	vessel = dq_leach_vessel(MAT_PGLASS, REAGENT_ID_LYE, 30, 200)
	vessel.vessel_leach(5)
	TEST_ASSERT_EQUAL(vessel.reagents.contaminant_volume(), 0, "borosilicate leaches nothing into hot lye either")

/datum/unit_test/dq_vessel_leach_plastic_gives_plasticiser

/datum/unit_test/dq_vessel_leach_plastic_gives_plasticiser/Run()
	var/obj/item/reagent_containers/glass/beaker/vessel = dq_leach_vessel(MAT_PLASTIC, REAGENT_ID_SACID, 30, 20)
	vessel.vessel_leach(1)
	TEST_ASSERT(vessel.reagents.has_reagent(REAGENT_ID_CONTAMINANT_PLASTICISER), "a strong acid in a plastic vessel takes up plasticiser")

/datum/unit_test/dq_vessel_leach_mild_glass_gives_nothing

/datum/unit_test/dq_vessel_leach_mild_glass_gives_nothing/Run()
	var/obj/item/reagent_containers/glass/beaker/vessel = dq_leach_vessel(null, REAGENT_ID_WATER, 30, 20)
	vessel.vessel_leach(10)
	TEST_ASSERT_EQUAL(vessel.reagents.contaminant_volume(), 0, "water at room temperature leaches nothing from glass")
	vessel = dq_leach_vessel(null, REAGENT_ID_SACID, 30, 90)
	vessel.vessel_leach(10)
	TEST_ASSERT_EQUAL(vessel.reagents.contaminant_volume(), 0, "ordinary glass stands up to a hot acid")
	vessel = dq_leach_vessel(null, REAGENT_ID_LYE, 30, 20)
	vessel.vessel_leach(1)
	TEST_ASSERT(vessel.reagents.contaminant_volume() > 0, "a strong base takes a silicate trace from ordinary glass")
	vessel = dq_leach_vessel(null, REAGENT_ID_WATER, 30, 200)
	vessel.vessel_leach(1)
	TEST_ASSERT(vessel.reagents.contaminant_volume() > 0, "very hot contents take a silicate trace from ordinary glass")

/datum/unit_test/dq_vessel_leach_examine_names_material

/datum/unit_test/dq_vessel_leach_examine_names_material/Run()
	var/obj/item/reagent_containers/glass/beaker/vessel = dq_leach_vessel(MAT_PGLASS, REAGENT_ID_WATER, 10, 20)
	TEST_ASSERT(findtext(vessel.vessel_description(), "nothing leaches"), "a borosilicate beaker says nothing leaches from it")
	vessel = dq_leach_vessel(MAT_STEEL, REAGENT_ID_WATER, 10, 20)
	TEST_ASSERT(findtext(vessel.vessel_description(), "steel"), "a steel beaker names its material")

/// The beaker designs print in glass, borosilicate, steel or plastic, and every choice costs at least what the product recycles into.
/datum/unit_test/dq_vessel_beaker_designs_conserve_every_material

/datum/unit_test/dq_vessel_beaker_designs_conserve_every_material/Run()
	for(var/design_id in list("beaker", "large_beaker"))
		var/datum/design_techweb/D = SSresearch.techweb_designs[design_id]
		TEST_ASSERT(D?.material_template, "[design_id] is a material-selectable design")
		for(var/material_id in list(MAT_GLASS, MAT_PGLASS, MAT_STEEL, MAT_PLASTIC))
			var/list/choices = list(MATERIAL_ROLE_STRUCTURE = material_id, MATERIAL_ROLE_LINER = material_id)
			TEST_ASSERT(D.material_choice_valid(choices), "[design_id] accepts [material_id]")
			var/list/needed = list()
			var/list/source = D.effective_materials(choices)
			for(var/key in source)
				var/datum/material/M = istype(key, /datum/material) ? key : get_material_by_name(key)
				if(istype(M))
					needed[M] += source[key]
			var/obj/item/reagent_containers/glass/beaker/made = D.create_item(null, choices)
			TEST_ASSERT(made, "[design_id] prints in [material_id]")
			split_materials_uniformly(needed, 1, made) // records the cost as a mix, as the lathe does
			var/list/excess = dq_fab_excess(dq_fab_basic(needed), dq_fab_recovered(made), dq_fab_part_count(made))
			TEST_ASSERT(!length(excess), "[design_id] in [material_id] recycles into no more than it costs: [jointext(excess, "; ")]")
			TEST_ASSERT_EQUAL(made.vessel_material()?.name, material_id, "the printed [design_id] is a vessel of [material_id]")
			qdel(made)

#endif
