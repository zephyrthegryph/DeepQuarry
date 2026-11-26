// per_type(nameof(v), PROC_REF(build), copy_on_write = TRUE) (code/engine/lifeforms/per_type.dm): a starting list shared by every instance of the
// type until the first write, which copies it through the generated mutators (tools/analyze/src/gens/tracked_lists.rs).

/obj/item/dq_cow_probe
	name = "cow probe"
	var/list/words
	var/list/marks

CAPABILITIES(/obj/item/dq_cow_probe)
	per_type(nameof(words), PROC_REF(build_words), copy_on_write = TRUE)
	per_type(nameof(marks), PROC_REF(build_marks), copy_on_write = TRUE)

/obj/item/dq_cow_probe/proc/build_words()
	return list("ire", "ego", "veri")

/obj/item/dq_cow_probe/proc/build_marks()
	return list("a" = 1, "b" = 2)

/// A subtype declaring nothing of its own binds the inherited declaration to a table of its own.
/obj/item/dq_cow_probe/sub

/datum/unit_test/dq_cow_list_shared_until_written

/datum/unit_test/dq_cow_list_shared_until_written/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_cow_probe/A = allocate(/obj/item/dq_cow_probe, T)
	var/obj/item/dq_cow_probe/B = allocate(/obj/item/dq_cow_probe, T)
	var/list/table = per_type_table(/obj/item/dq_cow_probe, "words")
	TEST_ASSERT_NOTNULL(table, "the type built its starting table")
	TEST_ASSERT(A.words == table && B.words == table, "every instance holds the one table until it writes")
	TEST_ASSERT_EQUAL(length(table), 3, "the starting entries")
	var/obj/item/dq_cow_probe/sub/C = allocate(/obj/item/dq_cow_probe/sub, T)
	TEST_ASSERT(C.words != table, "a subtype has its own table")

	TEST_ASSERT(A.add_words("nahlizet"), "a write through the mutator")
	TEST_ASSERT(A.words != table, "the first write gave A its own list")
	TEST_ASSERT_EQUAL(length(A.words), 4, "A has the new entry")
	TEST_ASSERT_EQUAL(length(table), 3, "the shared table did not change")
	TEST_ASSERT(B.words == table && length(B.words) == 3, "B still holds the shared table, unchanged")
	var/list/mine = A.words
	TEST_ASSERT(A.add_words("jatkaa"), "a second write")
	TEST_ASSERT(A.words == mine, "later writes edit A's own list in place, no second copy")

	TEST_ASSERT(B.remove_words("ego"), "B removes an entry")
	TEST_ASSERT(B.words != table, "B copied before removing")
	TEST_ASSERT_EQUAL(length(table), 3, "the table still has all three")
	TEST_ASSERT(!("ego" in B.words) && ("ego" in A.words), "each instance has its own edit")
	var/obj/item/dq_cow_probe/D = allocate(/obj/item/dq_cow_probe, T)
	TEST_ASSERT(D.words == table && ("ego" in D.words), "an instance made after the writes still starts from the table")

/datum/unit_test/dq_cow_list_every_mutator_unshares

