#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/datum/roller/dq_rifle_branch
	var/pick_standard

/datum/roller/dq_rifle_branch/chance(percent)
	return pick_standard

/obj/structure/closet/secure_closet/guncabinet/rifle/dq_parity
	abstract_type = /obj/structure/closet/secure_closet/guncabinet/rifle/dq_parity
	var/branch_standard = TRUE

/obj/structure/closet/secure_closet/guncabinet/rifle/dq_parity/lever
	abstract_type = /obj/structure/closet/secure_closet/guncabinet/rifle/dq_parity/lever
	branch_standard = FALSE

/obj/structure/closet/secure_closet/guncabinet/rifle/dq_parity/roll_starts_with(datum/roller/R)
	var/datum/roller/dq_rifle_branch/controlled = new("rifle parity")
	controlled.pick_standard = branch_standard
	. = ..(controlled)
	qdel(controlled)

/datum/unit_test/dq_rifle_starting_list_parity/Run()
	dq_look_scope_globals()
	var/turf/T = test_floor()
	for(var/type in list(/obj/structure/closet/secure_closet/guncabinet/rifle/dq_parity, /obj/structure/closet/secure_closet/guncabinet/rifle/dq_parity/lever))
		dq_look_reset(T)
		var/obj/structure/closet/secure_closet/guncabinet/rifle/dq_parity/C = allocate(type, T)
		var/standard = C.branch_standard
		var/list/old = list(/obj/item/ammo_magazine/clip/c762/hunter = 9, /obj/item/gun/projectile/shotgun/pump/rifle = 2)
		if(standard)
			old += /obj/item/gun/projectile/shotgun/pump/rifle
		else
			old += /obj/item/gun/projectile/shotgun/pump/rifle/lever
		var/list/old_counts = list()
		// This is the real old latent-generator consumer, including repeated
		// associative keys and dq_latent_spawn_count's count/variant semantics.
		for(var/path in old)
			old_counts[path] += dq_latent_spawn_count(old[path])
		dq_look_settle()
		var/list/native_counts = list()
		// Observe actual constructor entries and the real ledger/latent contents,
		// rather than recreating contains_roll in a mock normalization loop.
		for(var/path in C.slot_kinds(CONTAINER_SLOT_INTERIOR, /obj/item/gun))
			native_counts[path]++
		// Materialize and delete all custody before asserting, so a mismatch
		// cannot spill real guns or leave their power/periodic entries alive.
		C.latent_materialize_all(CONTAINER_SLOT_INTERIOR)
		for(var/atom/movable/child as anything in C.slot_contents())
			qdel(child)
		qdel(C)
		dq_look_reset(T)
		TEST_ASSERT_EQUAL(native_counts[/obj/item/gun/projectile/shotgun/pump/rifle], old_counts[/obj/item/gun/projectile/shotgun/pump/rifle], "Real native contents preserve legacy standard rifles for branch[standard]")
		TEST_ASSERT_EQUAL(native_counts[/obj/item/gun/projectile/shotgun/pump/rifle/lever], old_counts[/obj/item/gun/projectile/shotgun/pump/rifle/lever], "Real native contents preserve legacy lever rifles for branch[standard]")
#endif
