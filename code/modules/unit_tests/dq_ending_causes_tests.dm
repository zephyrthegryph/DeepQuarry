// The audited caused endings (code/engine/lifeforms/lifetimes.dm; tools/codemods/ending_fix.py): the verbs the audit added (lapsed(),
// replaced_by(), ended_with()), the detail destroyed() carries, and content paths whose cause the audit changed.

/datum/unit_test/dq_ending_causes

/datum/unit_test/dq_ending_causes/Run()
	GLOB.dq_life_heard.Cut()
	var/turf/T = dq_containment_floor()
	var/datum/dq_life_listener/L = new
	var/obj/item/dq_life_cell/successor = allocate(/obj/item/dq_life_cell, T)
	var/obj/item/dq_life_cell/owner = allocate(/obj/item/dq_life_cell, T)
	var/list/cases = list(
		list(GLOBAL_PROC_REF(lapsed), END_EXPIRED, null),
		list(GLOBAL_PROC_REF(replaced_by), END_REPLACED, successor),
		list(GLOBAL_PROC_REF(ended_with), END_OWNER, owner))
	for(var/list/each as anything in cases)
		var/obj/item/dq_life_cell/cell = allocate(/obj/item/dq_life_cell, T)
		observe(cell, /datum/notice/ended, L, then(TYPE_PROC_REF(/datum/dq_life_listener, heard)))
		TEST_ASSERT(call(each[1])(cell, each[3]), "[each[1]] ended it")
		TEST_ASSERT(QDELETED(cell), "[each[1]]: it is gone")
		var/list/heard = GLOB.dq_life_heard[length(GLOB.dq_life_heard)]
		TEST_ASSERT_EQUAL(heard[1], each[2], "[each[1]]: the ended notice carries its cause")
		TEST_ASSERT_EQUAL(heard[2], each[3], "[each[1]]: and the successor or owner as `by`")

	// destroyed(thing, by, cause): the cause is the notice's detail.
	var/obj/item/dq_life_cell/burnt = allocate(/obj/item/dq_life_cell, T)
	var/datum/dq_ending_detail/D = new
	observe(burnt, /datum/notice/ended, D, then(TYPE_PROC_REF(/datum/dq_ending_detail, heard)))
	destroyed(burnt, null, BURN)
	TEST_ASSERT_EQUAL(D.cause, END_DESTROYED, "destroyed() ends with END_DESTROYED")
	TEST_ASSERT_EQUAL(D.detail, BURN, "and names what destroyed it")

	// Content: cash worth nothing more is spent (cash.dm adjust_worth).
	var/obj/item/spacecash/cash = allocate(/obj/item/spacecash, T)
	observe(cash, /datum/notice/ended, L, then(TYPE_PROC_REF(/datum/dq_life_listener, heard)))
	cash.adjust_worth(-cash.worth)
	TEST_ASSERT(QDELETED(cash), "cash worth nothing is gone")
	TEST_ASSERT_EQUAL(GLOB.dq_life_heard[length(GLOB.dq_life_heard)][1], END_SPENT, "used-up cash is spent")

	// Content: a plain container's leftover contents end with it (atoms_movable.dm on_destroy), cause END_OWNER, by the container.
	var/obj/item/dq_life_cell/box = allocate(/obj/item/dq_life_cell, T)
	var/obj/item/dq_life_cell/inside = new(box)
	observe(inside, /datum/notice/ended, L, then(TYPE_PROC_REF(/datum/dq_life_listener, heard)))
	qdel(box)
	if(QDELETED(inside))
		var/list/heard = GLOB.dq_life_heard[length(GLOB.dq_life_heard)]
		TEST_ASSERT_EQUAL(heard[1], END_OWNER, "what a container still held ends with it, as END_OWNER")
		TEST_ASSERT_EQUAL(heard[2], box, "by the container")
	else
		qdel(inside)
	qdel(D)
	qdel(L)

/datum/dq_ending_detail
	var/cause
	var/detail

/datum/dq_ending_detail/proc/heard(datum/act/notice/A)
	var/datum/notice/ended/N = A
	cause = N.cause
	detail = N.detail