/datum/unit_test/dq_cow_list_every_mutator_unshares/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_cow_probe/P = allocate(/obj/item/dq_cow_probe, T)
	var/list/table = per_type_table(/obj/item/dq_cow_probe, "words")
	var/list/before = table.Copy()
	var/obj/item/dq_cow_probe/A = allocate(/obj/item/dq_cow_probe, T)
	TEST_ASSERT(A.include_words("zzz"), "include")
	var/obj/item/dq_cow_probe/B = allocate(/obj/item/dq_cow_probe, T)
	TEST_ASSERT(B.insert_words(1, "first"), "insert")
	var/obj/item/dq_cow_probe/C = allocate(/obj/item/dq_cow_probe, T)
	TEST_ASSERT(C.swap_words(1, 3), "swap")
	var/obj/item/dq_cow_probe/E = allocate(/obj/item/dq_cow_probe, T)
	TEST_ASSERT(E.cut_words(1, 2), "cut")
	var/obj/item/dq_cow_probe/F = allocate(/obj/item/dq_cow_probe, T)
	TEST_ASSERT(F.clear_words(), "clear")
	var/obj/item/dq_cow_probe/G = allocate(/obj/item/dq_cow_probe, T)
	TEST_ASSERT(G.set_words_at(2, "second"), "set an index")
	TEST_ASSERT_EQUAL(length(table), length(before), "no mutator changed the shared table's length")
	for(var/i in 1 to length(before))
		TEST_ASSERT_EQUAL(table[i], before[i], "no mutator changed the shared table's entry [i]")
	TEST_ASSERT(P.words == table, "an untouched instance still holds it")
	var/obj/item/dq_cow_probe/H = allocate(/obj/item/dq_cow_probe, T)
	var/list/marks_table = per_type_table(/obj/item/dq_cow_probe, "marks")
	TEST_ASSERT(H.set_marks_at("a", 9), "an assoc write")
	TEST_ASSERT_EQUAL(marks_table["a"], 1, "the shared assoc table is unchanged")
	TEST_ASSERT_EQUAL(H.marks["a"], 9, "the instance sees its own value")

/datum/unit_test/dq_cow_list_publishes_changes

/datum/unit_test/dq_cow_list_publishes_changes/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_cow_probe/A = allocate(/obj/item/dq_cow_probe, T)
	// state_changed() with a var name probes the var's readers once: the write published.
	var/probes = GLOB.plan_reader_probes
	TEST_ASSERT(A.add_words("x"), "the first write")
	TEST_ASSERT_EQUAL(GLOB.plan_reader_probes - probes, 1, "the first write, the one that copies, published the change")
	probes = GLOB.plan_reader_probes
	TEST_ASSERT(A.add_words("y"), "the second write")
	TEST_ASSERT_EQUAL(GLOB.plan_reader_probes - probes, 1, "every write publishes")
	TEST_ASSERT_EQUAL(A.words_version, 2, "and bumps the version")
	probes = GLOB.plan_reader_probes
	TEST_ASSERT(!A.remove_words("not there"), "a removal that finds nothing")
	TEST_ASSERT_EQUAL(GLOB.plan_reader_probes - probes, 0, "changes nothing and publishes nothing")

/datum/unit_test/dq_cow_list_keeps_a_given_list

/datum/unit_test/dq_cow_list_keeps_a_given_list/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_cow_probe/A = allocate(/obj/item/dq_cow_probe, T)
	var/list/own = list("one")
	A.set_words(own)
	TEST_ASSERT(A.add_words("two"), "a write after the list was replaced")
	TEST_ASSERT(A.words == own, "a list the instance was given is edited in place, never copied")

// A type's trait block is the same form for a datum: shared by every instance of the type until one writes (set_trait), then that holder
// has its own copy in a row of per_type_copies, dropped with the holder by engine_forget().

/datum/unit_test/dq_cow_trait_shared_until_written

