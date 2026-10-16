// Real mapload contexts preserve persistence eligibility, including negative config cases.
/datum/unit_test/dq_init_objects_persistent_filth

/datum/unit_test/dq_init_objects_persistent_filth/proc/prepare_persistence()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/area/A = get_area(T)
	set_var(A, nameof(A.flags), A.flags & ~AREA_FLAG_IS_NOT_PERSISTENT)
	set_var(using_map, nameof(using_map.persist_levels), list(T.z))
	set_var(SSpersistence, nameof(SSpersistence.tracking_values), list())
	set_config(/datum/config_entry/flag/persistence_disabled, FALSE)
	set_config(/datum/config_entry/flag/persistence_ignore_mapload, TRUE)
	return T

/datum/unit_test/dq_init_objects_persistent_filth/proc/map_pair(turf/T)
	var/list/made = list()
	SSatoms.map_loader_begin("dq_persistent_filth_test")
	made += new /obj/effect/decal/cleanable/ash(T)
	made += new /obj/item/trash/raisins(T)
	SSatoms.map_loader_stop("dq_persistent_filth_test")
	for(var/atom/A as anything in made)
		own(A)
	SSatoms.InitializeAtoms(made.Copy())
	return made

/datum/unit_test/dq_init_objects_persistent_filth/Run()
	var/turf/T = prepare_persistence()
	var/obj/effect/decal/cleanable/ash/A = allocate(/obj/effect/decal/cleanable/ash, T)
	var/obj/item/trash/raisins/R = allocate(/obj/item/trash/raisins, T)
	TEST_ASSERT(A in SSpersistence.tracking_values[/datum/persistent/filth], "actual runtime filth is tracked even when mapload filth is ignored")
	TEST_ASSERT(R in SSpersistence.tracking_values[/datum/persistent/filth/trash], "actual runtime trash uses the trash persistence category")
	var/list/mapped = map_pair(T)
	TEST_ASSERT(!(mapped[1] in SSpersistence.tracking_values[/datum/persistent/filth]), "actual mapped filth respects ignore_mapload")
	TEST_ASSERT(!(mapped[2] in SSpersistence.tracking_values[/datum/persistent/filth/trash]), "actual mapped trash respects ignore_mapload")
	qdel(A)
	TEST_ASSERT(!(A in SSpersistence.tracking_values[/datum/persistent/filth]), "real filth destruction still forgets its persistence membership")

/datum/unit_test/dq_init_objects_persistent_filth/map_and_disabled

/datum/unit_test/dq_init_objects_persistent_filth/map_and_disabled/Run()
	var/turf/T = prepare_persistence()
	set_config(/datum/config_entry/flag/persistence_ignore_mapload, FALSE)
	var/list/mapped = map_pair(T)
	TEST_ASSERT(mapped[1] in SSpersistence.tracking_values[/datum/persistent/filth], "the real mapload context tracks filth when configured to keep it")
	TEST_ASSERT(mapped[2] in SSpersistence.tracking_values[/datum/persistent/filth/trash], "the real mapload context tracks trash when configured to keep it")
	set_config(/datum/config_entry/flag/persistence_disabled, TRUE)
	var/obj/effect/decal/cleanable/ash/A = allocate(/obj/effect/decal/cleanable/ash, T)
	var/obj/item/trash/raisins/R = allocate(/obj/item/trash/raisins, T)
	TEST_ASSERT(!(A in SSpersistence.tracking_values[/datum/persistent/filth]), "disabled persistence refuses actual runtime filth")
	TEST_ASSERT(!(R in SSpersistence.tracking_values[/datum/persistent/filth/trash]), "disabled persistence refuses actual runtime trash")
