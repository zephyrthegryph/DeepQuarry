// Relations wave 0 (doc/rewrite/proposals/relations.md D1, D3, D14, D17): an undeclared write is reported, vars_write goes through the
// relation verbs, a link end cannot also be another declaration, and a thing that survives its container is spilled, not deleted.

/// A holder with a var no declaration names (the write below is by a dynamic name, so the rel_write_undeclared lint does not see it).
/datum/relations_stray_holder
	var/datum/stray
	var/datum/declared

CAPABILITIES(/datum/relations_stray_holder)
	ref_one(nameof(declared))

/datum/unit_test/relations_undeclared_write_reported

/datum/unit_test/relations_undeclared_write_reported/Run()
	var/list/capture = list()
	set_global("dq_lifecycle_report_capture", capture)
	var/datum/relations_stray_holder/H = new
	var/datum/relations_stray_holder/other = new
	rel_set(H, "declared", other)
	TEST_ASSERT_EQUAL(H.declared, other, "a declared var is written")
	TEST_ASSERT(!length(capture), "a declared write reports nothing: [json_encode(capture)]")
	rel_set(H, "stray", other)
	set_global("dq_lifecycle_report_capture", null)
	TEST_ASSERT(length(capture) == 1 && findtext(capture[1], "not declared"), "an undeclared write is reported, not learned: [json_encode(capture)]")
	var/datum/own_table/T = own_table_of(H)
	TEST_ASSERT(isnull(T.entries["stray"]), "the table learned nothing from the write")
	qdel(H)
	qdel(other)

/datum/unit_test/relations_vars_write_routes_relation

/datum/unit_test/relations_vars_write_routes_relation/Run()
	var/list/reports = list()
	set_global("declare_report_capture", reports)
	var/datum/own_test_holder/H = new
	var/datum/own_test_child/target = new
	TEST_ASSERT(vars_write(H, "view", target), "vars_write writes a declared relation var")
	TEST_ASSERT_EQUAL(H.view, target, "the value is held")
	qdel(target)
	TEST_ASSERT(isnull(H.view), "the write went through the relation: the target's death cleared the view")
	TEST_ASSERT(!vars_write(H, "view", 5), "a number is not an entity")
	TEST_ASSERT(!vars_write(H, "children", 5), "a many takes a list of entities, not a number")
	set_global("declare_report_capture", null)
	TEST_ASSERT_EQUAL(length(reports), 2, "both refusals are reported: [json_encode(reports)]")
	var/datum/own_test_child/first = new
	var/datum/own_test_child/second = new
	TEST_ASSERT(vars_write(H, "children", list(first, second)), "a many is refilled from a list")
	TEST_ASSERT(length(H.children) == 2 && (first in H.children) && (second in H.children), "both members are held")
	TEST_ASSERT_EQUAL(owner_of(first), H, "the owner stamp was written: the write used the verbs")
	TEST_ASSERT(vars_write(H, "children", null), "null empties a many")
	TEST_ASSERT(!length(H.children), "the list is empty")
	qdel(H)

/obj/item/dq_relations_survivor
	name = "survivor"
	w_class = ITEMSIZE_SMALL

/obj/item/dq_relations_survivor/survives_container()
	return TRUE

/datum/unit_test/relations_survives_container_spills

/datum/unit_test/relations_survives_container_spills/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_destroy_transaction_nest_outer/outer = allocate(/obj/item/dq_destroy_transaction_nest_outer, T)
	var/obj/item/dq_relations_survivor/survivor = allocate(/obj/item/dq_relations_survivor, T)
	var/obj/item/dq_containment_test/plain = allocate(/obj/item/dq_containment_test, T)
	TEST_ASSERT(move_into(outer, null, survivor), "the survivor into the deleting slot")
	TEST_ASSERT(move_into(outer, null, plain), "an ordinary item into the same slot")
	qdel(outer)
	TEST_ASSERT(QDELETED(plain), "the DELETE slot deleted the ordinary item")
	TEST_ASSERT(!QDELETED(survivor), "the thing that survives its container was not deleted")
	TEST_ASSERT_EQUAL(survivor.loc, T, "it spilled to where the holder was")

/datum/unit_test/relations_survives_container_defaults

/datum/unit_test/relations_survives_container_defaults/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_containment_test/plain = allocate(/obj/item/dq_containment_test, T)
	TEST_ASSERT(!plain.survives_container(), "an ordinary item does not survive its container")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/dummy, T)
	TEST_ASSERT(!H.survives_container(), "a mob with no mind and no client does not")
	var/obj/item/disk/nuclear/disk = allocate(/obj/item/disk/nuclear, T)
	TEST_ASSERT(disk.survives_container(), "the nuclear disk does")