/datum/unit_test/dq_cow_trait_shared_until_written/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_cow_probe/A = allocate(/obj/item/dq_cow_probe, T)
	var/obj/item/dq_cow_probe/B = allocate(/obj/item/dq_cow_probe, T)
	var/datum/type_trait/atom_rules/shared = atom_rules_of_type(A.type)
	TEST_ASSERT(atom_rules_of(A) == shared && atom_rules_of(B) == shared, "every instance reads the type's one trait block")
	TEST_ASSERT_NULL(per_type_copy_peek(A, ENTRY_ATOM_RULES), "a read made no copy")
	var/old_price = atom_rules_of(B).price_tag
	var/before = per_type_copy_count(ENTRY_ATOM_RULES)

	TEST_ASSERT(A.set_price_tag(77), "the first write changes the value")
	TEST_ASSERT(atom_rules_of(A) != shared, "the first write gave A its own copy")
	TEST_ASSERT_EQUAL(atom_rules_of(A).price_tag, 77, "A reads its written value")
	TEST_ASSERT_EQUAL(per_type_copy_count(ENTRY_ATOM_RULES), before + 1, "one row was made")
	var/datum/type_trait/atom_rules/mine = atom_rules_of(A)
	TEST_ASSERT(A.set_price_tag(78), "a second write")
	TEST_ASSERT_EQUAL(atom_rules_of(A).price_tag, 78, "A reads its second value")
	TEST_ASSERT_EQUAL(mine.price_tag, 77, "a shared variant is never written in place: the second write moved A to another")
	TEST_ASSERT_EQUAL(per_type_copy_count(ENTRY_ATOM_RULES), before + 1, "still one row")

	TEST_ASSERT(atom_rules_of(B) == shared, "B still reads the shared block")
	TEST_ASSERT_EQUAL(atom_rules_of(B).price_tag, old_price, "B's value is unchanged")
	TEST_ASSERT_EQUAL(shared.price_tag, old_price, "the shared block did not change")
	var/obj/item/dq_cow_probe/C = allocate(/obj/item/dq_cow_probe, T)
	TEST_ASSERT(atom_rules_of(C) == shared, "an instance made after the write still reads the shared block")
	TEST_ASSERT(!A.set_price_tag(78), "writing the value it already has changes nothing")
	TEST_ASSERT_NULL(per_type_copy_peek(B, ENTRY_ATOM_RULES), "writing A made no row for B")

/datum/unit_test/dq_cow_trait_freed_with_holder

/datum/unit_test/dq_cow_trait_freed_with_holder/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_cow_probe/A = allocate(/obj/item/dq_cow_probe, T)
	var/before = per_type_copy_count(ENTRY_ATOM_RULES)
	A.set_price_tag(5)
	var/slot = A.handle_slot
	TEST_ASSERT(slot, "the writer has a slot")
	TEST_ASSERT_EQUAL(per_type_copy_count(ENTRY_ATOM_RULES), before + 1, "the row exists")
	qdel(A)
	TEST_ASSERT_EQUAL(per_type_copy_count(ENTRY_ATOM_RULES), before, "a destroyed holder leaves no row")
	TEST_ASSERT_NULL(GLOB.per_type_copies[ENTRY_ATOM_RULES]?[slot], "the row at its slot is gone")

/// Holders that make the same write to the same trait share one interned variant (every item of a blueprint sets the same fields): no copy each.
/datum/unit_test/dq_cow_trait_same_write_shares_a_variant

/datum/unit_test/dq_cow_trait_same_write_shares_a_variant/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_cow_probe/A = allocate(/obj/item/dq_cow_probe, T)
	var/obj/item/dq_cow_probe/B = allocate(/obj/item/dq_cow_probe, T)
	var/obj/item/dq_cow_probe/C = allocate(/obj/item/dq_cow_probe, T)
	var/datum/type_trait/atom_rules/shared = atom_rules_of_type(A.type)
	A.set_price_tag(4242)
	B.set_price_tag(4242)
	TEST_ASSERT(atom_rules_of(A) == atom_rules_of(B), "the same write gives both holders the one variant")
	TEST_ASSERT(atom_rules_of(A) != shared, "not the type's own block")
	TEST_ASSERT(atom_rules_of(C) == shared && shared.price_tag != 4242, "a holder that did not write reads the type's block, unchanged")
	B.set_price_tag(4343)
	TEST_ASSERT_EQUAL(atom_rules_of(A).price_tag, 4242, "B's next write leaves A's value alone")
	TEST_ASSERT_EQUAL(atom_rules_of(B).price_tag, 4343, "and B reads its own")
	var/datum/type_trait/atom_rules/own = type_trait_own(A, ENTRY_ATOM_RULES)
	TEST_ASSERT(own != atom_rules_of(B) && own.price_tag == 4242, "a private copy taken from a variant starts from its values")
