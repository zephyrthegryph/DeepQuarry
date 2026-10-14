// Initial evaluation is silent until map load completes, then one settling drain (doc/rewrite/final_api.html section 7, section 6 step 7;
// stat_drain_point() and SSatoms.initialize_atoms_finish()).

/// A lamp with an on_change hook on a tracked var. `light_on_init` makes its own init write the var after ..(): a change the hook is owed.
/obj/dq_settle_lamp
	name = "settle lamp"
	var/lit = FALSE
	var/light_on_init = FALSE
	var/hook_runs = 0
	/// What the hook saw: was the map load still open when it ran?
	var/ran_during_load = FALSE

TRACKED(/obj/dq_settle_lamp, lit)

CAPABILITIES(/obj/dq_settle_lamp)
	on_change(nameof(lit), ENTER, then(PROC_REF(on_lit)))

/obj/dq_settle_lamp/Initialize(mapload)
	. = ..()
	if(light_on_init)
		set_lit(TRUE)
		stat_drain_point() // a kernel drain arriving mid-load (a chunked load yields between steps): it must wait for the load

/obj/dq_settle_lamp/proc/on_lit(datum/act/A)
	hook_runs++
	if(SSatoms.map_loading())
		ran_during_load = TRUE

/// Starts lit: the value its init sets is the baseline, so nothing is owed.
/obj/dq_settle_lamp/prelit
	lit = TRUE

/obj/dq_settle_lamp/switched
	light_on_init = TRUE

/datum/unit_test/dq_init_settle

/datum/unit_test/dq_init_settle/Run()
	var/list/made = list()
	SSatoms.map_loader_begin("dq_init_settle")
	for(var/i in 1 to 3)
		made += new /obj/dq_settle_lamp/switched(dq_containment_floor())
	made += new /obj/dq_settle_lamp/prelit(dq_containment_floor())
	SSatoms.map_loader_stop("dq_init_settle")
	for(var/obj/dq_settle_lamp/lamp as anything in made)
		own(lamp)
	SSatoms.InitializeAtoms(made.Copy())
	TEST_ASSERT(!SSatoms.map_loading(), "the load frame closed")
	for(var/obj/dq_settle_lamp/switched/lamp in made)
		TEST_ASSERT_EQUAL(lamp.hook_runs, 1, "the settling drain ran the hook its init owed, once")
		TEST_ASSERT(!lamp.ran_during_load, "no hook ran while the map loaded")
	for(var/obj/dq_settle_lamp/prelit/lamp in made)
		TEST_ASSERT_EQUAL(lamp.hook_runs, 0, "a value set at init is the baseline: initial evaluation publishes nothing")
	// Outside a load the drain runs at once.
	var/obj/dq_settle_lamp/runtime = allocate(/obj/dq_settle_lamp, dq_containment_floor())
	runtime.set_lit(TRUE)
	stat_drain_point()
	TEST_ASSERT_EQUAL(runtime.hook_runs, 1, "after the load, a drain point runs the hook")
