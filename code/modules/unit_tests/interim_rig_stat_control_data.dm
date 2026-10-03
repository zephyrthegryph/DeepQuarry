/// Real rig-module initialization creates correctly labeled and linked selection controls.
/datum/unit_test/interim_rig_stat_control_data/Run()
	var/obj/item/rig_module/module = allocate(/obj/item/rig_module)
	var/atom/movable/stat_rig_module/select/select_control
	var/atom/movable/stat_rig_module/charge/charge_control
	for(var/atom/movable/stat_rig_module/control as anything in module.stat_modules)
		if(istype(control, /atom/movable/stat_rig_module/select))
			select_control = control
		if(istype(control, /atom/movable/stat_rig_module/charge))
			charge_control = control
	TEST_ASSERT(select_control && charge_control, "actual module initialization creates both real owned stat controls")
	TEST_ASSERT_EQUAL(select_control.name, "Select", "actual selection control retains its initialized label")
	TEST_ASSERT_EQUAL(select_control.module_mode, "select", "actual selection control retains its click dispatch mode")
	TEST_ASSERT_EQUAL(charge_control.name, "Change Charge", "actual charge control retains its initialized label")
	TEST_ASSERT_EQUAL(charge_control.module_mode, "select_charge_type", "actual charge control retains its click dispatch mode")
	TEST_ASSERT_EQUAL(select_control.module, module, "actual selection control links the exact owning module")
	TEST_ASSERT_EQUAL(charge_control.module, module, "actual charge control links the exact owning module")
	TEST_ASSERT_EQUAL(select_control.CanUse(), 0, "the actual nonselectable base module refuses selection")
	TEST_ASSERT_EQUAL(charge_control.CanUse(), 0, "the actual uncharged base module refuses charge switching")

/// Real chemical charges keep their dynamic label and next-charge hyperlink behavior.
/datum/unit_test/interim_rig_stat_charge_data/Run()
	var/obj/item/rig_module/chem_dispenser/module = allocate(/obj/item/rig_module/chem_dispenser)
	var/atom/movable/stat_rig_module/charge/control
	for(var/atom/movable/stat_rig_module/entry as anything in module.stat_modules)
		if(istype(entry, /atom/movable/stat_rig_module/charge))
			control = entry
	TEST_ASSERT(control, "the actual chemical dispenser initializes its real owned charge control")
	TEST_ASSERT_EQUAL(control.name, "Change Charge", "the actual control starts with its unchanged initial label")
	TEST_ASSERT_EQUAL(module.charge_selected, REAGENT_ID_TRICORDRAZINE, "actual chemical initialization selects its first declared charge")
	TEST_ASSERT_EQUAL(length(module.charges), 8, "the actual chemical dispenser initializes every real charge datum")
	TEST_ASSERT_EQUAL(control.CanUse(), 1, "the actual populated chemical dispenser permits charge switching")
	var/datum/rig_charge/selected = module.charges[module.charge_selected]
	TEST_ASSERT_EQUAL(selected.charges, 80, "the actual selected chemical charge retains its declared quantity")
	TEST_ASSERT_EQUAL(control.name, "[selected.display_name] (80C) - Change", "the actual control keeps its real dynamic quantity label")
	var/list/hrefs = list()
	control.AddHref(hrefs)
	TEST_ASSERT_EQUAL(hrefs["charge_type"], REAGENT_ID_TRAMADOL, "the actual charge control links to the next real declared charge")
	TEST_ASSERT_EQUAL(module.charge_selected, REAGENT_ID_TRICORDRAZINE, "building the real hyperlink does not change the selected chemical")
