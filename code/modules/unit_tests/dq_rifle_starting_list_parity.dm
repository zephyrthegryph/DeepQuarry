#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/datum/roller/dq_rifle_branch
	var/pick_standard

/datum/roller/dq_rifle_branch/chance(percent)
	return pick_standard

/datum/unit_test/dq_rifle_starting_list_parity/Run()
	var/obj/structure/closet/secure_closet/guncabinet/rifle/cabinet = allocate(/obj/structure/closet/secure_closet/guncabinet/rifle)
	for(var/standard in list(FALSE, TRUE))
		var/list/old = list(/obj/item/ammo_magazine/clip/c762/hunter = 9, /obj/item/gun/projectile/shotgun/pump/rifle = 2)
		if(standard)
			old += /obj/item/gun/projectile/shotgun/pump/rifle
		else
			old += /obj/item/gun/projectile/shotgun/pump/rifle/lever
		var/datum/roller/dq_rifle_branch/R = allocate(/datum/roller/dq_rifle_branch)
		R.pick_standard = standard
		var/list/added = cabinet.roll_starts_with(R)
		var/list/native = list(/obj/item/ammo_magazine/clip/c762/hunter = 9, /obj/item/gun/projectile/shotgun/pump/rifle = 2)
		// Actual contains_roll conversion: returned plain type-list items count1.
		for(var/path in added)
			var/n = added[path]
			native[path] += isnum(n) ? n : 1
		var/list/old_counts = list()
		for(var/path in old)
			var/n = old[path]
			old_counts[path] += isnum(n) ? n : 1
		TEST_ASSERT_EQUAL(native[/obj/item/gun/projectile/shotgun/pump/rifle], old_counts[/obj/item/gun/projectile/shotgun/pump/rifle], "Native standard rifle count must match actual legacy += list semantics for branch[standard]")
		TEST_ASSERT_EQUAL(native[/obj/item/gun/projectile/shotgun/pump/rifle/lever], old_counts[/obj/item/gun/projectile/shotgun/pump/rifle/lever], "Native lever rifle count must match actual legacy += list semantics for branch[standard]")
#endif
