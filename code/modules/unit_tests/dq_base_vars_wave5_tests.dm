// base_vars wave 5: rare mob and item state that left /mob, /mob/living, /human and /obj/item for sparse slots.
// Each is gone as a var, reads as the default the var had, and is reached by View Variables by its slot label.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Every slot of this wave: list(owner type, slot name, a value to set, the default it reads as).
/proc/dq_wave5_slot_rows()
	var/static/list/rows = list(
		list(/mob, "facing_dir", NORTH, null),
		list(/mob, "lastKnownIP", "127.0.0.1", null),
		list(/mob, "skincmds", list(), null),
		list(/mob/living, "custom_link", "example.org", null),
		list(/mob/living, "eggs", 3, 0),
		list(/mob/living, "failed_last_breath", 1, 0),
		list(/mob/living, "summoned", TRUE, null),
		list(/mob/living/carbon/human, "heartbeat", 2, 0),
		list(/obj/item/pen, "user_vars_to_edit", list("name" = "x"), null),
		list(/obj/item/pen, "user_vars_remembered", list("name" = "y"), null),
	)
	return rows

/datum/unit_test/dq_base_vars_wave5_slots

/datum/unit_test/dq_base_vars_wave5_slots/Run()
	var/turf/T = dq_containment_floor()
	for(var/list/row as anything in dq_wave5_slot_rows())
		var/datum/holder = allocate(row[1] == /mob || row[1] == /mob/living ? /mob/living/carbon/human : row[1], T)
		var/name = row[2]
		var/label = sparse_slot_label(name)
		TEST_ASSERT(!(name in holder.vars), "[name] is no longer a var of [holder.type]")
		TEST_ASSERT((label in sparse_slots_of(holder)), "[name] is listed as a slot of [holder.type]")
		TEST_ASSERT_EQUAL(_sparse_get(holder, name, row[4]), row[4], "[name] reads as the default its var had")
		TEST_ASSERT(holder.vv_edit_var(label, row[3]), "the VV edit of [name] is accepted")
		TEST_ASSERT_EQUAL(vv_var_value(holder, label), row[3], "[name] reads back what View Variables wrote")

/// The worn-item var edit round trip: equipping applies the edits, dropping puts the originals back.
/datum/unit_test/dq_base_vars_wave5_item_edits

/datum/unit_test/dq_base_vars_wave5_item_edits/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/original = H.real_name
	sparse_set(pen, user_vars_to_edit, list("real_name" = "Wave Five"))
	pen.item_restore_user_vars(H)
	TEST_ASSERT_EQUAL(H.real_name, original, "restoring with nothing remembered changes nothing")
	sparse_set(pen, user_vars_remembered, list("real_name" = original))
	H.vv_edit_var("real_name", "Wave Five")
	pen.item_restore_user_vars(H)
	TEST_ASSERT_EQUAL(H.real_name, original, "a remembered var still holding the edited value is restored")
	TEST_ASSERT_NULL(sparse_get(pen, user_vars_remembered), "the remembered list is cleared")

#endif
