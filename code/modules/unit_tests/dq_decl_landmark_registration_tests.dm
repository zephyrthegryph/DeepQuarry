/// A real moving spawn landmark joins conditionally and leaves when deleted.
/obj/effect/landmark/dq_decl_latejoin
	name = "JoinLate"
	delete_me = TRUE

/obj/effect/landmark/dq_decl_other
	name = "ordinary test landmark"
	delete_me = TRUE

/datum/unit_test/dq_decl_landmark_registration/Run()
	var/turf/T = test_floor()
	var/obj/effect/landmark/dq_decl_latejoin/L = allocate(/obj/effect/landmark/dq_decl_latejoin, T)
	var/obj/effect/landmark/dq_decl_other/O = allocate(/obj/effect/landmark/dq_decl_other, T)
	TEST_ASSERT(L in REGISTRY_MEMBERS(REGISTRY_LATEJOIN), "a real JoinLate marker is a moving spawn point")
	TEST_ASSERT(L in registry_all(REGISTRY_LATEJOIN), "the declared registry indexes the moving marker")
	TEST_ASSERT(L.simulated, "the moving spawn marker keeps its instance configuration")
	TEST_ASSERT(!(O in REGISTRY_MEMBERS(REGISTRY_LATEJOIN)), "an ordinary marker never becomes a spawn point")
	set_var(L, nameof(L.name), "renamed spawn")
	set_var(O, nameof(O.name), "JoinLate")
	TEST_ASSERT(L in registry_all(REGISTRY_LATEJOIN), "renaming does not undo initial membership")
	TEST_ASSERT(!(O in registry_all(REGISTRY_LATEJOIN)), "renaming does not rerun an init-only membership condition")
	qdel(L)
	TEST_ASSERT(QDELETED(L), "the deletable fixture actually ended")
	TEST_ASSERT(!(L in REGISTRY_MEMBERS(REGISTRY_LATEJOIN)), "deleted spawn markers leave the member list")
	TEST_ASSERT(!(L in registry_all(REGISTRY_LATEJOIN)), "deleted spawn markers leave the declared index")
