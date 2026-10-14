// Declared lifetimes (code/engine/lifeforms/lifetimes.dm): owns_one on a plain datum, lives_while() scopes, on_ending() and the caused
// endings with their ended notice.

/datum/dq_life_part
	var/label = "part"

/// A plain datum that owns a child: its starts = runs from New(), and its destruction deletes the child.
/datum/dq_life_owner
	var/datum/dq_life_part/part = null

CAPABILITIES(/datum/dq_life_owner)
	owns_one(nameof(part), /datum/dq_life_part, starts = /datum/dq_life_part)

/// A window-like record that lives while its host does, and while it is wanted.
/datum/dq_life_window
	var/datum/host = null
	var/wanted = TRUE
	var/list/endings = null

TRACKED(/datum/dq_life_window, wanted)

CAPABILITIES(/datum/dq_life_window)
	param(nameof(host))
	lives_while(nameof(host))
	lives_while(nameof(wanted))
	on_ending(PROC_REF(ending))

/datum/dq_life_window/proc/ending(cause, datum/by)
	LAZYADD(endings, cause)
	GLOB.dq_life_endings += cause

GLOBAL_LIST_EMPTY(dq_life_endings)
GLOBAL_LIST_EMPTY(dq_life_heard)

/obj/item/dq_life_cell
	name = "life cell"

/datum/dq_life_listener/proc/heard(datum/act/notice/A)
	var/datum/notice/ended/N = A
	GLOB.dq_life_heard += list(list(N.cause, N.by))

/datum/unit_test/dq_lifeform_lifetimes

/datum/unit_test/dq_lifeform_lifetimes/Run()
	GLOB.dq_life_endings.Cut()
	GLOB.dq_life_heard.Cut()
	var/datum/dq_life_owner/owner = new
	TEST_ASSERT_NOTNULL(owner.part, "owns_one(starts =) makes the child of a plain datum in New()")
	var/datum/dq_life_part/child = owner.part
	qdel(owner)
	TEST_ASSERT(QDELETED(child), "a plain datum's owned child is deleted with it")

	var/datum/dq_life_owner/host = new
	var/datum/dq_life_window/W = make(/datum/dq_life_window, host = host)
	TEST_ASSERT(!QDELETED(W), "a scoped record lives while its scope holds")
	qdel(host)
	TEST_ASSERT(QDELETED(W), "it ends when its host ends")
	TEST_ASSERT_EQUAL(GLOB.dq_life_endings[length(GLOB.dq_life_endings)], END_OWNER, "with the cause END_OWNER, through on_ending()")

	var/datum/dq_life_owner/host2 = new
	var/datum/dq_life_window/W2 = make(/datum/dq_life_window, host = host2)
	W2.set_wanted(FALSE)
	TEST_ASSERT(QDELETED(W2), "a scope condition that turns false ends it")
	TEST_ASSERT_EQUAL(GLOB.dq_life_endings[length(GLOB.dq_life_endings)], END_SCOPE, "with the cause END_SCOPE")
	qdel(host2)

	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/datum/dq_life_listener/L = new
	var/list/cases = list(
		list(GLOBAL_PROC_REF(spent), END_SPENT),
		list(GLOBAL_PROC_REF(consumed), END_CONSUMED),
		list(GLOBAL_PROC_REF(destroyed), END_DESTROYED),
		list(GLOBAL_PROC_REF(dissolved), END_DISSOLVED))
	for(var/list/each as anything in cases)
		var/obj/item/dq_life_cell/cell = allocate(/obj/item/dq_life_cell, T)
		observe(cell, /datum/notice/ended, L, then(TYPE_PROC_REF(/datum/dq_life_listener, heard)))
		TEST_ASSERT(call(each[1])(cell, user), "the verb ended it")
		TEST_ASSERT(QDELETED(cell), "and it is gone")
		var/list/heard = GLOB.dq_life_heard[length(GLOB.dq_life_heard)]
		TEST_ASSERT_EQUAL(heard[1], each[2], "the ended notice carries the verb's cause")
		TEST_ASSERT_EQUAL(heard[2], user, "and who caused it")
	var/obj/item/dq_life_cell/timed = allocate(/obj/item/dq_life_cell, T)
	observe(timed, /datum/notice/ended, L, then(TYPE_PROC_REF(/datum/dq_life_listener, heard)))
	qdel(timed)
	var/list/last = GLOB.dq_life_heard[length(GLOB.dq_life_heard)]
	TEST_ASSERT_EQUAL(last[1], END_ENGINE, "an ending no verb named is END_ENGINE")
	qdel(L)
