// Saved type paths (code/content/variants/variant_alias.dm, code/content/persistence/): a save made when a family was one type per row names
// the old path; it reads back as the parent with the row's key, and what is saved now reads back the same way.

#define DQ_SAVED_SIGN_OLD_PATH "/obj/structure/sign/department/medbay"

/datum/unit_test/dq_saved_type_reads_old_paths

/datum/unit_test/dq_saved_type_reads_old_paths/Run()
	TEST_ASSERT_EQUAL(saved_type("/obj/item/pen"), /obj/item/pen, "a path that exists reads as itself")
	var/old = saved_type(DQ_SAVED_SIGN_OLD_PATH)
	TEST_ASSERT(istext(old), "the old path of a collapsed type reads as a reference")
	TEST_ASSERT_EQUAL(saved_type_path(old), /obj/structure/sign/department, "the reference names the parent")
	TEST_ASSERT_EQUAL(variant_key(old), "medbay", "and the row")
	TEST_ASSERT_EQUAL(saved_type_path(old), /obj/structure/sign/department, "saved_type_path() is the parent")
	TEST_ASSERT_EQUAL(saved_type(old), old, "a reference passes through")
	TEST_ASSERT_NULL(saved_type("/obj/no/such/thing"), "a path that names nothing reads as null")
	TEST_ASSERT_NULL(saved_type(null), "no value, no type")

/datum/unit_test/dq_saved_type_round_trips

/datum/unit_test/dq_saved_type_round_trips/Run()
	var/turf/T = dq_containment_floor()
	var/obj/structure/sign/sign = variant_new(VARIANT(/obj/structure/sign/department/medbay), T)
	TEST_ASSERT_EQUAL(saved_type_text(sign), DQ_SAVED_SIGN_OLD_PATH, "a variant is saved under its old path")
	var/list/back = saved_type(saved_type_text(sign))
	TEST_ASSERT(istext(back), "and the save reads back as a reference")
	TEST_ASSERT_EQUAL(saved_type_path(back), sign.type, "to the same parent")
	TEST_ASSERT_EQUAL(variant_key(back), sign.variant, "and row")
	qdel(sign)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT_EQUAL(saved_type_text(pen), "/obj/item/pen", "a thing with no variant is saved under its path")

/datum/unit_test/dq_persistence_loads_old_paths

/datum/unit_test/dq_persistence_loads_old_paths/Run()
	// A storage save (smartfridge stock, container contents) that names an old path and a live one.
	var/datum/persistent/storage/P = new
	var/list/made = P.generate_items(list(DQ_SAVED_SIGN_OLD_PATH = 2, "/obj/item/pen" = 1))
	TEST_ASSERT_EQUAL(length(made), 3, "every saved item was made")
	var/signs = 0
	var/pens = 0
	for(var/atom/A as anything in made)
		if(istype(A, /obj/structure/sign/department))
			signs++
			TEST_ASSERT_EQUAL(A.name, "MEDBAY", "the old path's item has its row's name")
		else if(istype(A, /obj/item/pen))
			pens++
		qdel(A)
	TEST_ASSERT_EQUAL(signs, 2, "both signs were made")
	TEST_ASSERT_EQUAL(pens, 1, "the live path still works")
	qdel(P, TRUE)

	// A filth/trash save: the token's path becomes the parent and the row's key.
	var/datum/persistent/filth/F = new
	var/list/token = list("x" = 1, "y" = 1, "z" = 1, "age" = 0, "dirt" = 1, "pixel_x" = 0, "pixel_y" = 0, "path" = DQ_SAVED_SIGN_OLD_PATH)
	TEST_ASSERT(F.CheckTokenSanity(token), "a token with an old path is sane")
	TEST_ASSERT_EQUAL(token["path"], /obj/structure/sign/department, "its path is the parent")
	TEST_ASSERT_EQUAL(token["variant"], "medbay", "and it carries the row's key")
	var/list/live = list("x" = 1, "y" = 1, "z" = 1, "age" = 0, "dirt" = 1, "pixel_x" = 0, "pixel_y" = 0, "path" = "/obj/effect/decal/cleanable/blood")
	TEST_ASSERT(F.CheckTokenSanity(live), "a token with a live path is sane")
	TEST_ASSERT_EQUAL(live["path"], /obj/effect/decal/cleanable/blood, "its path is read as before")
	TEST_ASSERT_NULL(live["variant"], "with no key")
	var/list/bad = list("x" = 1, "y" = 1, "z" = 1, "age" = 0, "dirt" = 1, "pixel_x" = 0, "pixel_y" = 0, "path" = "/obj/no/such/thing")
	TEST_ASSERT(!F.CheckTokenSanity(bad), "a token whose path names nothing is refused")
	qdel(F, TRUE)

#undef DQ_SAVED_SIGN_OLD_PATH
